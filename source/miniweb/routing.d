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
}

/// ditto
alias route = Route;

/// Matcher to check if a request can be handled
private struct Matcher {
    private string str;

    bool matches(Request req) {
        return req.getURI().path == str;
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
    Matcher m;
    Handler handler;
    DList!Middleware middlewares;
}

/** 
 * The request router; used to route request, find handlers and calling them
 */
class Router {
    private DList!RouteEntry routes;
    private Callable!MaybeResponse[string] middlewares;

    Response route(Request req) {
        foreach (ent; routes) {
            if (ent.m.matches(req)) {
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
            }
        }
        return null;
    }

    void addRoute(T)(Route r, DList!Middleware mws, T delegate(Request) dg) {
        Callable!T cb;
        cb.set(dg);
        routes.insertBack(
            RouteEntry(
                Matcher(r.route), Handler.from(cb), mws
            )
        );
    }

    void addMiddleware(string name, MaybeResponse delegate(Request) dg) {
        Callable!MaybeResponse cb;
        cb.set(dg);
        middlewares[name] = cb;
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
private template MakeCallDispatcher(alias fn, paramInfos...) {
    import std.traits : fullyQualifiedName, Unconst, ParameterStorageClass;
    static if (paramInfos.length < 4) {
        enum MakeCallDispatcher = "";
    }
    else {
        alias tail = MakeCallDispatcher!(fn, paramInfos[4 .. $]);
        alias info = paramInfos[0 .. 4];

        alias paramSc = info[0];
        alias paramTy = info[1];
        alias paramId = info[2];

        alias plainParamTy = Unconst!paramTy;

        import std.conv : to;
        debug(miniweb_mkCallDisp) {
            pragma(
                msg,
                "- fn: " ~ fullyQualifiedName!fn
                    ~ " | ty:" ~ fullyQualifiedName!paramTy
                    ~ " | id:" ~ paramId
                    ~ " | sc:" ~ to!string(paramSc)
            );
        }

        static if (paramSc != ParameterStorageClass.none) {
            static assert(
                0, "Cannot compile dispatcher: disallowed storageclass `" ~ to!string(paramSc)[0 .. $-1] ~ "`"
                    ~ " for parameter `" ~ paramId ~ "`"
                    ~ " on function `" ~ fullyQualifiedName!fn ~ "`"
            );
        }

        static if (is(plainParamTy == Request)) {
            enum MakeCallDispatcher = "req," ~ tail;
        }
        else static if (is(plainParamTy == HeaderBag)) {
            enum MakeCallDispatcher = "req.headers," ~ tail;
        }
        else static if (is(plainParamTy == URI)) {
            enum MakeCallDispatcher = "req.uri," ~ tail;
        }
        else static if (is(plainParamTy == QueryParamBag)) {
            enum MakeCallDispatcher = "req.uri.queryparams," ~ tail;
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

                alias infos = GetParameterInfo!fn;
                alias args = MakeCallDispatcher!(fn, infos);
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

            // TODO: support various ways a handler can be called...

            alias infos = GetParameterInfo!fn;
            alias args = MakeCallDispatcher!(fn, infos);

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
                r.addRoute(r_uda, middlewares, (Request req) {
                    pragma(msg, "Creating route handler on `" ~ fullyQualifiedName!fn ~ "`, calling with: `" ~ args ~ "`");
                    pragma(msg, "  Routing spec is: ", r_uda);
                    pragma(msg, "  Middlewares applied: ");
                    static foreach (mw_uda; getUDAs!(fn, Middleware)) {
                        pragma(msg, "   - ", mw_uda);
                    }
                    static if (is(ReturnType!fn == void)) {
                        mixin( "fn(" ~ args ~ ");" );
                    } else static if (is(ReturnType!fn == Response)) {
                        mixin( "return fn(" ~ args ~ ");" );
                    } else {
                        static assert(0, "`" ~ fullyQualifiedName!fn ~ "` needs either void or Response as return type");
                    }
                });
            }

        }
    }

    return r;
}
