/*
 * Copyright (C) 2023 Mai-Lapyst
 * 
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 * 
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/** 
 * Module for all routing things
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module miniweb.routing;

import miniweb.http;
import miniweb.config;
import miniweb.utils;
import miniweb.middlewares;
import async.utils : Option;

alias MaybeResponse = Option!Response;

import std.container : DList;

/**
 * UDA to annotate route handlers.
 */
struct Route {
    string route;

    private RouteMatcher toMatcher() {
        return new RouteMatcher(route);
    }
}

/// ditto
alias route = Route;

/** 
 * UDA to restrict a route handler to a specific http method.
 * Apply multiple different to combine them OR-wise.
 */
struct Method {
    HttpMethod method;
    string raw_method = null;

    this(HttpMethod method) {
        this.method = method;
    }

    this(string method) {
        this.method = HttpMethod.custom;
        this.raw_method = method;
    }

    private MethodMatcher toMatcher() {
        return new MethodMatcher(this);
    }
}

/// Restrict routehandler to HEAD requests; see $(REF Method)
enum Head = Method(HttpMethod.HEAD);

/// ditto
alias HEAD = Head;

/// Restrict routehandler to GET requests; see $(REF Method)
enum Get = Method(HttpMethod.GET);

/// ditto
alias GET = Get;

/// Restrict routehandler to POST requests; see $(REF Method)
enum Post = Method(HttpMethod.POST);

/// ditto
alias POST = Post;

/// Restrict routehandler to PATCH requests; see $(REF Method)
enum Patch = Method(HttpMethod.PATCH);

/// ditto
alias PATCH = Patch;

/// Restrict routehandler to DELETE requests; see $(REF Method)
enum Delete = Method(HttpMethod.DELETE);

/// ditto
alias DELETE = Delete;

/**
 * UDA to restrict a route handler to run only when a header is present when applied to a function.
 */
struct RequireHeader {
    string name;

    private HeaderMatcher toMatcher() {
        return new HeaderMatcher(name);
    }
}

/**
 * UDA to take out the value of the header when applied to a handler's parameter (only for `string` and `string[]`).
 */
struct Header {
    string name;
}

// ================================================================================

/// Checks a condition if the request can be handled
interface Matcher {
    bool matches(Request req, ref RoutingStore store);
}

/// Checks if the request matches a specific route
private class RouteMatcher : Matcher {
    private string route;

    this(string route) {
        this.route = route;
    }

    bool matches(Request req, ref RoutingStore store) {
        return req.getURI().path == route;
    }
}

/// Checks if the request has a specific HTTP method
private class MethodMatcher : Matcher {
    private Method method;

    this(Method method) {
        this.method = method;
    }

    bool matches(Request req, ref RoutingStore store) {
        if (req.getMethod() != method.method) {
            store.non_match_cause = NonMatchCause.Method;
            return false;
        }
        if (
            (method.method == HttpMethod.custom)
            && (req.getRawMethod() != method.raw_method)
        ) {
            store.non_match_cause = NonMatchCause.Method;
            return false;
        }
        return true;
    }
}

/// Checks if the request has a specific HTTP header set
private class HeaderMatcher : Matcher {
    private string name;

    this(string name) {
        this.name = name;
    }

    bool matches(Request req, ref RoutingStore store) {
        if (req.headers.has(name)) {
            return true;
        }
        store.non_match_cause = NonMatchCause.Header;
        return false;
    }
}

/// Container to store delegates / functions which are route handlers with the returntype `T`.
private struct Callable(T) {
    void set(T function(Request req) fn) pure nothrow @nogc @safe {
        () @trusted { this.fn = fn; }();
        this.kind = Kind.FN;
    }
    void set(T delegate(Request req) dg) pure nothrow @nogc @safe {
        () @trusted { this.dg = dg; }();
        this.kind = Kind.DG;
    }

    T opCall(Request req) {
        final switch (this.kind) {
            case Kind.FN: return fn(req);
            case Kind.DG: return dg(req);
            case Kind.NO: throw new Exception("Called uninitialzed Callable!");
        }
    }
private:
	enum Kind { NO, FN, DG }
	Kind kind = Kind.NO;
	union {
		T function(Request req) fn;
		T delegate(Request req) dg;
	}
}

/// Container for route handlers
private struct Handler {
    Response opCall(Request req) {
        final switch (kind) {
            case Kind.NONE:
                throw new Exception("Tried to call unintialized handler!");
            case Kind.VOID: {
                this.cbVoid(req);
                return Response.build_200_OK(); // TODO: build an actual correct response!
            }
            case Kind.RESPONSE: {
                return this.cbResponse(req);
            }
        }
    }

