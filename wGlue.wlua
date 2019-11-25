--
--==============================================================================
-- WGLUE  (WIP)
--==============================================================================
--
--==============================================================================
-- Copyright (C) 2017-2019 Ulrich Schmidt.
--
-- Permission is hereby granted, free of charge, to any person obtaining
-- a copy of this software and associated documentation files (the
-- "Software"), to deal in the Software without restriction, including
-- without limitation the rights to use, copy, modify, merge, publish,
-- distribute, sublicense, and/or sell copies of the Software, and to
-- permit persons to whom the Software is furnished to do so, subject to
-- the following conditions:
--
-- The above copyright notice and this permission notice shall be
-- included in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
-- EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
-- MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
-- IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
-- CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
-- TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
-- SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--==============================================================================
--
--luacheck: globals arg

local VERSION = "V 19/11/23";
--
local iup  = require "iuplua";
local lpeg = require "lpeg";

local insert, concat = table.insert, table.concat;
--
local app = {};
--
local function luaVersion()
  local f = function() return function() end end;
  local t = {
    nil, --luacheck: ignore
    [false]  = 'LUA5.1',
    [true]   = 'LUA5.2',
    [1/'-0'] = 'LUA5.3',
    [1]      = 'LUAJIT'
  };
  return t[1] or t[1/0] or t[f()==f()];
end;

