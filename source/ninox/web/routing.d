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

module ninox.web.routing;

import ninox.web.http;
import ninox.web.config;
import ninox.web.utils;
import ninox.web.middlewares;
import ninox.web.client : NinoxWebRequest;
import ninox.std.optional : Optional;

alias MaybeResponse = Optional!Response;

import std.container : DList;
import std.regex : Regex, regex;

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

/// Restrict routehandler to PUT requests; see $(REF Method)
enum Put = Method(HttpMethod.PUT);

/// ditto
alias PUT = Put;

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
    string name = null;
}

/**
 * UDA to take out the value of the query params when applied to a handler's parameter (only for `string` and `string[]`).
 */
struct QueryParam {
    string name = null;
    string defaultValue = null;
}

/**
 * UDA to take out the value of the path params when applied to a handler's parameter (only for `string`).
 */
struct PathParam {
    string name = null;
}

/** 
 * UDA to specify which mimetypes a handler produces;
 * also used to restrict a handler to various types that can be then specifed via the "Accept" header
 */
struct Produces {
    string[] types;

    this(string type) {
        this.types = [type];
    }

    this(string[] types) {
        this.types = types;
    }
}

/** 
 * UDA to specify which mimetypes a handler consumes;
 * also used to restrict a handler to various types of input via the "Content-Type" header
 */
struct Consumes {
    string[] types;

    this(string type) {
        this.types = [type];
    }

    this(string[] types) {
        this.types = types;
    }
}

/** 
 * UDA to specify if the route should only be available on certain hosts;
 * uses the "Host" header to determine the host
 */
struct RequireHost {
    string pattern;

    this() @disable;

    this(string pattern) {
        this.pattern = pattern;
    }

    private HostMatcher toMatcher() {
        return new HostMatcher(this.pattern);
    }
}

/// ditto
alias Host = RequireHost;

// ================================================================================

/// Checks a condition if the request can be handled
interface Matcher {
    bool matches(NinoxWebRequest req, ref RoutingStore store);
}

/// Checks if the request matches a specific route
private class RouteMatcher : Matcher {
    private Regex!char re;
    private string[] param_names;

    this(string route) {
        // this.route = route;
        this.makeRegex(route);
    }

    private void makeRegex(string route) {
        string res = "";
        string param_name = "";
        bool is_param = false;

        this.param_names = [];

        foreach (char c; route) {
            if (!is_param) {
                if (c == ':') {
                    is_param = true;
                    continue;
                }
            }
            else {
                if (
                    (c >= 'a' && c <= 'z') ||
                    (c >= 'A' && c <= 'Z') ||
                    (c == '_') ||
                    (c >= '0' && c <= '9')
                ) {
                    param_name ~= c;
                    continue;
                }
                else {
                    res ~= "(?P<" ~ param_name ~ ">[^\\/]*)";
                    this.param_names ~= param_name;
                    param_name = "";
                    is_param = false;
                }
            }

            if (c == '?') {
                res ~= c;
            } else {
                import std.conv : to;
                import std.regex : escaper;
                res ~= to!string( escaper([c]) );
            }
        }

        if (is_param) {
            res ~= "(?P<" ~ param_name ~ ">.*)";
            this.param_names ~= param_name;
        }

        res = "^" ~ res ~ "$";

        this.re = regex(res);
    }

    bool matches(NinoxWebRequest req, ref RoutingStore store) {
        import std.regex : matchFirst, Captures;
        auto res = matchFirst(req.http.uri.path, this.re);
        if (res) {
            foreach (string key; this.param_names) {
                req.pathParams[key] = res[key];
            }
            return true;
        }
        return false;
    }
}

/// Checks if the request has a specific HTTP method
private class MethodMatcher : Matcher {
    private Method method;

    this(Method method) {
        this.method = method;
    }

