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
 * Module to provide the HTTP socket wrapper
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023-2025 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module ninox.web.http.socket;

version (Have_ninox_d_async) {
	import ninox.async.io.socket;
	alias NativeSocket = AsyncSocket;
}
else {
	static assert(0, "Need to have ninox.d-async as an IO provider");
}

/** 
 * Basic http client that implements all data-accessor wrappers that are needed.
 */
struct HttpSocket {
	protected char[] back_buffer;
	private NativeSocket socket;

	this(NativeSocket socket) {
		this.socket = socket;
	}

	void[] read(size_t count) {
		import std.algorithm : min;
		void[] res;

		// always read first from the back buffer
		if (back_buffer.length > 0) {
			size_t n = min(back_buffer.length, count);
			res ~= back_buffer[0 .. n];
			back_buffer = back_buffer[n .. $];
			count -= n;
			if (count == 0) { return res; }
		}

		// if not enough, try recieving from the socket
		char[1024] buffer;
		while (count > 0) {
			size_t received = this.socket.recieve(buffer).await();

			size_t n = min(received, count);
			res ~= buffer[0 .. n];

			if (n < received) {
				// if not all bytes that where recieved where read, we have enough to saitisfy
				// the count requested and need to put the remainder into the back buffer
				back_buffer = buffer[n .. $];
				break;
			}

			count -= n;
		}

		return res;
	}

	string readLine() {
		import std.algorithm.mutation : moveAll;

		string line;
		char[1024] buffer;
		size_t received;

		long findLineEnd(char[] haystack, size_t max) {
			foreach (i; 0..max) {
				auto ch = haystack[i];
				if (ch == '\r') {
					auto j = i + 1;
					if (j >= max) {
						return -1;
					}
					if (haystack[j] == '\n') {
						return i;
					}
				}
			}
			return -1;
		}

		if (back_buffer.length > 0) {
			auto lineEnd = findLineEnd(back_buffer, back_buffer.length);
			if (lineEnd < 0) {
				// not found; add complete back buffer to result and continue reading
				line ~= back_buffer;
				back_buffer = [];
			} else {
				line ~= back_buffer[0 .. lineEnd];

				lineEnd += 2; // skip \r\n

				if (lineEnd < back_buffer.length) {
					back_buffer = back_buffer[lineEnd .. $];
				} else {
					// clear back_buffer...
					back_buffer = [];
				}
				return line;
			}
		}

		while (true) {
			received = this.socket.recieve(buffer).await();

			auto lineEnd = findLineEnd(buffer, received);
			if (lineEnd < 0) {
				// not found, copy all recieved bytes and try again...
				line ~= buffer[0 .. received];
				continue;
			}

			// copy remainder
			line ~= buffer[0 .. lineEnd];

			lineEnd += 2; // skip \r\n

			if (lineEnd < received) {
				back_buffer = [];
				back_buffer ~= buffer[lineEnd .. received];
			}
			break;
		}

		return line;
	}

	void write(const(void)[] buffer) {
		this.socket.send(buffer).await();
	}

	void writeLine(string line) {
		this.socket.send(line ~ "\r\n").await();
	}

	pragma(inline) NativeSocket getSocket() {
		return this.socket;
	}

}
