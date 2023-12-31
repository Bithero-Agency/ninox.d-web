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
 * Main module; also holds the main-loop and request handling code
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module ninox.web;

import ninox.async;
import std.socket;

public import ninox.web.config;
public import ninox.web.main;
public import ninox.web.routing;
public import ninox.web.http;
public import ninox.web.client;
public import ninox.web.middlewares;

/// Handles one request
private void handleRequest(NinoxWebHttpClient client, Router router, ServerConfig conf, Request req) {
	Response resp = router.route(req, conf);
	if (resp is null) {
		import std.stdio;
		writeln("[handleRequest - ", client.getSocket().remoteAddress(), "] routing yielded no response - sending 404");
		resp = new Response(HttpResponseCode.Not_Found_404);
	}

	if (resp.responseBody !is null) {
		resp.responseBody.modifyHeaders(resp.headers, client);
	}

	if (conf.addDate && !resp.headers.has("Date")) {
		import std.datetime;
		auto currentTime = Clock.currTime();
		resp.headers.set("Date", toHttpTimeFormat(currentTime));
	}

	final switch (conf.publishServerInfo) {
		case ServerInfo.NONE: break;
		case ServerInfo.NO_VERSION:
			resp.headers.set("Server", "ninox-d_web");
			break;
		case ServerInfo.FULL:
			resp.headers.set("Server", "ninox-d_web; v0.1.0");
			break;
		case ServerInfo.CUSTOM:
			resp.headers.set("Server", conf.customServerInfo);
			break;
	}

	if (resp.responseBody is null) {
		// when no body was set, we set the contentsize to zero
		// TODO: add an warning
		resp.headers.set("Content-Length", "0");
	}

	sendResponse(req.httpVersion, resp, client);
}

/** 
 * Handles a client
 * 
 * Params:
 *   sock = the client's socket
 *   router = the router instance
 *   conf = the server config
 */
private void handleClient(AsyncSocket sock, Router router, ServerConfig conf) {
	auto peerAddr = sock.remoteAddress();

	try {
		auto client = new NinoxWebHttpClient(sock);

		if (!client.waitForActivity(conf.keep_alive_timeout)) {
			// timeout reached without any activity
			return;
		}

		Request req = parseRequest(client);
		handleRequest(client, router, conf, req);

		if (req.httpVersion < HttpVersion.HTTP1_1) {
			// close connection immedeatly after first request if not HTTP 1.1
			return;
		}

		while (true) {
			import std.string : toLower;
			auto conn = req.headers.getOne("Connection", "close").toLower();
			if (conn == "keep-alive") {}
			else if (conn == "close") { return; }
			else if (conn == "upgrade") {
				// TODO: handle upgrade...
				return;
			}

			if (!client.waitForActivity(conf.keep_alive_timeout)) {
				// timeout reached without any activity
				return;
			}

			req = parseRequest(client);
			handleRequest(client, router, conf, req);
		}

	} catch (Throwable th) {
		import std.stdio;
		writeln("[handleClient - ", peerAddr, "] error while handling request: ", th);
	}
}

private void handleClientAsync(AsyncSocket client, Router r, ServerConfig conf) {
	gscheduler.schedule(() {
		handleClient(client, r, conf);
		client.shutdownSync(SocketShutdown.BOTH);
		client.closeSync();
	});
}

/** 
 * Mainloop of ninox.d-web; listens for connections and dispatches them
 * 
 * Params:
 *   conf = the server config
 *   r = the router
 * 
 * Returns: exitstatus of ninox.d-web
 */
int ninoxwebRunServer(ServerConfig conf, Router r) {
	auto listener = new AsyncSocket(AddressFamily.INET, SocketType.STREAM);
	listener.bind(conf.addr);
	listener.listen();

	bool isRunning = true;
	while (isRunning) {
		AsyncSocket client = listener.accept().await();
		debug(ninoxweb_client_accept) {
			import std.stdio;
			writeln("[ninoxwebRunServer] accepting client ", client.remoteAddress());
		}
		handleClientAsync(client, r, conf);
	}

	return 0;
}