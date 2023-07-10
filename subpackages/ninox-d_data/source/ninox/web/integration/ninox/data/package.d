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
 * Module to integrate ninox.d-data into ninox.d-web
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module ninox.web.integration.ninox.data;

template mkJsonMapper() {
    static if (__traits(compiles, imported!"ninox.data.json.serializer".JsonMapper)) {
        enum mkJsonMapper = "
            @( imported!\"ninox.web.serialization\".Mapper([\"application/json\"]) )
            class JsonMapperImpl {
                static T deserialize(T)(void[] buffer) {
                    import ninox.data.json.serializer;
                    auto mapper = new JsonMapper();
                    return mapper.deserialize!(T)( cast(string) buffer );
                }
                static string serialize(T)(auto ref T value) {
                    import ninox.data.json.serializer;
                    auto mapper = new JsonMapper();
                    return mapper.serialize!T(value);
                }
            }
        ";
    }
    else {
        static assert (0, "Cannot use mkJsonMapper without also installing the ninox-d_data:json package!");
    }
}
