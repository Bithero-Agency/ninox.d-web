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
 * Module to hold code to reduce boilerplate code
 * 
 * License:   $(HTTP https://www.gnu.org/licenses/agpl-3.0.html, AGPL 3.0).
 * Copyright: Copyright (C) 2023-2025 Mai-Lapyst
 * Authors:   $(HTTP codeark.it/Mai-Lapyst, Mai-Lapyst)
 */

module ninox.web.main;

/** 
 * Used to reduce boilerplate in ninox.d-web projects; defines an async main and calls ninox.d-web's startup.
 * 
 * Supply it with all modules where ninox.d-web should search for route handlers.
 * 
 * Example:
 * ---
 * module test;
 * import ninox.web.main;
 * mixin NinoxWebMain!(test);
 * ---
 * 
 * See_Also: $(REF ninox.async.main.AsyncMain)
 */
template NinoxWebMain(Modules...) {
	mixin NinoxWebAsyncMain!Modules;

	import ninox.async;
	import ninox.async.main;
	mixin AsyncMain;
}

/** 
 * Used to reduce boilerplate in ninox.d-web projects;
 * Wrapper around $(REF ninox.async.main.AsyncLoop); also defines ninox.d-web's startup.
 * 
 * Supply it with all modules where ninox.d-web should search for route handlers.
 * 
 * Example:
 * ---
 * module test;
 * import ninox.web.main;
 * mixin NinoxWebLoop!(test);
 * 
 * int main(string[] args) {
 *     return mainAsyncLoop();
 * }
 * ---
 * 
 * See_Also: $(REF ninox.async.main.AsyncLoop)
 */
template NinoxWebLoop(Modules...) {
	mixin NinoxWebAsyncMain!Modules;

	import ninox.async;
	import ninox.async.main;
	mixin AsyncLoop;
}

/** 
 * Used to reduce boilerplate in ninox.d-web projects;
 * Defines a async main with ninox.d-web's startup.
 * 
 * Supply it with all modules where ninox.d-web should search for route handlers.
 * 
 * See_Also: $(REF ninox.async.main.AsyncLoop) and $(REF ninox.async.main.AsyncMain)
 */
template NinoxWebAsyncMain(Modules...) {
	mixin NinoxWebStartup!Modules;

	int async_main() {
		return ninoxWebStartup();
	}
}

/** 
 * Used to reduce boilerplate in ninox.d-web projects;
 * Defines ninox.d-web's startup.
 * 
 * Supply it with all modules where ninox.d-web should search for route handlers.
 * 
 * Example:
 * ---
 * module test;
 * import ninox.web.main;
 * mixin NinoxWebStartup!test;
 * 
 * import ninox.async.main;
 * mixin AsyncMain;
 * 
 * int async_main(string[] args) {
 *     return ninoxWebStartup();
 * }
 * ---
 */
template NinoxWebStartup(Modules...) {
	import std.meta : AliasSeq;
	import std.traits : getSymbolsByUDA, isFunction, ReturnType, Parameters,
		ParameterIdentifierTuple, ParameterStorageClassTuple, ParameterStorageClass,
		fullyQualifiedName, Unconst;
	import ninox.web.config;
	import ninox.web.di;

	alias allMods = AliasSeq!(Modules);

	int ninoxWebStartup() {
		ServerConfig conf = new ServerConfig();
		DiContainer container;

		template MakeCall(string name, alias fn)
		{
			alias storageclasses = ParameterStorageClassTuple!fn;
			alias types = Parameters!fn;
			alias identifiers = ParameterIdentifierTuple!fn;

			template Impl(size_t i = 0) {
				static if (i == types.length) {
					enum Impl = "";
				} else {
					alias tail = Impl!(i+1);

					alias paramSc = storageclasses[i];
					alias paramTy = types[i .. i+1];
					enum paramId = identifiers[i];
					enum isRef = paramSc == ParameterStorageClass.ref_;
					alias plainParamTy = Unconst!paramTy;

					static if (is(plainParamTy == ServerConfig)) {
						enum Impl = "conf," ~ tail;
					}
					else static if (is(plainParamTy == DiContainer)) {
						static assert(isRef, "parameter of type DiContainer needs to have `ref` storageclass");
						enum Impl = "container, " ~ tail;
					}
					else {
						static assert(
							0, "Cannot compile call for " ~ name ~ ": unknown type `" ~ fullyQualifiedName!paramTy ~ "`"
								~ " for parameter `" ~ paramId ~ "`"
								~ " on function `" ~ fullyQualifiedName!fn ~ "`"
						);
					}
				}
			}
			enum MakeCall = Impl!();
		}

		static foreach (mod; allMods) {
			static foreach (fn; getSymbolsByUDA!(mod, OnServerStart)) {
				static assert(isFunction!fn, "`" ~ __traits(identifier, fn) ~ "` is annotated with OnServerStart but is not a function");
				static assert(is(ReturnType!fn == void), "`" ~ __traits(identifier, fn) ~ "` needs to have a return value of `void`");
				mixin("fn(" ~ MakeCall!("OnServerStart", fn) ~ ");");
			}
		}

		import ninox.web.serialization;
		checkMappers!(allMods);

		Router router = initRouter!(allMods)(conf);

		int exitCode = ninoxwebRunServer(conf, router, container);

		static foreach (mod; allMods) {
			static foreach (fn; getSymbolsByUDA!(mod, OnServerShutdown)) {
				static assert(isFunction!fn, "`" ~ __traits(identifier, fn) ~ "` is annotated with OnServerShutdown but is not a function");
				static assert(is(ReturnType!fn == void), "`" ~ __traits(identifier, fn) ~ "` needs to have a return value of `void`");
				mixin("fn(" ~ MakeCall!("OnServerStart", fn) ~ ");");
			}
		}

		return exitCode;
	}
}
