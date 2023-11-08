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
 * Module to hold ninox.d-web's configuration
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module ninox.web.config;

import std.socket;
import std.datetime : Duration, dur;
import ninox.fs;

/** 
 * UDA for functions that should be called on server start
 * 
 * Functions applied with this needs to have `void` as returntype,
 * and either no parameters or only a singular of type `ServerConfig`.
 * 
 * Example:
 * ---
 * @OnServerStart
 * void myConfigFunc(ServerConfig conf) {}
 * 
 * @OnServerStart
 * void myVoidFunc() {}
 * ---
 */
struct OnServerStart {}

/// UDA for functions that should be called on server shutdown
struct OnServerShutdown {}

/// State of the serverinfo; used to determine the value of the `Server` http header
enum ServerInfo {
	/// No serverinfo will be given out
	NONE,

	/// Only the identifier of ninox.d-web will be used
	NO_VERSION,

	/// Full serverinfo of ninox.d-web; name + version
	FULL,

	/// Custom serverinfo-string; See $(REF ServerConfig.setCustomServerInfo)
	CUSTOM,
}

/// A public directory mapping
struct PublicDirMapping {
	FS fs;
	string uri_path;
	bool exclusive = false;
}

/** 
 * Configuration of the server
 */
class ServerConfig {

	/// The address to listen on
	Address addr;

	/// If true, the http `Date` header will be set on all responses
	bool addDate = true;

	/// The serverinfo type
	ServerInfo publishServerInfo = ServerInfo.FULL;

	/// A custom serverinfo string
	string customServerInfo = "";

	/// Retruns a 404 instead of a 405 when no route handler was found because the @Method restriction didn't permitted handling.
	bool treat_405_as_404 = false;

	/// Returns a 404 instead of a 400 when no route handler was found because the @RequiredHeader restriction didn't permitted handling.
	bool treat_required_header_failure_as_404 = false;

	/// Returns a 404 instead of a 406 when no route handler was found because the @Produces restriction didn't permitted handling
	bool treat_406_as_404 = false;

	/// List of all public dir mappings
	PublicDirMapping[] publicdir_mappings;

	/// Timeout for keep-alive connections; defaults to 300 seconds / 5 minutes
	Duration keep_alive_timeout = dur!"seconds"(300);

	this() {
		this.addr = new InternetAddress("localhost", 8080);
	}

	/// Sets the serverinfo to a custom string
	void setCustomServerInfo(string info) {
		customServerInfo = info;
		publishServerInfo = ServerInfo.CUSTOM;
	}

	/**
	 * Adds an public directory mapping via runtime lookup
	 * 
	 * Params:
	 *   fs_path = the path to the directory on the filesystem, relative to the current working directory of the process
	 *   uri_path = path for the uri to match the mapping
	 *   exclusive = if true, this means when a file could not be found, routing is stoped with an 404;
	 *               otherwise when its false, it falls through to normal routing on nonexisting files
	 */
	void addPublicDir(string fs_path, string uri_path = "/", bool exclusive = false) {
		this.addPublicDir(getOsFs(fs_path), uri_path, exclusive);
	}

	/**
	 * Adds an public directory mapping via the ninox.d-fs filesystem abstraction
	 * 
	 * Params:
	 *   fs = the filesystem to use
	 *   uri_path = path for the uri to match the mapping
	 *   exclusive = if true, this means when a file could not be found, routing is stoped with an 404;
	 *               otherwise when its false, it falls through to normal routing on nonexisting files
	 */
	void addPublicDir(FS fs, string uri_path = "/", bool exclusive = false) {
		this.publicdir_mappings ~= PublicDirMapping( fs, uri_path, exclusive );
	}
}
