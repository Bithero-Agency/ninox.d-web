module test;

import ninox.web;
import ninox.web.serialization;

import std.stdio;
import std.json;

import ninox.web.integration.ninox.data;
mixin(mkJsonMapper!());

@( imported!"ninox.web.serialization".Mapper([ "text/x-meow" ]) )
class MeowMapperImpl {
    static T deserialize(T)(void[] buffer) {
        static if (is(T == MyValue)) {
            import std.conv : to;
            auto v = new MyValue();
            v.i = to!int(to!string(buffer));
            return v;
        } else {
            import std.traits : fullyQualifiedName;
            throw new RuntimeException("Cannot deserialize type " ~ fullyQualifiedName!T);
        }
    }
    static string serialize(T)(auto ref T value) {
        static if (is(T == MyValue)) {
            import std.conv : to;
            return to!string(value.i);
        } else {
            import std.traits : fullyQualifiedName;
            throw new RuntimeException("Cannot serialize type " ~ fullyQualifiedName!T);
        }
    }
}

mixin NinoxWebMain!(test);

@RegisterMiddleware("a")
MaybeResponse myfun() {
    writeln("Applying myfun middleware...");
    return MaybeResponse.none();
}

@OnServerStart
void my_server_conf(ServerConfig conf) {
    writeln("Called on server start!");
    conf.setCustomServerInfo("My Fancy Server");

    conf.addPublicDir("./public", "/assets1");

    import std.datetime : dur;
    conf.keep_alive_timeout = dur!"seconds"(10);
}

@OnServerShutdown
void my_server_shutdown() {
    writeln("Called on server shutdown!");
}

@Route("/assets1/test2.txt")
string assets1_test2_txt() {
    return "This is a dynamic 'file'!";
}

@Route("/doOther")
void doOther() {}

@Route("/doThing")
@Middleware("a")
@Middleware((r) { writeln("Applying functional middleware..."); return MaybeResponse.none(); })
Response doThing(Request r, HeaderBag h, URI uri) {
    writeln("Got request on doThing!");
    writeln(" req: ", r);
    writeln(" headers: ", h);
    writeln(" uri: ", uri.encode());
    auto resp = Response.build_200_OK();
    resp.headers.set("Bla", "blup");
    resp.setBody("Hello world :D");
    return resp;
}

@Route("/doSome")
void doSome1(HttpMethod method) {
    writeln("called doSome1: ", method);
}

@GET @Route("/doSome")
void doSome2() {
    writeln("called doSome2");
}

@GET @Route("/user/:username/?")
void getUserByName(@PathParam string username) {
    writeln("called getUserByName: username = ", username);
}

class CustomValue {
    private int num;

    this(int num) {
        this.num = num;
    }

    Response toResponse(Request req) {
        import std.conv : to;
        auto resp = Response.build_200_OK();
        resp.setBody(
            "host is: " ~ req.headers.getOne("host") ~ "\n"
            ~ "num is: " ~ to!string(this.num) ~ "\n"
        );
        return resp;
    }
}
@GET @Route("/customValue/:val")
CustomValue getCustomValue(@PathParam string val) {
    import std.conv : to;
    return new CustomValue( to!int(val) );
}

@GET @Route("/testJson")
JSONValue testJson() {
    JSONValue test;
    test["s"] = "Hello world";
    test["n"] = 42;
    test["a"] = [11, 22, 33];
    return test;
}

class MyValue {
    int i = 42;
}

@GET @Route("/testJson2")
@Produces(["application/json", "text/x-meow"])
MyValue testJson2(@Header string accept) {
    writeln("Accept: ", parseHeaderQualityList(accept));
    return new MyValue();
}

@Post @Route("/testJson3")
@Consumes(["application/json", "text/x-meow"])
void testJson3(MyValue val) {
    writeln("Handle testJson3; i=", val.i);
}

@Get @Route("/testString")
string testString() {
    return "Hello world from a string :D\n";
}

@Host("some.special.domain.tld") {

    @Get @Route("/testSpecial")
    Response get_testSpecial() {
        auto resp = Response.build_200_OK();
        resp.headers.set("Bla", "blup");
        resp.setBody("This is a special test :3");
        return resp;
    }

}