    static Handler from(Callable!void cb) {
        Handler h;
        h.kind = Kind.VOID;
        h.cbVoid = cb;
        return h;
    }
    static Handler from(Callable!Response cb) {
        Handler h;
        h.kind = Kind.RESPONSE;
        h.cbResponse = cb;
        return h;
    }

private:
    enum Kind{ NONE, VOID, RESPONSE }
    Kind kind = Kind.NONE;
    union {
        Callable!void cbVoid;
        Callable!Response cbResponse;
    }
}

/// Entry in the routing table
private struct RouteEntry {
    Matcher[] matchers;
    Handler handler;
    DList!Middleware middlewares;

    bool matches(Request req, ref RoutingStore store) {
        foreach (m; matchers) {
            if (!m.matches(req, store)) {
                return false;
            }
        }
        return true;
    }
}

private enum NonMatchCause {
    None,
    Method,
    Header,
}

/// Stores informations while routing
private struct RoutingStore {
    NonMatchCause non_match_cause = NonMatchCause.None;
}

/** 
 * The request router; used to route request, find handlers and calling them
 */
class Router {
    private RouteEntry[] routes;
    private Callable!MaybeResponse[string] middlewares;

    Response route(Request req, ServerConfig conf) {
        RoutingStore store;
        foreach (ent; routes) {
            if (ent.matches(req, store)) {
                foreach (mw_spec; ent.middlewares) {
                    import std.stdio;
                    writeln("try middleware... ", mw_spec);
                    final switch (mw_spec.kind) {
                        case Middleware.Kind.NO:
                            throw new Exception("Tried to call invalid middleware");
                        case Middleware.Kind.NAMED: {
                            auto mw_p = mw_spec.name in middlewares;
                            if (mw_p !is null) {
                                auto r = (*mw_p)(req);
                                if (r.isSome()) {
                                    return r.take();
                                }
                            }
                            break;
                        }
                        case Middleware.Kind.FN:
                        case Middleware.Kind.DG: {
                            auto r = mw_spec(req);
                            if (r.isSome()) {
                                return r.take();
                            }
                            break;
                        }
                    }
                }

                return ent.handler(req);
            } else {

            }
        }

        if (store.non_match_cause == NonMatchCause.Method && !conf.treat_405_as_404) {
            return new Response(HttpResponseCode.Method_Not_Allowed_405);
        }
        else if (store.non_match_cause == NonMatchCause.Header && !conf.treat_required_header_failure_as_404) {
            return new Response(HttpResponseCode.Bad_Request_400);
        }

        return null;
    }

    void addRoute(T)(Matcher[] matchers, DList!Middleware mws, T delegate(Request) dg) {
        Callable!T cb;
        cb.set(dg);
        routes ~= RouteEntry(matchers, Handler.from(cb), mws);
    }

    void addMiddleware(string name, MaybeResponse delegate(Request) dg) {
        Callable!MaybeResponse cb;
        cb.set(dg);
        middlewares[name] = cb;
    }

    /// Sorts all routes so we route correctly
    void sortRoutes() {
        import std.algorithm, std.array, std.stdio;

        // Currently simply sort by count of matchers:
        // The more matchers are present, the lower the routeentry will be positioned
        // so more specific routeentries will be checked first.
        alias compareRoute = (x, y) {
            return x.matchers.length > y.matchers.length;
        };
        routes.sort!compareRoute;

        debug (minweb_router_sort) {
            writeln("[miniweb.routing.Router.sortRoutes] Sorted routes:");
            foreach (r; routes) {
                writeln("[miniweb.routing.Router.sortRoutes]  - ", r);
            }
        }
    }
}

/**
 * Helper template to "compile" code like `"req,req.headers,"` to then be used in a call
 * to a route handler to satisfy all its parameters correctly
 * 
 * Params:
 *   fn = the route handler function
 *   paramInfos = parameterinfos of `fn`; aqquired from $(REF miniweb.utils.GetParameterInfo)
 */
