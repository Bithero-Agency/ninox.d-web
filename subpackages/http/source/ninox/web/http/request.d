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
 * Module to hold code for a http request
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023-2025 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module ninox.web.http.request;

import ninox.web.http.headers;
import ninox.web.http.socket;
import ninox.web.http.method;
import ninox.web.http.httpversion;
import ninox.web.http.uri;

/** 
 * Representing a HTTP request message
 */
class Request {
	/// The raw HTTP method; only valid if $(REF method) is $(REF ninox.web.http.method.HttpMethod.custom)
	private string _raw_method;

	/// The HTTP method; if this is $(REF ninox.web.http.method.HttpMethod.custom), the real method is in $(REF raw_method)
	private HttpMethod _method;

	/// The request uri
	private URI _uri;
	
	/// The http version of the request
	private HttpVersion ver;

	/// Storage for parsed headers
	private HeaderBag _headers;

	/// The request's body (if one is available)
	private RequestBody _body = null;

	this() {
		this._headers = new HeaderBag();
	}

	/// Returns the HTTP version of the request
	@property HttpVersion httpVersion() {
		return this.ver;
	}

	/// Returns the URL of the request
	ref URI getURI() {
		return _uri;
	}

	/// Returns the URL of the request
	@property ref URI uri() {
		return _uri;
	}

	/// Gets the raw method of the request
	string getRawMethod() {
		return _raw_method;
	}

	@property string rawMethod() {
		return _raw_method;
	}

	/// Gets the method of the request; if this returns $(REF ninox.web.http.method.HttpMethod.custom) use $(REF getRawMethod) instead
	HttpMethod getMethod() {
		return _method;
	}

	/// Gets the method of the request; if this returns $(REF ninox.web.http.method.HttpMethod.custom) use $(REF getRawMethod) instead
	@property HttpMethod method() {
		return _method;
	}

	/// Gets the headers
	@property HeaderBag headers() {
		return this._headers;
	}

	/// Gets the request's body
	@property RequestBody reqBody() {
		return _body;
	}
}

/**
 * Represents the body of an request
 */
class RequestBody {
	private void[] buffer;

	private this() {}

	void[] getBuffer() {
		return buffer;
	}
}

/**
 * Exception type for HTTP parsing exceptions
 */
class RequestParsingException : Exception {
	this(string msg) {
		super(msg);
	}
}

/**
 * Parses a request from the supplied socket
 * 
 * Params:
 *   sock = the current socket
 * 
 * Returns: the parsed http request
 * 
 * Throws: RequestParsingException if the parsing failed
 */
Request parseRequest(HttpSocket sock) {
	import std.string : indexOf;

	Request r = new Request();

	// parse the request line
	auto requestLine = sock.readLine();
	if (requestLine == "PRI * HTTP/2.0") {
		// TODO: http2 handling.
		throw new RequestParsingException("HTTP2 is NIY");
	}

	auto pos = requestLine.indexOf(' ');
	if (pos <= 0) throw new RequestParsingException("invalid request method");
	r._raw_method = requestLine[0 .. pos];
	r._method = httpMethodFromString(r._raw_method);
	requestLine = requestLine[pos+1 .. $];

	pos = requestLine.indexOf(' ');
	if (pos <= 0) throw new RequestParsingException("invalid request path");
	r._uri = URI(requestLine[0 .. pos]);
	requestLine = requestLine[pos+1 .. $];

	r.ver = httpVersionFromString(requestLine);
	if (r.ver == HttpVersion.unknown) throw new RequestParsingException("invalid request http version");

	// start header parsing
	while (true) {
		auto line = sock.readLine();
		debug (ninoxweb_parseRequest) {
			import std.stdio;
			writeln("[ninox.web.http.parseRequest] got headerline: ", line);
		}

		if (line.length < 1) { break; }

		string key = "";
		string value = "";
		bool splitHeader() {
			foreach(i, ch; line) {
				if (ch == ':') {
					auto j = i + 1;
					if (j >= line.length) {
						return false;
					}
					if (line[j] == ' ') {
						key = line[0 .. i];
						value = line[i+2 .. $];
						return true;
					}
				}
			}
			return false;
		}

		if (!splitHeader()) {
			throw new RequestParsingException("header line has wrong format");
		}

		debug (ninoxweb_parseRequest) {
			import std.stdio;
			writeln("[ninox.web.http.parseRequest] got header: key=", key, "|value=", value);
		}

		r._headers.append(key, value);
	}

	// TODO: this needs to be made more secure...
	if (r._headers.has("Content-Length")) {
		import std.conv : to;
		size_t contentLength = to!size_t( r._headers.getOne("Content-Length") );
		r._body = new RequestBody();
		r._body.buffer = sock.read(contentLength);
	}

	if (r.ver == HttpVersion.HTTP1_1 && !r._headers.has("Host")) {
		throw new RequestParsingException("request specified HTTP 1.1 but supplied no Host header");
	}

	return r;
}
