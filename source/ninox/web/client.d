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
 * Module to hold ninox.d-web's http client
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module ninox.web.client;

import ninox.async.io.socket;
import std.variant;
import std.datetime : Duration;
import ninox.web.http.client;
import ninox.web.http.request;

/** 
 * ninox.d-web's HTTP Client
 * 
 * See_Also: $(REF ninox.web.http.client.BaseHttpClient)
 */
class NinoxWebHttpClient : BaseHttpClient {
	/// The underlaying socket
	private AsyncSocket sock;

	/// Creates a new client from a socket
	this(AsyncSocket sock) {
		this.sock = sock;
	}

	/// Get the underlaying socket
	AsyncSocket getSocket() {
		return this.sock;
	}

	bool waitForActivity(ref Duration timeout) {
		return this.sock.waitForActivity(timeout).await();
	}

	protected override size_t nativeRead(scope void[] buffer) {
		return this.sock.recieve(buffer).await();
	}

	protected override void nativeWrite(scope const(void)[] buffer) {
		this.sock.send(buffer).await();
	}

}

class NinoxWebRequest {
	private Request _http_request;

	/// Storage for path parameters
	public string[string] pathParams;

	/// Stores the mime_type this request has accepted to produce
	public string accepted_product;

	/// Stores the mime_type this request consumes
	public string consumes;

	this(Request http_request) {
		this._http_request = http_request;
	}

	@property Request http() {
		return this._http_request;
	}

	string getPathParam(string key) {
		auto p = key in this.pathParams;
		if (p !is null) {
			return *p;
		}
		throw new Exception("Tried to access un-available path parameter '" ~ key ~ "'");
	}
}
