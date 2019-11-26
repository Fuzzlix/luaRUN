# luaRUN (WIP)

A exe builder for Lua.

Tested on windows using [TDM-gcc][], [lua5.1][], [lua5.2][], [lua5.3][] and [luaJIT][].

The loader provides a global `arg` similar to the lua-cli.

The provided makefile compiles by default a dos and a windows stub and glues
a glue program on it. The resulting exe's are:

* a dos stub. It is named like `glueD53.exe`.  
  D means dynamic linked to lua lib and `53` say its lua version 5.3.
* a gui stub `wsrluaD53.exe`  
  You can rename this exe and it will run the lua source with the same name. If your main lua file is "game.lua", rename wsrlua to "game.exe" and copy it into the same folder as "game.lua"  
  This stub does not open a console window and you should use some gui library like `iup` or `wxwidgets`.
* a gui glue exe. It is named like `wGlueD53`.  
  D means dynamic linked to lua lib and `53` say its lua version 5.3.
  
Both dos and gui glue programs require lpeg.

The gui glue program requires lpeg and iup.

[TDM-gcc]: http://tdm-gcc.tdragon.net/
[lua5.1]:  http://www.lua.org/versions.html#5.1
[lua5.2]:  http://www.lua.org/versions.html#5.2
[lua5.3]:  http://www.lua.org/versions.html#5.3
[luaJIT]:  http://luajit.org/