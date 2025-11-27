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
 * Module to hold code for the http version
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023-2025 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module ninox.web.http.httpversion;

/** 
 * The http version a request has been or response should be encoded with.
 */
enum HttpVersion {
	/// Unknown http version
	unknown,

	/// HTTP 1.0
	HTTP1_0,

	/// HTTP 1.1
	HTTP1_1
}

/**
 * Parses a http version from a string.
 * 
 * Params:
 *   str = the string to check
 * 
 * Returns: the http version or $(REF HttpVersion.unknown) if the version string is not known.
 */
HttpVersion httpVersionFromString(string str) {
	switch (str) {
		default: return HttpVersion.unknown;
		case "HTTP/1.0": return HttpVersion.HTTP1_0;
		case "HTTP/1.1": return HttpVersion.HTTP1_1;
	}
}

/**
 * Stringifies a http version.
 * 
 * Params:
 *   ver = the http version to stringify
 * 
 * Returns: the string representation or `null` if the version is $(REF HttpVersion.unknown).
 */
string httpVersionToString(HttpVersion ver) {
	final switch (ver) {
		case HttpVersion.unknown: return null;
		case HttpVersion.HTTP1_0: return "HTTP/1.0";
		case HttpVersion.HTTP1_1: return "HTTP/1.1";
	}
}
