module ninox.web.serialization;

import ninox.web.client;
import ninox.web.http.response;

import std.meta : AliasSeq;

struct Mapper {
    string[] types;
}

private template checkMapper(alias clazz) {
    import std.traits;
    static assert (
        __traits(compiles, __traits(getMember, clazz, "deserialize")),
        "Mapper `" ~ fullyQualifiedName!clazz ~ "` needs to have a static method called `deserialize`!"
    );
    static assert (
        __traits(compiles, __traits(getMember, clazz, "serialize")),
        "Mapper `" ~ fullyQualifiedName!clazz ~ "` needs to have a static method called `serialize`!"
    );
}

void checkMappers(Modules...)() {
    import std.traits;
    struct MyVal {}

    static foreach (mod; Modules) {
        static foreach (clazz; getSymbolsByUDA!(mod, Mapper)) {
            pragma(msg, "Found mapper: `", fullyQualifiedName!clazz, "`");
            mixin checkMapper!(clazz);
        }
    }
}

T requestbody_deserialize(T, Modules...)(NinoxWebRequest req) {
    import ninox.web.utils : extractBaseMime;

    string base_mime = extractBaseMime(req.consumes);

    template apply_mapper_deserialize(alias clazz) {
        import std.traits;

        alias udas = getUDAs!(clazz, Mapper);
        static assert (udas.length == 1, "Can only have one instance of @Mapper applied to `" ~ fullyQualifiedName!clazz ~ "`");

        enum types = udas[0].types;

        import ninox.web.utils : BuildImportCodeForType;
        enum apply_mapper_deserialize =
            "if (" ~ types.stringof ~ ".canFind(base_mime)) {" ~
                "debug (ninoxweb_debug_mappers) {" ~
                    "import std.stdio;" ~ 
                    "writeln(\"[requestbody_deserialize] use `" ~ fullyQualifiedName!clazz ~ "` for mime '\" ~ base_mime ~ \"'\");" ~
                "}" ~
                "return " ~ BuildImportCodeForType!clazz ~ ".deserialize!(" ~ BuildImportCodeForType!T ~ ")(req.http.reqBody.getBuffer());" ~
            "}"
        ;
    }

    import std.traits;
    import std.algorithm : canFind;
    static foreach (mod; Modules) {
        static foreach (clazz; getSymbolsByUDA!(mod, Mapper)) {
            mixin( apply_mapper_deserialize!clazz );
        }
    }

    assert (0, "Could not find any mapper to apply for mimetype '" ~ base_mime ~ "'");
}

Response serialize_responsevalue(T, Modules...)(string accepted_product, auto ref T value) {
    import ninox.web.utils : extractBaseMime;

    string base_mime = extractBaseMime(accepted_product);

    template apply_mapper_serialize(alias clazz) {
        import std.traits;

        alias udas = getUDAs!(clazz, Mapper);
        static assert (udas.length == 1, "Can only have one instance of @Mapper applied to `" ~ fullyQualifiedName!clazz ~ "`");

        enum types = udas[0].types;

        import ninox.web.utils : BuildImportCodeForType;
        enum apply_mapper_serialize =
            "if (" ~ types.stringof ~ ".canFind(base_mime)) {" ~
                "debug (ninoxweb_debug_mappers) {" ~
                    "import std.stdio;" ~ 
                    "writeln(\"[serialize_responsevalue] use `" ~ fullyQualifiedName!clazz ~ "` for mime '\" ~ base_mime ~ \"'\");" ~
                "}" ~
                "auto str = " ~ BuildImportCodeForType!clazz ~ ".serialize!(" ~ BuildImportCodeForType!T ~ ")(value);" ~
                "auto resp = new Response(HttpResponseCode.OK_200);" ~
                "resp.setBody(str, accepted_product);" ~
                "return resp;" ~
            "}"
        ;
    }

    import std.traits;
    import std.algorithm : canFind;
    import ninox.web.http.response;

    static foreach (mod; Modules) {
        static foreach (clazz; getSymbolsByUDA!(mod, Mapper)) {
            mixin( apply_mapper_serialize!clazz );
        }
    }

    assert (0, "Could not find any mapper to apply for mimetype '" ~ base_mime ~ "'");
}