    bool matches(NinoxWebRequest req, ref RoutingStore store) {
        if (req.http.getMethod() != method.method) {
            store.non_match_cause = NonMatchCause.Method;
            return false;
        }
        if (
            (method.method == HttpMethod.custom)
            && (req.http.getRawMethod() != method.raw_method)
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

    bool matches(NinoxWebRequest req, ref RoutingStore store) {
        if (req.http.headers.has(name)) {
            return true;
        }
        store.non_match_cause = NonMatchCause.Header;
        return false;
    }
}

auto parseHeaderQualityList(string header) {
    import std.conv : to;
    import std.string : stripRight, strip;

    float[string] map;

    enum State { VALUE, PARAMS, QUANTITY_KEY, QUANTITY_VALUE }
    State state;
    string v, q;
    foreach (c; header) {
        if (c == ',') {
            // put v + q into map
            float f = (q == "") ? 1.0f : to!float(strip(q));
            if (f > 1.0f) { f = 1.0f; }
            else if (f < 0.0f) { f = 0.0f; }
            map[stripRight(v)] = f;
            v = "";
            q = "";
            state = State.VALUE;
            continue;
        }
        else if (c == ';') {
            // switch to state PARAMS
            state = State.PARAMS;
            continue;
        }

        final switch (state) {
            case State.VALUE: {
                if (v.length == 0 && (c == ' ' || c == '\t')) {
                    break;
                }
                v ~= c;
                break;
            }
            case State.PARAMS: {
                if (c == 'q') {
                    state = State.QUANTITY_KEY;
                }
                break;
            }
            case State.QUANTITY_KEY: {
                if (c == '=') {
                    state = State.QUANTITY_VALUE;
                }
                break;
            }
            case State.QUANTITY_VALUE: {
                q ~= c;
                break;
            }
        }
    }

    if (v.length > 0) {
        map[stripRight(v)] = (q == "") ? 1.0f : to!float(strip(q));
    }

    import std.array;
    import std.algorithm;
    return map.byPair.array.sort!"a[1]>b[1]".map!"a[0]";
}

/// Checks if the accepted formats of a request can be satisfied
private abstract class BaseMimeMatcher : Matcher {
    private string[] raw_products;
    private Regex!char[] products_matcher;

    this(string[] products) {
        foreach (v; products) {
            this.add(v);
        }
    }

    void add(string mime) {
        this.products_matcher ~= makeMimeRegex(mime);

        import std.string : count;
        if (mime.count('*') < 1) {
            this.raw_products ~= mime;
        }
    }

    static Regex!char makeMimeRegex(string mime) {
        string res = "^";
        foreach (char c; mime) {
            if (c == '*') {
                res ~= ".*";
            } else {
                import std.conv : to;
                import std.regex : escaper;
                res ~= to!string( escaper([c]) );
            }
        }
        res ~= "$";
        return regex(res);
    }

    protected bool canSatisfy(string type, out string __out) {
        import std.string : count;
        import std.regex : matchFirst;

        if (type.count!"a == '*'" > 0) {
            auto re = makeMimeRegex(type);
            foreach (p; raw_products) {
                if (matchFirst(p, re)) {
                    __out = p;
                    return true;
                }
            }
            return false;
        }
        else {
            import std.regex : matchFirst;
            foreach (Regex!char re; this.products_matcher) {
                if (matchFirst(type, re)) {
                    __out = type;
                    return true;
                }
            }
            return false;
        }
    }
}

private class AcceptMatcher : BaseMimeMatcher {
    this(string[] products) {
        super(products);
    }

    bool matches(NinoxWebRequest req, ref RoutingStore store) {
        if (!req.http.headers.has("Accept")) {
            store.non_match_cause = NonMatchCause.Accept;
            return false;
        }

        auto accept = parseHeaderQualityList(req.http.headers.getOne("Accept"));
        foreach (e; accept) {
            string res;
            if (this.canSatisfy(e, res)) {
                req.accepted_product = res;
                return true;
            }
        }

        store.non_match_cause = NonMatchCause.Accept;
        return false;
    }
}

private class ContentTypeMatcher : BaseMimeMatcher {
    this(string[] types) {
        super(types);
    }

    bool matches(NinoxWebRequest req, ref RoutingStore store) {
        if (!req.http.headers.has("Content-Type")) {
            // TODO: make a error code
            return false;
        }

        auto content_type_raw = req.http.headers.getOne("Content-Type");

        import std.string : split, strip;
        auto content_type = strip( content_type_raw.split(';')[0] );

        string __tmp;
        if (this.canSatisfy(content_type, __tmp)) {
            req.consumes = content_type;
            // TODO: copy all type parameters like charset to the request too
            return true;
        }

        // TODO: make a error code
        return false;
    }
}

/// Checks if the request is for a specific host
private class HostMatcher : Matcher {
    private Regex!char pattern;

    this(string pattern) {
        this.pattern = regex(pattern);
    }

    bool matches(NinoxWebRequest req, ref RoutingStore store) {
        if (!req.http.headers.has("Host")) {
            return false;
        }

        auto host = req.http.headers.getOne("Host");

        import std.regex : matchFirst;
        return cast(bool) matchFirst(host, this.pattern);
    }
}

// ================================================================================

struct Outcome {
    this(Response r) {
        this._kind = Kind.RESPONSE;
        this._response = r;
    }

    this(MaybeResponse r) {
        if (r.isSome()) {
            this._kind = Kind.RESPONSE;
            this._response = r.take();
        } else {
            this._kind = Kind.NO_RESPONSE;
        }
    }

    static Outcome from(Response r) {
        return Outcome(r);
    }

    static Outcome from(MaybeResponse r) {
        return Outcome(r);
    }

    static Outcome nextHandler() {
        auto o = Outcome();
        o._kind = Kind.TRY_NEXT_HANDLER;
        return o;
    }

    @property Kind kind() {
        return this._kind;
    }

    @property Response response() {
        if (this._kind == Kind.RESPONSE) {
            return this._response;
        }
        throw new Exception("Outcome was no response, cant request response form it then");
    }

private:
    enum Kind {
        INVALID, RESPONSE, NO_RESPONSE, TRY_NEXT_HANDLER
    }
    Kind _kind = Kind.INVALID;
    Response _response = null;
}

/// Container to store delegates / functions which are route handlers with the returntype `T`.
private struct Callable(T) {
    void set(T function(NinoxWebRequest req) fn) pure nothrow @nogc @safe {
        () @trusted { this.fn = fn; }();
        this.kind = Kind.FN;
    }
    void set(T delegate(NinoxWebRequest req) dg) pure nothrow @nogc @safe {
        () @trusted { this.dg = dg; }();
        this.kind = Kind.DG;
    }

    T opCall(NinoxWebRequest req) {
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
		T function(NinoxWebRequest req) fn;
		T delegate(NinoxWebRequest req) dg;
	}
}

/// Container for route handlers
private struct Handler {
    Outcome opCall(NinoxWebRequest req) {
        final switch (kind) {
            case Kind.NONE:
                throw new Exception("Tried to call unintialized handler!");
            case Kind.VOID: {
                this.cbVoid(req);
                return Outcome.from(Response.build_200_OK()); // TODO: build an actual correct response!
            }
            case Kind.RESPONSE: {
                return Outcome.from(this.cbResponse(req));
            }
            case Kind.OUTCOME: {
                return this.cbOutcome(req);
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
    static Handler from(Callable!Outcome cb) {
        Handler h;
        h.kind = Kind.OUTCOME;
        h.cbOutcome = cb;
        return h;
    }

private:
    enum Kind{ NONE, VOID, RESPONSE, OUTCOME }
    Kind kind = Kind.NONE;
    union {
        Callable!void cbVoid;
        Callable!Response cbResponse;
        Callable!Outcome cbOutcome;
    }
}

/// Entry in the routing table
private struct RouteEntry {
    Matcher[] matchers;
    Handler handler;
    DList!Middleware middlewares;

    bool matches(NinoxWebRequest req, ref RoutingStore store) {
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
    Accept,
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

    Response route(Request http_req, ServerConfig conf) {
        NinoxWebRequest req = new NinoxWebRequest(http_req);

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

                auto outcome = ent.handler(req);
                final switch (outcome.kind) {
                    case Outcome.Kind.INVALID: {
                        throw new Exception("Got invalid outcome from handler!");
                    }
                    case Outcome.Kind.RESPONSE: {
                        return outcome.response;
                    }
                    case Outcome.Kind.NO_RESPONSE: {
                        return null;
                    }
                    case Outcome.Kind.TRY_NEXT_HANDLER: {
                        // Try next handler.
                        // TODO: consider how we wanna react to middlewares modifing the request here...
                        continue;
                    }
                }
            } else {

            }
        }

        if (store.non_match_cause == NonMatchCause.Method && !conf.treat_405_as_404) {
            return new Response(HttpResponseCode.Method_Not_Allowed_405);
        }
        else if (store.non_match_cause == NonMatchCause.Header && !conf.treat_required_header_failure_as_404) {
            return new Response(HttpResponseCode.Bad_Request_400);
        }
        else if (store.non_match_cause == NonMatchCause.Accept && !conf.treat_406_as_404) {
            return new Response(HttpResponseCode.Not_Acceptable_406);
        }

        return null;
    }

    void addRoute(T)(Matcher[] matchers, DList!Middleware mws, T delegate(NinoxWebRequest) dg) {
        Callable!T cb;
        cb.set(dg);
        routes ~= RouteEntry(matchers, Handler.from(cb), mws);
    }

    void addMiddleware(string name, MaybeResponse delegate(NinoxWebRequest) dg) {
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

        debug (ninoxweb_router_sort) {
            writeln("[ninox.web.routing.Router.sortRoutes] Sorted routes:");
            foreach (r; routes) {
                writeln("[ninox.web.routing.Router.sortRoutes]  - ", r);
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
 *   paramInfos = parameterinfos of `fn`; aqquired from $(REF ninox.web.utils.GetParameterInfo)
 */
private template MakeCallDispatcher(alias fn) {
    import std.traits;

    alias storageclasses = ParameterStorageClassTuple!fn;
    alias types = Parameters!fn;
    alias identifiers = ParameterIdentifierTuple!fn;
    alias defaultvalues = ParameterDefaults!fn;

    template Impl(size_t i = 0, bool allowConsumes = true) {
        static if (i == types.length) {
            enum Impl = "";
        } else {
            alias tail = Impl!(i+1, true);

            alias paramSc = storageclasses[i];
            alias paramTy = types[i .. i+1];
            alias paramId = identifiers[i];
            alias paramDef = defaultvalues[i];

            alias plainParamTy = Unconst!paramTy;

            alias paramUdas = __traits(getAttributes, paramTy);

            import std.conv : to;
            debug(ninoxweb_mkCallDisp) {
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

            import ninox.web.utils : filterUDAs, containsUDA;
            import std.meta : AliasSeq;

            static if (is(plainParamTy == Request)) {
                enum Impl = "req.http," ~ tail;
            }
            else static if (is(plainParamTy == NinoxWebRequest)) {
                enum Impl = "req," ~ tail;
            }
            else static if (is(plainParamTy == HeaderBag)) {
                enum Impl = "req.http.headers," ~ tail;
            }
            else static if (is(plainParamTy == URI)) {
                enum Impl = "req.http.uri," ~ tail;
            }
            else static if (is(plainParamTy == QueryParamBag)) {
                enum Impl = "req.http.uri.queryparams," ~ tail;
            }
            else static if (is(plainParamTy == HttpMethod)) {
                enum Impl = "req.http.method," ~ tail;
            }
            else static if (containsUDA!(Header, paramUdas)) {
                alias header_udas = filterUDAs!(Header, paramUdas);
                static if (header_udas.length != 1) {
                    static assert(
                        0, "Cannot compile dispatcher: parameter `" ~ paramId ~ "` was annotated with multiple instances of `@Header`"
                    );
                }

                alias h_uda = header_udas[0];
                static if (is(h_uda == Header)) {
                    enum Name = paramId;
                } else {
                    static if (h_uda.name !is null) {
                       enum Name = h_uda.name;
                    } else {
                       enum Name = paramId;
                    }
                }

                static if (is(plainParamTy == string)) {
                    enum Impl = "req.http.headers.getOne(\"" ~ Name ~ "\")," ~ tail;
                }
                else static if (is(plainParamTy == string[])) {
                    enum Impl = "req.http.headers.get(\"" ~ Name ~ "\")," ~ tail;
                }
                else {
                    static assert(
                        0, "Cannot compile dispatcher: parameter `" ~ paramId ~ "` was annotated with `@Header`,"
                            ~ " but is not of type `string` or `string[]`: " ~ fullyQualifiedName!paramTy
                    );
                }
            }
            else static if (containsUDA!(QueryParam, paramUdas)) {
                alias queryparam_udas = filterUDAs!(QueryParam, paramUdas);
                static if (queryparam_udas.length != 1) {
                    static assert(
                        0, "Cannot compile dispatcher: parameter `" ~ paramId ~ "` was annotated with multiple instances of `@QueryParam`"
                    );
                }

                alias qp_uda = queryparam_udas[0];

                static if (is(qp_uda == QueryParam)) {
                    static if (is(paramDef == void)) {
                        enum DefVal = "null";
                    }
                    else static if (is(typeof(paramDef) == string)) {
                        enum DefVal = "\"" ~ paramDef ~ "\"";
                    }
                    else {
                        static assert (
                            0, "Cannot compile dispatcher: parameter `" ~ paramId ~ "`"
                                ~ " has a default value which isn't a string"
                        );
                    }
                    enum Name = paramId;
                } else {
                    static if (qp_uda.defaultValue !is null) {
                        enum DefVal = "\"" ~ qp_uda.defaultValue ~ "\"";
                        static if (!is(paramDef == void)) {
                            pragma(msg, "WARNING: found both default value in `@QueryParam` annotation and on parameter; prioritize defaultvalue of the annotation");
                        }
                    } else {
                        static if (is(paramDef == void)) {
                            enum DefVal = "null";
                        }
                        else static if (is(typeof(paramDef) == string)) {
                            enum DefVal = "\"" ~ paramDef ~ "\"";
                        }
                        else {
                            static assert (
                                0, "Cannot compile dispatcher: parameter `" ~ paramId ~ "`"
                                    ~ " has a default value which isn't a string"
                            );
                        }
                    }

                    static if (qp_uda.name !is null) {
                       enum Name = qp_uda.name;
                    } else {
                       enum Name = paramId;
                    }
                }

                static if (is(plainParamTy == string)) {
                    enum Impl = "req.http.uri.queryparams.getOne(\"" ~ Name ~ "\"," ~ DefVal ~ ")," ~ tail;
                }
                else static if (is(plainParamTy == string[])) {
                    enum Impl = "req.http.uri.queryparams.get(\"" ~ Name ~ "\"," ~ DefVal ~ ")," ~ tail;
                }
                else {
                    static assert(
                        0, "Cannot compile dispatcher: parameter `" ~ paramId ~ "` was annotated with `@QueryParam`,"
                            ~ " but is not of type `string` or `string[]`: " ~ fullyQualifiedName!paramTy
                    );
                }
            }
            else static if (containsUDA!(PathParam, paramUdas)) {
                alias pathparam_udas = filterUDAs!(PathParam, paramUdas);
                static if (pathparam_udas.length != 1) {
                    static assert(
                        0, "Cannot compile dispatcher: parameter `" ~ paramId ~ "` was annotated with multiple instances of `@PathParam`"
                    );
                }

                alias pp_uda = pathparam_udas[0];

                static if (is(pp_uda == PathParam)) {
                    enum Name = paramId;
                } else {
                    static if (pp_uda.name !is null) {
                       enum Name = pp_uda.name;
                    } else {
                       enum Name = paramId;
                    }
                }

                static if (is(plainParamTy == string)) {
                    enum Impl = "req.getPathParam(\"" ~ Name ~ "\")," ~ tail;
                }
                else {
                    static assert(
                        0, "Cannot compile dispatcher: parameter `" ~ paramId ~ "` was annotated with `@PathParam`,"
                            ~ " but is not of type `string`: " ~ fullyQualifiedName!paramTy
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
                enum Impl = "imported!\"" ~ moduleName!plainParamTy ~ "\"." ~ plainParamTy.stringof ~ ".fromRequest(req.http)," ~ tail;
            }
            else static if (hasUDA!(fn, Consumes)) {
                static assert (allowConsumes, "Cannot have two parameters be deserialized from the body of the request: `" ~ paramId ~ "` on `" ~ fullyQualifiedName!fn ~ "`");
                import ninox.web.utils;
                enum Impl =
                    "imported!\"ninox.web.serialization\".requestbody_deserialize!( " ~ BuildImportCodeForType!(paramTy) ~ ", Modules )(req),"
                    ~ Impl!(i+1, false);
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

private void addRoute(alias fn, string args, Modules...)(Router r, DList!Middleware middlewares) {
    import std.traits : fullyQualifiedName, getUDAs, hasUDA, ReturnType, hasMember, isFunction, Parameters;
    import std.meta : AliasSeq;

    pragma(msg, "Creating route handler on `" ~ fullyQualifiedName!fn ~ "`, calling with: `" ~ args ~ "`");
    pragma(msg, "  Matchers: ");
    static if (hasUDA!(fn, Middleware)) {
        static foreach (mw_uda; getUDAs!(fn, Middleware)) {
            pragma(msg, "   - ", mw_uda);
        }
    }

    Matcher[] matchers;
    static if (hasUDA!(fn, RequireHost)) {
        static foreach (uda; getUDAs!(fn, RequireHost)) {
            pragma(msg, "   - ", uda);
            matchers ~= uda.toMatcher();
        }
    }

    static if (hasUDA!(fn, Route)) {
        static foreach (uda; getUDAs!(fn, Route)) {
            pragma(msg, "   - ", uda);
            matchers ~= uda.toMatcher();
        }
    }

    static if (hasUDA!(fn, Method)) {
        static foreach (uda; getUDAs!(fn, Method)) {
            pragma(msg, "   - ", uda);
            matchers ~= uda.toMatcher();
        }
    }

    static if (hasUDA!(fn, RequireHeader)) {
        static foreach (uda; getUDAs!(fn, RequireHeader)) {
            pragma(msg, "   - ", uda);
            matchers ~= uda.toMatcher();
        }
    }

    static if (hasUDA!(fn, Produces)) {
        alias p_udas = getUDAs!(fn, Produces);
        static foreach (uda; p_udas) {
            pragma(msg, "   - ", uda);
        }
        template CollectProducesAttrs(size_t i = 0) {
            static if (i >= p_udas.length) {
                enum CollectProducesAttrs = "";
            } else {
                static if (is(p_udas[i] == Produces)) {
                    static assert (0, "Need instance of `@Produces` on handler `" ~ fullyQualifiedName!fn ~ "`");
                } else {
                    static assert (p_udas[i].types.length != 0, "@Produces needs a mime type on handler `" ~ fullyQualifiedName!fn ~ "`");

                    template ExpandProduceAttr(size_t j = 0) {
                        static if (j >= p_udas[i].types.length) {
                            enum ExpandProduceAttr = "";
                        } else {
                            import std.conv : to;
                            static assert (p_udas[i].types[j] != "", "@Produces needs a non-empty mime type at position " ~ to!string(j) ~ " on handler `" ~ fullyQualifiedName!fn ~ "`");
                            enum ExpandProduceAttr = "\"" ~ p_udas[i].types[j] ~ "\", " ~ ExpandProduceAttr!(j+1);
                        }
                    }

                    enum products = ExpandProduceAttr!();
                    static if (products == "") {
                        enum CollectProducesAttrs = CollectProducesAttrs!(i+1);
                    } else {
                        enum CollectProducesAttrs = products ~ CollectProducesAttrs!(i+1);
                    }
                }
            }
        }
        matchers ~= new AcceptMatcher(mixin("[" ~ CollectProducesAttrs!() ~ "]"));
    }

    static if (hasUDA!(fn, Consumes)) {
        alias c_udas = getUDAs!(fn, Consumes);
        static foreach (uda; c_udas) {
            pragma(msg, "   - ", uda);
        }
        template CollectConsumesAttrs(size_t i = 0) {
            static if (i >= c_udas.length) {
                enum CollectConsumesAttrs = "";
            } else {
                static if (is(c_udas[i] == Consumes)) {
                    static assert (0, "Need instance of `@Consumes` on handler `" ~ fullyQualifiedName!fn ~ "`");
                } else {
                    static assert (c_udas[i].types.length != 0, "@Consumes needs a mime type on handler `" ~ fullyQualifiedName!fn ~ "`");

                    template ExpandConsumeAttr(size_t j = 0) {
                        static if (j >= c_udas[i].types.length) {
                            enum ExpandConsumeAttr = "";
                        } else {
                            import std.conv : to;
                            static assert (c_udas[i].types[j] != "", "@Consumes needs a non-empty mime type at position " ~ to!string(j) ~ " on handler `" ~ fullyQualifiedName!fn ~ "`");
                            enum ExpandConsumeAttr = "\"" ~ c_udas[i].types[j] ~ "\", " ~ ExpandConsumeAttr!(j+1);
                        }
                    }

                    enum products = ExpandConsumeAttr!();
                    static if (products == "") {
                        enum CollectConsumesAttrs = CollectConsumesAttrs!(i+1);
                    } else {
                        enum CollectConsumesAttrs = products ~ CollectConsumesAttrs!(i+1);
                    }
                }
            }
        }
        matchers ~= new ContentTypeMatcher(mixin("[" ~ CollectConsumesAttrs!() ~ "]"));
    }

    r.addRoute(matchers, middlewares, (NinoxWebRequest req) {
        import std.json : JSONValue;
        import std.traits : isSomeString;

        alias retTy = ReturnType!fn;
        static if (is(retTy == void)) {
            mixin( "fn(" ~ args ~ ");" );
        } else static if (is(retTy == Response)) {
            mixin( "return fn(" ~ args ~ ");" );
        } else static if (is(retTy == JSONValue)) {
            mixin(
                "import ninox.web.http.response;" ~
                "import ninox.web.http.body;" ~
                "auto resp = new Response(HttpResponseCode.OK_200);" ~
                "resp.responseBody = new StdJsonBody( fn(" ~ args ~ ") );" ~
                "return resp;"
            );
        } else static if (isSomeString!retTy) {
            mixin(
                "import ninox.web.http.response;" ~
                "auto resp = new Response(HttpResponseCode.OK_200);" ~
                "resp.setBody( fn(" ~ args ~ ") );" ~
                "return resp;"
            );
        } else static if (hasMember!(retTy, "toResponse")) {
            alias toResponseMember = __traits(getMember, retTy, "toResponse");
            static assert (
                isFunction!toResponseMember,
                "Member toResponse of `" ~ fullyQualifiedName!retTy ~ "` needs to be a method"
            );
            static assert (
                is(ReturnType!toResponseMember == Response),
                "Member toResponse of `" ~ fullyQualifiedName!retTy ~ "` needs to have Response as a return type"
            );

            alias toResponseParams = Parameters!toResponseMember;
            static if (is(toResponseParams == AliasSeq!())) {
                mixin( "return fn(" ~ args ~ ").toResponse();" );
            } else static if (is(toResponseParams == AliasSeq!(Request))) {
                mixin( "return fn(" ~ args ~ ").toResponse(req.http);" );
            } else static if (is(toResponseParams == AliasSeq!(NinoxWebRequest))) {
                mixin( "return fn(" ~ args ~ ").toResponse(req);" );
            }
        } else static if (hasUDA!(fn, Produces)) {
            auto val = mixin("fn(" ~ args ~ ")");
            import ninox.web.serialization;
            return serialize_responsevalue!(typeof(val), Modules)(req.accepted_product, val);
        } else {
            static assert(0, "`" ~ fullyQualifiedName!fn ~ "` needs either void, Response or a type that has a toResponse method as return type");
        }
    });
}

private void addPublicDirMapping(Router r, PublicDirMapping pubDir) {
    Matcher[] matchers = [
        new RouteMatcher(pubDir.uri_path ~ "/:file"),
        cast(Matcher) new MethodMatcher(Method(HttpMethod.GET)),
    ];
    DList!Middleware emptyList;
    r.addRoute(matchers, emptyList, (NinoxWebRequest req) {
        import ninox.fs : NinoxFsNotFoundException;
        auto file = req.pathParams["file"];
        try {
            auto resp = Response.build_200_OK();
            // TODO: add libmagic to auto-detect content types, and maybe cache them somehow
            resp.setBody( cast(string) pubDir.fs.readFile(file) );
            return Outcome.from( resp );
        }
        catch (NinoxFsNotFoundException e) {
            if (pubDir.exclusive) {
                // exclusive means that we return a 404 on non-found files
                return Outcome.from( new Response(HttpResponseCode.Not_Found_404) );
            } else {
                // continue normal routeing
                return Outcome.nextHandler();
            }
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
                static if (is(ReturnType!fn == Optional!Response)) {
                    pragma(msg, "Creating middleware handler on `" ~ fullyQualifiedName!fn ~ "` named '" ~ uda.name ~ "', calling with: `" ~ args ~ "`");
                    r.addMiddleware(uda.name, (NinoxWebRequest req) {
                        mixin( "return fn(" ~ args ~ ");" );
                    });
                }
                else {
                    static assert(0, "`" ~ fullyQualifiedName!fn ~ "` needs to have either void or Optional!Response as returntype");
                }
            }
        }

        foreach (fn; getSymbolsByUDA!(mod, Route)) {
            static assert(isFunction!fn, "`" ~ __traits(identifier, fn) ~ "` is annotated with @Route but isn't a function");

            static assert(!hasUDA!(fn, Header), "`@Header` cannot be applied to a function directly: " ~ fullyQualifiedName!fn);
            static assert(!hasUDA!(fn, QueryParam), "`@QueryParam` cannot be applied to a function directly: " ~ fullyQualifiedName!fn);

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

            addRoute!(fn, args, Modules)(r, middlewares);

        }
    }

    foreach (pubDir; conf.publicdir_mappings) {
        addPublicDirMapping(r, pubDir);
    }

    r.sortRoutes();

    return r;
}