local function pairsByKey(t)
  local a = {}
  for n in pairs(t) do
    a[#a + 1] = n;
  end;
  table.sort(a, function(a, b)
      return (type(a) == type(b)) and (a < b) or (type(a) < type(b))
    end
  );
  local i = 0;        -- iterator variable
  return function()   -- iterator function
    i = i + 1;
    return a[i], a[i] and t[a[i]];
  end;
end;

local function splitpath(path)
  local i = #path;
  local ch = path:sub(i, i);
  while i > 0 and ch ~= '/' and ch ~= '\\' do
    i = i - 1;
    ch = path:sub(i, i);
  end;
  if i == 0 then
    return '', path;
  else
    return path:sub(1, i - 1), path:sub(i + 1);
  end;
end;

local function filetype(fn, ext)
  ext = ext:lower();
  if ext:sub(1,1) ~= "." then ext = "." .. ext end;
  return fn:sub(-#ext):lower() == ext;
end;

local function is_exe(fn)
  return filetype(fn, ".exe");
end;
--
local function ifSources(elem)
  local filelist = {
    "Makefile",
    "loader.c",
    "miniglue.c",
    "lua.ico",
    "glue.lua",
    "wglue.wlua",
    "lua.ico",
    "lua_lang.ico",
    "lua_small.ico"
  };
  for _,fn in ipairs(filelist) do
    local f = io.open(fn);
    if not f then
      return;
    end;
    f:close();
  end;
  return elem;
end;
ifSources = ifSources(function(x) return x; end) or function() return; end;
--
local function printMessageLine(ps, mt)
  local size = 131 - #ps;
  local s = "";
  local t = {};
  for k in pairsByKey(mt) do
    insert(t, k);
  end;
  if #t > 0 then
    for i = 1, #t do
      if (#ps + #s + #t[i]) > size then
        app.print(ps .. s);
        ps = string.rep(" ", #ps);
        s = "";
      end;
      if #s > 0 then
        s = s..", ";
      end;
      s = s .. t[i];
    end
    app.print(ps .. s);
  end
end;

local function doGlue(args)
  --[[ Lua Module Catenation.
   Creates one single lua file preloading all lua modules.
   Usefull to create stand alone lua programs.

   **Required Modules:** lpeg
  ]]
  --
  lpeg.setmaxstack(300);       -- default: 100
  local locale   = lpeg.locale();
  local P, S, V  = lpeg.P, lpeg.S, lpeg.V;
  local C, Cb, Cg, Cs, Cmt = lpeg.C, lpeg.Cb, lpeg.Cg, lpeg.Cs, lpeg.Cmt;
  local EOL, ANY = P"\n", P(1);
  local EOF      = P(-1);
  local SPACE    = locale.space;
  local DIGIT    = locale.digit;
  local ALPHA    = locale.alpha + P"_";
  local ALPHANUM = ALPHA + DIGIT;
  local SHEBANG  = P"#" * (ANY - EOL)^0 * EOL;
  local function K(w)
    return P(w) * -ALPHANUM;
  end;
  local tblLuaMods       = {}; -- required lua modules.
  local tblOtherMods     = {}; -- unknown modules.
  local tblBuiltinMods   = {   -- list of built in modules.
    _G        = true,
    coroutine = package.loaded["coroutine"] and true, --luacheck: ignore
    debug     = package.loaded["debug"]     and true, --luacheck: ignore
    io        = package.loaded["io"]        and true, --luacheck: ignore
    math      = package.loaded["math"]      and true, --luacheck: ignore
    os        = package.loaded["os"]        and true, --luacheck: ignore
    package   = package.loaded["package"]   and true, --luacheck: ignore
    string    = package.loaded["string"]    and true, --luacheck: ignore
    table     = package.loaded["table"]     and true, --luacheck: ignore
    utf8      = package.loaded["utf8"]      and true, --luacheck: ignore
    bit32     = package.loaded["bit32"]     and true, --luacheck: ignore
    bit       = package.loaded["bit"]       and true, --luacheck: ignore
    jit       = package.loaded["jit"]       and true, --luacheck: ignore
    utf8      = package.loaded["utf8"]      and true, --luacheck: ignore
    };
  local tblExcludedMods  = setmetatable({},{__index = tblBuiltinMods}); -- excluded modules
  local tblIncludedMods  = {}; -- manually included modules
  local tblPreloadedMods = {}; -- already preloaded modules.
  local sources          = {};
  local stripping;             -- true in pass2: generating amalgam

  local function get_module_name(s) return s; end; -- forward declaration
  local function GMN(s)
    return get_module_name(s);
  end;
  local function GPN(s)        -- get preloaded name
      tblPreloadedMods[s] = true;
      tblLuaMods[s] = nil;
    return s;
  end;
  local function strip_spc(s)
    if stripping then return " " end;
    return s;
  end;
  local function stripall(s)
    if stripping then return "" end;
    return s;
  end;

  local PARSER = Cs{
    "chunk",
    spc = (SPACE + V"comment")^0 / stripall,

    space = ((SPACE + V"comment")^1 / strip_spc)^0,

    longstring = (P"[" * Cg((P"=")^0, "init") * P"[") *
                 (ANY - (Cmt((P"]" * C((P"=")^0) * "]") * Cb"init",
                             function (s,i,a,b) return a == b end)))^0 * --luacheck: ignore
                 (P"]" * (P"=")^0 * P"]"),

    comment = (P"--" * V"longstring") +
              (P"--" * (ANY - EOL)^0),

    Name = ALPHA * ALPHANUM^0 - (
               K"and" + K"break" + K"do" + K"else" + K"elseif" +
               K"end" + K"false" + K"for" + K"function" + K"goto" + K"if" +
               K"in" + K"local" + K"nil" + K"not" + K"or" + K"repeat" +
               K"return" + K"then" + K"true" + K"until" + K"while"),

    Number = (P"-")^-1 * V"spc" * P"0x" * locale.xdigit^1 * -ALPHANUM +
             (P"-")^-1 * V"spc" * DIGIT^1 *
                 (P "." * DIGIT^1)^-1 * (S "eE" * (P "-")^-1 *
                     DIGIT^1)^-1 * -ALPHANUM +
             (P"-")^-1 * V "spc" * P "." * DIGIT^1 *
                 (S "eE" * (P "-")^-1 * DIGIT^1)^-1 * -ALPHANUM,

    String = P'"' * (P"\\" * ANY + (1 - P'"'))^0 * P'"' +
             P"'" * (P"\\" * ANY + (1 - P"'"))^0 * P"'" +
             V"longstring",

    chunk = ((SHEBANG)^-1 / "") * V"spc" * V"block" * V"spc" * EOF,

    preload = P"package.preload[" * V"preloaded_name" * P"]" * V"spc" * P"=" * V"spc" * P"function(...)" *
              V"spc" *  V"block" * V"space" * K"end" * V"space" * P";",
    preloaded_name = P'"' * ((1 - P'"')^1 / GPN) * P'"' +
                     P"'" * ((1 - P"'")^1 / GPN) * P"'",
    block = (V"stat" * ((V"spc" * P";" * V"spc") + V"space"))^0,
    stat = P";" * V"spc" +
           P"::" * V"spc" * V"Name" * V"spc" * P"::" +
           V"preload" +
           K"break" +
           K"goto" * V"space" * V"Name" +
           K"do" * V"space" * V"block" * V"space" * K "end" +
           K"while" * V"space" * V"expr" * V"space" * K "do" * V"space" *
               V"block" * V"space" * K"end" +
           K"repeat" * V"space" * V"block" * V"space" * K"until" *
               V"space" * V"expr" +
           K"if" * V"space" * V"expr" * V"space" * K"then" *
               V"space" * V"block" * V"space" *
               (K"elseif" * V"space" * V"expr" * V"space" * K"then" *
                V"space" * V"block" * V"space")^0 *
               (K"else" * V"space" * V"block" * V"space")^-1 * K"end" +
           K"for" * V"space" *
               ((V"Name" * V"spc" * P"=" * V"spc" *
                 V"expr" * V"spc" * P"," * V"spc" * V"expr" *
                 (V"spc" * P"," * V"spc" * V"expr")^-1) +
                (V"namelist" * V"space" * K"in" * V"space" * V"explist")
               )* V"space" * K"do" * V"space" * V"block" * V"space" * K"end" +
           K"return" * (V"space" * V"explist")^-1 +
           K"function" * V"space" * V"funcname" * V"spc" *  V"funcbody" +
           K"local" * V"space" * (
             (K"function" * V"space" * V"Name" * V"spc" * V"funcbody") +
             (V"namelist" * (V"spc" * P"=" * V"spc" * V"explist")^-1)) +
           V"varlist" * V"spc" * P"=" * V"spc" * V"explist" +
           V"functioncall",
    funcname = V"Name" * (V"spc" * P"." * V"spc" * V"Name")^0 *
                  (V"spc" * P":" * V"spc" * V"Name")^-1,
    namelist = V"Name" * (V"spc" * P"," * V"spc" * V"Name")^0,
    varlist = V"var" * (V"spc" * P"," * V"spc" * V"var")^0,
    value = K"nil" + K"false" + K"true" + P"..." +
            V"Number" + V"String" * V"spc" +
            V"functiondef" + V"tableconstructor" +
            V"functioncall" + V"var" +
            P"(" * V"spc" * V"expr" * V"spc" * P")" * V"spc",
    expr = V"unop" * V"spc" * V"expr" +
           V"value" * (V"binop" * V"expr")^-1,
    index = P"[" * V"spc" * V"expr" * V"spc" * P"]" +
            P"." * V"spc" * V"Name",
    call = V"args" +
           P":" * V"spc" * V"Name" * V"spc" * V"args",
    prefix = P"(" * V"spc" * V"expr" * V"spc" * P")" +
             V"Name",
    suffix = V"call" + V"index",
    var = V"prefix" * (V"spc" * V"suffix" * #(V"spc" * V"suffix"))^0 * V"spc" * V"index" +
          V"Name",
    -- <require>
    moduleargs = -- capture constant module names
                 V"modulename" + P"(" * V"spc" * V"modulename" * V"spc" * P")" +
                 -- cant capture calculated module names
                 P"(" * V"spc" * V"explist" * V"spc" * P")",
    modulename = P'"' * ((1 - P'"')^0 / GMN) * P'"' +
                 P"'" * ((1 - P"'")^0 / GMN) * P"'",
    -- </require>
    functioncall = -- <require>
                   K"require" * V"space" * V"moduleargs" * (
                      V"spc" * P"." * V"spc" * V"Name" +
                      V"spc" * (V"args" + V"index"))^0 +
                   -- </require>
                   V"prefix" * (V"spc" * V"suffix" * #(V"spc" * V"suffix"))^0 * V"spc" * V"call",
    explist = V"expr" * (V"spc" * P"," * V"spc" * V"expr")^0;
    args = P"(" * V"spc" * (V"explist" * V"spc")^-1 * P")" +
           V"tableconstructor" +
           V"String",
    functiondef = K"function" * V"spc" * V"funcbody",
    funcbody = P"(" * V"spc" * (V"parlist" * V"spc")^-1 * P")" * V"spc" *  V"block" * V"space" * K"end",
    parlist = V"namelist" * (V"spc" * P"," * V"spc" * P"...")^-1 + P"...",
    tableconstructor = P"{" * V"spc" * (V"fieldlist" * V"spc")^-1 * P"}",
    fieldlist = V"field" * (V"spc" * V"fieldsep" * V"spc" * V"field")^0 * (V"spc" * V"fieldsep")^-1,
    field = V"spc" * P"[" * V"spc" *V"expr" * V"spc" * P"]" * V"spc" * P"=" * V"spc" * V"expr"
            + V"space" * V"Name" * V"spc" * P"=" * V"spc" * V"expr" + V"expr",
    fieldsep = V"spc" * (P"," + P ";") * V"spc",
    binop = V"space" * (K"and" + K"or") * V"space" +
            V"spc" * (P".." + P"<=" + P">=" + P"==" + P"~="
                      + P"//" + P">>" + P"<<" + P"~"
                      + P"|" + P"+" + P"-" + P"*" + P"/"
                      + P"^" + P"%" + P"&" + P"<" + P">" ) * V"spc",
    unop  = V"space" *K"not" * V"space" +
            V"spc" * (P"-" + P"~" + P"#") * V"spc"
  };

  local function assert(cond, msg, ...)
    if cond then return cond end;
    assert(msg, 'assertion failed.');
    io.stderr:write(" *ERROR: " .. msg:format(...) .. "\n"); --luacheck: ignore
    os.exit(1);
  end;

  local function locate_module() end; -- forward declaration

  local function scan_file(fn, mn)
    mn = mn or 0;
    local t = {};
    function get_module_name(s)
      insert(t, s);
      return s;
    end;
    local f = assert(io.open(fn), 'cant open "' .. fn .. '".');
    sources[mn] = PARSER:match(f:read("*a"));
    f:close();
    if not sources[mn] then
      app.print('* syntax error in file "' .. fn ..'".');
      return;
    end;
    for _, n in ipairs(t) do
      locate_module(n);
    end;
    return;
  end;

  function locate_module(ModuleName)
    if (type(ModuleName) ~= "string") or
       (not args.glue) or
       tblLuaMods[ModuleName] or
       tblExcludedMods[ModuleName] or
       tblOtherMods[ModuleName] or
       tblPreloadedMods[ModuleName] then
      return;
    end;
    local f, filename;
    for p in (package.path..";".. splitpath(args.infile) .."/?.lua"):gsub("\\","/"):gmatch("([^;]+);") do --luacheck: ignore
      p = p:gsub("?",ModuleName:gsub("%.","/"));
      f = io.open(p);
      if f then
        filename = p;
        f:close();
        break;
      end;
    end;
    if filename then
      if not tblLuaMods[ModuleName] then
        tblLuaMods[ModuleName] = filename;
        scan_file(filename, ModuleName);
      end
      return;
    else
      tblOtherMods[ModuleName] = (package.preload[ModuleName] and "preloaded") or "?"; --luacheck: ignore
    end;
    return;
  end;

  local function create_amalgam(sources)
    local t = {sources[0]}; -- main source
    sources[0] = nil;
    for m in pairsByKey(tblLuaMods) do
      insert(t, #t, 'package.preload["'.. m .. '"] = function(...)\n');
      insert(t, #t, sources[m]);
      insert(t, #t, "\nend; -- module " .. m .. " \n");
      sources[m] = nil;
    end;
    local s = concat(t)
    if args.strip then
      stripping = true;
      local s1 = #s;
      s = PARSER:match(s)
      local s2 = #s;
      app.print("- strip result:\t"..string.format("%i / %i => %2.1f%% saved.", s1, s2, (1.0 - (s2/s1)) * 100.0));
    end;
    return s;
  end;

  local function print_status()
    printMessageLine("- already preloaded:\t", tblPreloadedMods);
    printMessageLine("- lua modules:\t", tblLuaMods);
    printMessageLine("- excluded modules:\t", tblExcludedMods);
    printMessageLine("- included modules:\t", tblIncludedMods);
    printMessageLine("- non lua modules:\t", tblOtherMods);
  end;

  local function find_loader()
    local function anystub()
      local function exestub(fn)
        local GLUESIG = "%%glue:L";
        --local LUACSIG = "\x1bLuaR";
        local stub;
        --fn = fn or arg[0];
        if is_exe(fn) then
          local sfile = assert(io.open(fn, "rb")); --TODO
          sfile:seek("end", -(8 + #GLUESIG));
          local stublen = "a";
          if GLUESIG == sfile:read(#GLUESIG) then
            stublen = (string.byte(sfile:read(1))) +
                      (string.byte(sfile:read(1)) * 256) +
                      (string.byte(sfile:read(1)) * 256^2) +
                      (string.byte(sfile:read(1)) * 256^3);
          else
            app.print("* exe has no lua source attached. Be shure you have chosen the right exe stub!");
          end;
          sfile:seek("set", 0);
          stub = assert(sfile:read(stublen)); --TODO
          sfile:close();
          return stub, fn;
        end
        return nil;
      end;
      --
      local stub, stubname;
      if args.loader then
        stub, stubname = exestub(args.loader);
      else
        stub, stubname = exestub(arg[0]);
      end
      return stub , stubname;
    end;
    --
    local stub, stubname = anystub();
    assert(stub, "can't find a loader.");
    app.print('- using loader in:\t"' .. stubname ..'".');
    return stub;
  end;

  local function glue(source)
    local GLUESIG = "%%glue:L"
    --local LUACSIG = "\x1bLuaR"
    local function linteger(num)
      local function byte(n)
        return math.floor(num / (256^n)) % 256;
      end;
      return string.char(byte(0), byte(1), byte(2), byte(3));
    end;
    local stub = find_loader();
    return concat{stub, source, GLUESIG, linteger(#stub), linteger(#source)};
  end;
  --
  if not args.infile then
    app.print("no source file given.");
    return;
  end;
  if not args.outfile then
    app.print("no target file given.");
    return;
  end;
  if args.exclude then
    for _, m in ipairs(args.exclude) do
      tblExcludedMods[m] = true;
      tblIncludedMods[m] = nil
    end;
  end;
  if args.include then
    for _, m in ipairs(args.include) do
      if not tblExcludedMods[m] then
        tblIncludedMods[m] = true;
      end;
    end;
  end;
  -- read main source
  scan_file(args.infile);
  if sources[0] then
    -- read manually included modules ...
    for mn in pairsByKey(tblIncludedMods) do
      locate_module(mn);
    end;
    --
    print_status();
    --
    if args.outfile then
      -- write outfile
      local of;
      sources = create_amalgam(sources);
      if is_exe(args.outfile) then
        sources = glue(sources);
        of = assert(io.open(args.outfile, "w+b"), 'cant open "' .. args.outfile .. '".');
      else
        of = assert(io.open(args.outfile, "w+"), 'cant open "' .. args.outfile .. '".');
      end;
      assert(of:write(sources), 'cant write "' .. args.outfile .. '".');
      of:close();
      app.print('* Done.\t\t"' .. args.outfile .. '" created.');
    end;
  end;
end;

local function doCompile()
  local cmdline = 'make "LUAVER=$LUAVER" "ICON=$ICON" "CLISTUB=$CLISTUB" "GUISTUB=$GUISTUB" "PRELOAD_MODS=$PRELOADMODS"';
  local function execute(cmd)
    local res1, _, res3 = os.execute(cmd);
    if type(res1) == "number" then
      return res1 == 0, res1;
    else
      return res1, res3;
    end;
  end;
  cmdline = cmdline:gsub("$(%u+)", app);
  app.print(cmdline);
  execute(cmdline.." >makeoutput.tmp 2>&1");
  local f = io.open("makeoutput.tmp");
  if f then
    local strres = f:read("*a");
    f:close();
    app.print(strres);
    os.remove("makeoutput.tmp");
  end;
  execute("make clean");
end;
--
app.print = function(msg)
  if msg then
    app.messages.append = msg;
  else
    app.messages.value = "";
  end;
end;
--
-- GUI ----------------------------------------------------------------------
--
local last_directory = ".";

app.ifSource = iup.text{value = arg[1],
  multiline = "no",
  cuebanner = "lua-source",
  expand = "HORIZONTAL",
};

app.ifTarget = iup.text{value = arg[2],
  multiline = "no",
  cuebanner = "lua-source or exe-file",
  expand = "HORIZONTAL",
};

app.ifLoader = iup.text{value = arg[3] or is_exe(arg[0]) and arg[0],
  multiline = "no",
  cuebanner = "executable containing a loader",
  expand = "HORIZONTAL",
  active = "no",
};

--
app.btBrowseSource  = iup.button{title = " Browse ",
  action = function ()
    local fd=iup.filedlg{ title = "Lua Source File",
      dialogtype = "OPEN",
      parentdialog = app.dlg,
      nochangedir = "NO",
      directory = last_directory,
      filter = "*.lua;*.wlua",
      filterinfo = "Lua Files",
      allownew = "NO",
    }
    fd:popup(iup.CENTER, iup.CENTER)
    local status = fd.status
    local filename = fd.value
    last_directory = fd.directory
    fd:destroy()
    if (status == "-1") or (status == "1") then
      if (status == "1") then
        app.print("Cannot load file " .. filename)
      end
    else
      app.ifSource.value = filename
    end
  end,
};

app.btnBrowseTarget = iup.button{title = " Browse ",
  action = function ()
    local fd = iup.filedlg{title="Target File",
      dialogtype="SAVE",
      parentdialog = app.dlg,
      nochangedir="NO",
      directory=last_directory,
      extfilter="scripts/exe (.lua;.wlua;.exe)|*.exe;*.lua;*.wlua|\z
                 executable file (.exe)|*.exe|\z
                 lua script (.lua;.wlua)|*.lua;*.wlua",
      allownew = "yes",
    };
    fd:popup(iup.LEFT, iup.LEFT)
    local status = fd.status;
    app.targetFileName = fd.value;
    last_directory = fd.directory;
    fd:destroy();
    if status ~= "-1" then
      if (app.targetFileName == nil) then
        app.print("Cannot Save file "..app.targetFileName);
      end;
      app.ifTarget.value = app.targetFileName;
    end;
  end,
};

app.btnBrowseLoader = iup.button{title = " Browse ",
  action = function ()
    local fd = iup.filedlg{title="Loader File",
      dialogtype  ="OPEN",
      parentdialog = app.dlg,
      nochangedir ="NO",
      directory   =last_directory,
      filter      ="*.exe",
      filterinfo  ="exe files",
      allownew    = "NO",
    };
    fd:popup(iup.LEFT, iup.LEFT);
    local status = fd.status;
    local loaderFileName = fd.value;
    last_directory = fd.directory;
    fd:destroy();
    if (status == "-1") or (status == "1") then
      if (status == "1") then
        app.print("Cannot read file " .. loaderFileName);
      end
    else
      app.ifLoader.value = loaderFileName;
    end;
  end,
};

app.btnAbort        = iup.button{title = " Quit ",
  name   = "btnAbort",
  expand = "horizontal",
  action = function()
    return iup.CLOSE;
  end,
};

app.btnGlue         = iup.button{title = " Glue! ",
  action = function()
    app.messages.value = ""; -- clear old messages
    doGlue{
      infile  = app.ifSource.value ~= ""  and app.ifSource.value or nil,
      outfile = app.ifTarget.value ~= ""  and app.ifTarget.value or nil,
      loader  = app.ifLoader.value  ~= "" and app.ifLoader.value or nil,
      glue    = app.cbPreloadModules.value   == "ON",
      strip   = app.cbStripWhitespaces.value == "ON",
    };
  end,
};

app.btnIcon         = iup.button{title = " Icon?",
  active = "no",
  action = function(self)
    local dlg = iup.filedlg{
      dialogtype = "open",
      directory = ".",
      extfilter = "icons|*.ico|",
      nochangedir = "no",
      parentdialog = app.dlg,
    };
    if iup.Popup(dlg,iup.CENTERPARENT,iup.CENTERPARENT) == iup.NOERROR then
      if dlg.value then
        app.ICON   = dlg.value:match("([^\\/]+).ico$");
        self.title = app.ICON;
        iup.Map(app.dlg);
        app.btnModules.active = "yes";
      end;
    end;
    --TODO:
  end,
};

app.btnModules      = iup.button{title = " Modules: ",
  expand = "horizontal",
  active = "no",
  action = function(self)
    app.modules = {
      "idle",
      "iuplua",
      "lanes.core",
      "lfs",
      "lpeg",
      "lsqlite3",
      "mime.core",
      "socket.core",
      "winapi",
    };
    app.modsChoosen = {};
    for i in ipairs(app.modules) do
      app.modsChoosen[i] = 0;
    end;
    local err = iup.ListDialog(2,"module selection",
      #app.modules,
      app.modules,
      0, 0, #app.modules,
      app.modsChoosen
    );
    if err ~= -1 then
      local selection = {};
      local i = 1;
      while i ~= (#app.modules + 1) do
        if app.modsChoosen[i] ~= 0 then
          insert(selection, app.modules[i]);
        end;
        i = i + 1;
      end;
      if #selection == 0 then
        app.PRELOADMODS = "";
        self.title = "(dynamic module loading)";
      else
        app.PRELOADMODS = table.concat(selection, " ");
        self.title = app.PRELOADMODS;
      end;
      iup.Map(app.dlg);
      app.btnCompile.active = "yes";
    end;
  end,
};

app.btnCompile      = iup.button{title = " Compile ",
  expand = "horizontal",
  active = "no",
  action = doCompile,
};
--
app.cbPreloadModules   = iup.toggle{title = "preload lua modules",
  flat = "YES",
  value = "ON",
};

app.cbStripWhitespaces = iup.toggle{title = "strip whitspaces",
  flat = "YES",
  value = "OFF",
};
--
app.lstVersion = iup.list{
  dropdown = "yes",
  "Lua 5.1",
  "Lua 5.2",
  "Lua 5.3",
  action = function(_, _, item)
    app.LUAVER = "5"..item;
    app.lstGuiCli.active = "yes";
  end;
};

app.lstGuiCli  = iup.list{
  active = "no",
  dropdown = "yes",
  "GUI",
  "CLI",
  action = function(_, text)
    if text == "CLI" then
      app.CLISTUB = "true";
      app.GUISTUB = "";
    elseif text == "GUI" then
      app.CLISTUB = "";
      app.GUISTUB = "true";
    end;
    app.btnIcon.active = "yes";
  end;
};

--
app.messages = iup.text{
  multiline  = "yes",
  border     = "no",
  canfocus   = "no",
  readonly   = "yes",
  formatting = "yes",
  expand     = "yes",
};
--
app.dlg = iup.dialog{title = "wGlue "..VERSION,
  minsize      = "640x340",
  defaultesc   = app.btnAbort,
  defaultenter = app.btnGlue,
  iup.vbox{
    cgap = "2",
    cmargin = "1x1",
    iup.frame{--title = "source/target"
      iup.gridbox{
        NUMDIV = 3,
        cgapcol = 5,
        cgaplin = 2,
        iup.label{ title = "Source:",
          padding = "1x2",
        },
        app.ifSource,
        app.btBrowseSource,
        iup.label{ title = "Target:",
          padding = "1x2",
        },
        app.ifTarget,
        app.btnBrowseTarget,
      },
    },
    iup.frame{--title = "Loader",
      iup.gridbox{
        NUMDIV = 3,
        cgapcol = 5,
        cgaplin = 2,
        iup.label{title = "Loader:",
          padding = "1x2",
        },
        app.ifLoader,
        app.btnBrowseLoader,
        ifSources(iup.label{title = "build:",
            padding = "1x4",
          }
        ),
        ifSources(iup.hbox{
            app.lstVersion,
            app.lstGuiCli,
            app.btnIcon,
            app.btnModules,
          }
        );
        ifSources(app.btnCompile),
      },
    },
    iup.frame{title = "glue options",
      iup.hbox{
        alignment = "ACENTER",
        app.cbPreloadModules,
        app.cbStripWhitespaces,
        --iup.button{title = "include module(s)",
        --  flat = "YES",
        --},
        iup.fill{},
      },
    },
    iup.frame{title = "messages",
      app.messages,
    },
    iup.hbox{
      cmargin = "0x2",
      app.btnAbort,
      app.btnGlue,
    },
  },
};
--
-- Main Loop ----------------------------------------------------------------
--
app.dlg:showxy();
app.print(("WGlue %s (%s)"):format(VERSION, luaVersion()));
printMessageLine("* preloaded modules: ", package.preload);
iup.MainLoop();
iup.Close();