private template MakeCallDispatcher(alias fn) {
    import std.traits;

    alias storageclasses = ParameterStorageClassTuple!fn;
    alias types = Parameters!fn;
    alias identifiers = ParameterIdentifierTuple!fn;

    template Impl(size_t i = 0) {
        static if (i == types.length) {
            enum Impl = "";
        } else {
            alias tail = Impl!(i+1);

            alias paramSc = storageclasses[i];
            alias paramTy = types[i .. i+1];
            alias paramId = identifiers[i];

            alias plainParamTy = Unconst!paramTy;

            alias paramUdas = __traits(getAttributes, paramTy);

            import std.conv : to;
            debug(miniweb_mkCallDisp) {
                pragma(
                    msg,
                    "- fn: " ~ fullyQualifiedName!fn
                        ~ " | ty:" ~ fullyQualifiedName!paramTy
                        ~ " | id:" ~ paramId
                        ~ " | sc:" ~ to!string(paramSc)
                        ~ " | udas: ", paramUdas
                );
            }

            static if (paramSc != ParameterStorageClass.none) {
                static assert(
                    0, "Cannot compile dispatcher: disallowed storageclass `" ~ to!string(paramSc)[0 .. $-1] ~ "`"
                        ~ " for parameter `" ~ paramId ~ "`"
                        ~ " on function `" ~ fullyQualifiedName!fn ~ "`"
                );
            }

            import miniweb.utils : filterUDAs, containsUDA;
            import std.meta : AliasSeq;

            static if (is(plainParamTy == Request)) {
                enum Impl = "req," ~ tail;
            }
            else static if (is(plainParamTy == HeaderBag)) {
                enum Impl = "req.headers," ~ tail;
            }
            else static if (is(plainParamTy == URI)) {
                enum Impl = "req.uri," ~ tail;
            }
            else static if (is(plainParamTy == QueryParamBag)) {
                enum Impl = "req.uri.queryparams," ~ tail;
            }
            else static if (is(plainParamTy == HttpMethod)) {
                enum Impl = "req.method," ~ tail;
            }
            else static if (containsUDA!(Header, paramUdas)) {
                alias header_udas = filterUDAs!(Header, paramUdas);
                static if (header_udas.length != 1) {
                    static assert(
                        0, "Cannot compile dispatcher: parameter `" ~ paramId ~ "` was annotated with multiple instances of `@Header`"
                    );
                }
                else static if (is(plainParamTy == string)) {
                    enum Impl = "req.headers.getOne(\"" ~ header_udas[0].name ~ "\")," ~ tail;
                }
                else static if (is(plainParamTy == string[])) {
                    enum Impl = "req.headers.get(\"" ~ header_udas[0].name ~ "\")," ~ tail;
                }
                else {
                    static assert(
                        0, "Cannot compile dispatcher: parameter `" ~ paramId ~ "` was annotated with `@Header`,"
                            ~ " but is not of type `string` or `string[]`: " ~ fullyQualifiedName!paramTy
                    );
                }
            }
            else static if (hasStaticMember!(plainParamTy, "fromRequest")) {
                alias fromRequest = __traits(getMember, plainParamTy, "fromRequest");
                static assert (
                    is(ReturnType!fromRequest == plainParamTy),
                    "Cannot compile dispatcher: type `" ~ fullyQualifiedName!paramTy ~ "`"
                        ~ " that has a static function `fromRequest` needs to have itself as returntype but had"
                        ~ " `" ~ fullyQualifiedName!(ReturnType!fromRequest) ~ "`"
                );
                static assert (
                    is(Parameters!fromRequest == AliasSeq!( Request )),
                    "Cannot compile dispatcher: type `" ~ fullyQualifiedName!paramTy ~ "`"
                        ~ " that has a static function `fromRequest` needs to have one parameter of type `Request`"
                );
                enum Impl = "imported!\"" ~ moduleName!plainParamTy ~ "\"." ~ plainParamTy.stringof ~ ".fromRequest(req)," ~ tail;
            }
            else {
                static assert(
                    0, "Cannot compile dispatcher: unknown type `" ~ fullyQualifiedName!paramTy ~ "`"
                        ~ " for parameter `" ~ paramId ~ "`"
                        ~ " on function `" ~ fullyQualifiedName!fn ~ "`"
                );
            }
        }
    }

    enum MakeCallDispatcher = Impl!();
}

private void addRoute(alias fn, string args, matcher_udas...)(Router r, DList!Middleware middlewares) {
    import std.traits : fullyQualifiedName, getUDAs, hasUDA, ReturnType;

    pragma(msg, "Creating route handler on `" ~ fullyQualifiedName!fn ~ "`, calling with: `" ~ args ~ "`");
    pragma(msg, "  Matchers: ");
    static foreach (uda; matcher_udas) {
        pragma(msg, "   - ", uda);
    }
    static if (hasUDA!(fn, Middleware)) {
        static foreach (mw_uda; getUDAs!(fn, Middleware)) {
            pragma(msg, "   - ", mw_uda);
        }
    }

    Matcher[] matchers;
    static foreach (uda; matcher_udas) {
        matchers ~= uda.toMatcher();
    }

    r.addRoute(matchers, middlewares, (Request req) {
        static if (is(ReturnType!fn == void)) {
            mixin( "fn(" ~ args ~ ");" );
        } else static if (is(ReturnType!fn == Response)) {
            mixin( "return fn(" ~ args ~ ");" );
        } else {
            static assert(0, "`" ~ fullyQualifiedName!fn ~ "` needs either void or Response as return type");
        }
    });
}

