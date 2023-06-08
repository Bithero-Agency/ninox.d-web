# Miniweb

A minimal yet complete webframework.

## License

The code in this repository is licensed under AGPL-3.0-or-later; for more details see the `LICENSE` file in the repository.

## Getting started

This library aims to have an small but complete webframework for dlang projects.

A simple hello world project:
```d
module test;

import miniweb;
import miniweb.main;
mixin MiniWebMain!test;

@OnServerStart
void configureServer(ServerConfig conf) {
    conf.setCustomServerInfo("My Fancy Server");
}

@Route("/doSomething")
void doSomething() {
    writeln("Does something!");
}

@GET @Route("/returnSomething")
Response returnSomething(HeaderBag headers) {
    auto resp = Response.build_200_OK();
    resp.headers.set("X-My-Header", headers.get("X-My-Header"));
    resp.setBody("Hello world!");
    return resp;
}
```
Miniweb has the ability to analyse annotated functions and call them with any order of parameters, as long as minweb supports the type.

Currently supported are:
- `Request` get the raw http request
- `MiniwebRequest` get the miniweb request
- `HeaderBag` get the headers of the request
- `URI` get the uri of the request
- `QueryParamBag` get the query params of the request
- `HttpMethod` get the requests HTTP method of the request
- `@Header` annotated `string` or `string[]` params get the specified header;
    Uses the parameter name if none is supplied
- `@QueryParam` annotated `string` or `string[]` params get the specified header;
    Uses the parameter name as queryparam name if none is supplied, same with default value
- `@PathParam` annotated `string` params get the specified path parameter;
    Uses the parameter name if none is supplied

To use middlewares you have two options, either create a named one or use functionals:
```d
@RegisterMiddleware("my_middleware")    // registers a named middleware
MaybeResponse handler(Request req) {
    return MaybeResponse.none();    // returns a Option!Response with no value set,
                                    // which effectivly means to call either the next middleware
                                    // or the handler.
}

// Middlewares can either return MaybeResponse or void and have
// the same freedom in their parameters as normal route handlers
@RegisterMiddleware("other")
void otherHandler() {}

@Route("/returnSomething")
@Middleware("my_middleware")    // applies a named middleware
Response returnSomething(HeaderBag headers) {
    // ...
}

@Route("/someWhereOther")
// This is a functional middleware, it accepts a delegate/function directly
@Middleware((req) {
    return MaybeReponse.none();
})
Response someWhereOther() {
    // ...
}
```

Usage of path parameters:
```d
// To use path parameters, just use the syntax :<a-zA-Z0-9_> inside the route matcher.
// @Route declarations also now support the `?` specified which make the character before it optional.
@GET @Route("/user/:username/?")
Response getUser(@PathParam string username) {
    // ...
}
```

Custom return types:
```d
import std.conv : to;
class CustomValue {
    private int num;
    this(int num) { this.num = num; }
    Response toResponse(Request req) {
        auto resp = Response.build_200_OK();
        resp.setBody(
            "host is: " ~ req.headers.getOne("host") ~ "\n"
            ~ "num is: " ~ to!string(this.num) ~ "\n");
        return resp;
    }
}
@GET @Route("/customValue/:val")
CustomValue getCustomValue(@PathParam string val) {
    return new CustomValue( to!int(val) );
}
```

## Roadmap

- More bodytypes to move data
- Allowing more returntypes, i.e. auto-serializing
- Allowing detection of more request parameters
- Routes with regex
- Full http/1.1 support
- http/2 support
- ssl/tls support
- ...
