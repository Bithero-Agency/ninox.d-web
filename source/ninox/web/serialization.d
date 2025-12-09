/*
 * Copyright (C) 2023-2025 Mai-Lapyst
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
 * Module for all serialization things
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023-2025 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */
module ninox.web.serialization;

import ninox.web.request;
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