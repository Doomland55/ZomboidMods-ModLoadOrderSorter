# MLOS ZombieBuddy bridge

`build.sh` builds the shipped client-only JAR with JDK 8 or newer. The Kahlua
`LuaMethod` annotation under `stubs/` is the original Kahlua 2 definition
(MIT licence, copyright notice in the file), used only for compilation and not
packaged: Project Zomboid supplies it at runtime. The bridge uses no compile-time
ZombieBuddy or game classes. The game mod registry is resolved on the caller
thread; filesystem enumeration and reads run on a daemon worker. Only paths from
that registry are accepted. See `42.0/ZombieBuddy.md` in the mod for user setup.

`tests/java/ModFilesBridgeTest.java` exercises the compiled JAR using a minimal
stand-in for `ChooseGameInfo`. `tests/zombie_buddy_bridge.lua` exercises the
Lua integration, cache interoperability, cancellation and fallback using mocks.
Neither substitutes for testing in Project Zomboid with ZombieBuddy installed.
