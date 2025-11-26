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
 * Module to hold header related code
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023-2025 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module ninox.web.http.headers;

private pragma(inline) char toLower(char c) @nogc @safe pure nothrow {
	return (c >= 'A' && c <= 'Z') ? cast(char)(c + 32) : c;
}

private struct CaseInsensitiveString {
	string data;

	size_t toHash() const @nogc @safe pure nothrow {
		size_t hash = 0;
		foreach (char c; this.data) {
			hash = hash * 32 + c.toLower;
		}
		return hash;
	}

	bool opEquals(const CaseInsensitiveString other) const @nogc @safe pure nothrow {
		if (this.data.length != other.data.length) return false;
		foreach (i, char c; this.data) {
			if (c.toLower != other.data[i].toLower) return false;
		}
		return true;
	}

	pragma(inline) string opCast() const @nogc @safe pure nothrow {
		return this.data;
	}
}

/**
 * Stores headers for an HTTP Message, all keys are case insensitive.
 */
class HeaderBag {
	/// internal assocative array storing the headers
	private string[][CaseInsensitiveString] map;

	/**
	 * Checks if a key is set
	 * 
	 * Params:
	 *  key = the key to check for
	 * 
	 * Returns: true if the key is set, false otherwise
	 */
	bool has(string key) {
		auto p = CaseInsensitiveString(key) in map;
		return p !is null;
	}

	/**
	 * Get's all values for the given key
	 * 
	 * Params:
	 *   key = the key to get values for
	 *   defaultValue = a default value if the key dosnt exist
	 * 
	 * Returns: the values for the key or a array with `defaultValue` as single element if no values are present.
	 */
	string[] get(string key, string defaultValue = "") {
		auto p = CaseInsensitiveString(key) in map;
		if (p !is null) {
			return *p;
		}
		return [defaultValue];
	}

	/**
	 * Gets exactly one value for the given key
	 * 
	 * Params:
	 *   key = the key to get values for
	 *   defaultValue = a default value if the key dosnt exist
	 * 
	 * Returns: the values for the key or `defaultValue` if no values are present.
	 */
	string getOne(string key, string defaultValue = "") {
		return get(key, defaultValue)[0];
	}

	/** 
	 * Sets the given key to the given values
	 * 
	 * Params:
	 *   key = the key to get values for
	 *   values = the values to set
	 */
	void set(string key, string[] values) {
		map[CaseInsensitiveString(key)] = values;
	}

	/** 
	 * Sets the given key to the given value
	 * 
	 * Params:
	 *   key = the key to get values for
	 *   value = the value to set
	 */
	void set(string key, string value) {
		map[CaseInsensitiveString(key)] = [ value ];
	}

	/** 
	 * Appends the given values to the values of the given key
	 * 
	 * Params:
	 *   key = the key to append values to
	 *   values = the values to append
	 */
	void append(string key, string[] values) {
		auto _key = CaseInsensitiveString(key);
		if ((_key in map) !is null) {
			map[_key] = values;
		} else {
			map[_key] ~= values;
		}
	}

	/** 
	 * Appends the given value to the values of the given key
	 * 
	 * Params:
	 *   key = the key to append values to
	 *   value = the value to append
	 */
	void append(string key, string value) {
		append(key, [ value ]);
	}

	/** 
	 * Unsets the given key; effectively deletes all values for the key
	 * 
	 * Params:
	 *   key = the key to unset
	 */
	void unset(string key) {
		map.remove(CaseInsensitiveString(key));
	}

	/** 
	 * Iterates over all key`s and run the given delegate on it and the values
	 * 
	 * Params:
	 *   dg = delegate to call for each header key
	 */
	void foreachHeader(void delegate(string, string[]) dg) {
		foreach (key, value; map) {
			dg(key.data, value);
		}
	}

	/** 
	 * Iterates over all key`s and run the given function on it and the values
	 * 
	 * Params:
	 *   fn = function to call for each header key
	 */
	void foreachHeader(void function(string, string[]) fn) {
		foreach (key, value; map) {
			fn(key.data, value);
		}
	}

	pragma(inline) ref auto opIndex(string key) {
		return this.get(key);
	}

	pragma(inline) ref auto opIndexAssign(string value, string key) {
		return this.set(key, value);
	}

	pragma(inline) ref auto opIndexAssign(string[] value, string key) {
		return this.set(key, value);
	}

	int opApply(scope int delegate(string, ref string) dg) {
		int result = 0;
		foreach (key, ref vals; this.map) {
			foreach (ref val; vals) {
				result = dg(key.data, val);
				if (result)
					break;
			}
		}
		return result;
	}

	int opApply(scope int delegate(string, ref string[]) dg) {
		int result = 0;
		foreach (key, ref vals; this.map) {
			result = dg(key.data, vals);
			if (result)
				break;
		}
		return result;
	}
}