/**
 * Initializes a router instance.
 * 
 * Provide the generic varidic parameter `Modules` to search for route handlers.
 * 
 * Params:
 *   conf = the server configuration
 * 
 * Returns: a new router with all routes registered.
 */
Router initRouter(Modules...)(ServerConfig conf) {
    import std.meta : AliasSeq;
    import std.traits;

    Router r = new Router();

    foreach (mod; Modules) {
        foreach (fn; getSymbolsByUDA!(mod, RegisterMiddleware)) {
            static assert(isFunction!fn, "`" ~ __traits(identifier, fn) ~ "` is annotated with @RegisterMiddleware but isn't a function");
            foreach (uda; getUDAs!(fn, RegisterMiddleware)) {
                auto p = uda.name in r.middlewares;
                if (p !is null) {
                    assert(0, "Cannot register `" ~ fullyQualifiedName!fn ~ "` as middleware `" ~ uda.name ~ "` since a same named middleware already exists");
                }

                enum args = MakeCallDispatcher!fn;
                static if (is(ReturnType!fn == void)) {
                    pragma(msg, "Creating middleware handler on `" ~ fullyQualifiedName!fn ~ "` named '" ~ uda.name ~ "', calling with: `" ~ args ~ "`");
                    r.addMiddleware(uda.name, (Request req) {
                        mixin( "fn(" ~ args ~ ");" );
                        return MaybeResponse.none();
                    });
                }
                static if (is(ReturnType!fn == Option!Response)) {
                    pragma(msg, "Creating middleware handler on `" ~ fullyQualifiedName!fn ~ "` named '" ~ uda.name ~ "', calling with: `" ~ args ~ "`");
                    r.addMiddleware(uda.name, (Request req) {
                        mixin( "return fn(" ~ args ~ ");" );
                    });
                }
                else {
                    static assert(0, "`" ~ fullyQualifiedName!fn ~ "` needs to have either void or Option!Response as returntype");
                }
            }
        }

        foreach (fn; getSymbolsByUDA!(mod, Route)) {
            static assert(isFunction!fn, "`" ~ __traits(identifier, fn) ~ "` is annotated with @Route but isn't a function");

            static assert(!hasUDA!(fn, Header), "`@Header` cannot be applied to a function directly: " ~ fullyQualifiedName!fn);

            // TODO: support various ways a handler can be called...

            enum args = MakeCallDispatcher!fn;

            DList!Middleware middlewares;
            foreach (mw_uda; getUDAs!(fn, Middleware)) {
                if (mw_uda.kind == Middleware.Kind.NAMED) {
                    auto p = mw_uda.name in r.middlewares;
                    if (p is null) {
                        assert(0, "Cannot use middleware `" ~ mw_uda.name ~ "` on `" ~ fullyQualifiedName!fn ~ "` since no such middleware exists");
                    }
                }

                middlewares.insertBack(mw_uda);
            }

            foreach (r_uda; getUDAs!(fn, Route)) {
                static if (hasUDA!(fn, Method)) {
                    foreach (m_uda; getUDAs!(fn, Method)) {
                        static if (hasUDA!(fn, RequireHeader)) {
                            foreach (rh_uda; getUDAs!(fn, RequireHeader)) {
                                addRoute!(fn, args, AliasSeq!( r_uda, m_uda, rh_uda ))(r, middlewares);
                            }
                        } else {
                            addRoute!(fn, args, AliasSeq!( r_uda, m_uda ))(r, middlewares);
                        }
                    }
                } else {
                    static if (hasUDA!(fn, RequireHeader)) {
                        foreach (rh_uda; getUDAs!(fn, RequireHeader)) {
                            addRoute!(fn, args, AliasSeq!( r_uda, rh_uda ))(r, middlewares);
                        }
                    } else {
                        addRoute!(fn, args, AliasSeq!( r_uda ))(r, middlewares);
                    }
                }
            }

        }
    }

    r.sortRoutes();

    return r;
}
