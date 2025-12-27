/*
 * Copyright (C) 2025 Mai-Lapyst
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
 * Copyright: Copyright (C) 2025 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module ninox.web.di;

import std.variant;

/**
 * UDA to annotate injectable parameters.
 */
struct Inject {
    string key;
}

/** 
 * Template to build code for an `@Inject` parameter.
 * 
 * Params:
 *   di_varname = the variable name for the di container
 *   paramId = the parameter id that is annotated with `@Inject`
 *   paramTy = the parameter's type
 *   udas = all udas of the parameter (will get filtered)
 */
template buildInject(string di_varname, string paramId, alias paramTy, udas...)
{
    import ninox.web.utils : filterUDAs;
    alias inject_udas = filterUDAs!(Inject, udas);
    static if (inject_udas.length != 1) {
        static assert(
            0, "Cannot compile inject: parameter `" ~ paramId ~ "` was annotated with multiple instances of `@Inject`"
        );
    }
    alias uda = inject_udas[0];

    import ninox.web.utils : BuildImportCodeForType;
    enum buildInject = di_varname ~ ".get!(" ~ BuildImportCodeForType!(paramTy) ~ ")(\"" ~ uda.key ~ "\")";
}

/** 
 * Exception that is thrown if the di container detects an problem.
 */
class DiContainerException : Exception {
    @nogc @safe pure nothrow this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) {
        super(msg, file, line, nextInChain);
    }

    @nogc @safe pure nothrow this(string msg, Throwable nextInChain, string file = __FILE__, size_t line = __LINE__) {
        super(msg, file, line, nextInChain);
    }
}

struct DiContainer {

    private Variant[string] _data;

    /** 
     * Generic method to set an key inside the di container.
     * 
     * Params:
     *   key = the key
     *   data = the object to be associated with the key
     */
    void set(T)(string key, T data) {
        this._data[key] = Variant(data);
    }

    /** 
     * Generic method to access an key inside the di container.
     * 
     * Params:
     *   key = the key
     * Returns: the object that is associated with the key
     */
    T get(T)(string key)
    if (!is(T == Variant))
    {
        auto val_ptr = key in this._data;
        if (val_ptr !is null && val_ptr.hasValue) {
            return val_ptr.get!T;
        } else {
            throw new DiContainerException("Could not retrieve data for key " ~ key);
        }
    }

}
