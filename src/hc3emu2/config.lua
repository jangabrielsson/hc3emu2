_DEVELOP=_DEVELOP

local EMU_DIR = "emu"
local EMUSUB_DIR = "emu/pages"

lfs = require("lfs")
socket = require("socket")
local fmt = string.format

local cmdLine = arg[-3] or ""
local debuggerType = "unknown"
if cmdLine:match("actboy168") then debuggerType="actboy168" end
if cmdLine:match("mobdebug") then debuggerType="mobdebug" end
local cfgFileName = ".hc3emu.lua"   -- Config file in current directory
local homeCfgFileName = ".hc3emu.lua"  -- Config file in home directory

local win = (os.getenv('WINDIR') or (os.getenv('OS') or ''):match('[Ww]indows')) and not (os.getenv('OSTYPE') or ''):match('cygwin') -- exclude cygwin
local fileSeparator = win and '\\' or '/'
local tempDir = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp/" -- temp directory
local homeDir = os.getenv("HOME") or os.getenv("homepath") or ""
local currentDir = lfs.currentdir()
local isVscode = package.path:lower():match("vscode") ~= nil
local isZerobrane = package.path:lower():match("zerobrane") ~= nil

local function findFile(path,fn,n)
  n = n or 0
  if n > 4 then return nil end
  local dirs = {}
  for file in lfs.dir(path) do
    if file ~= "." and file ~= ".." then
      local f = path..fileSeparator..file
      if fn == file then return f end
      local attr = lfs.attributes (f)
      assert(type(attr) == "table")
      if attr.mode == "directory" then
        dirs[#dirs+1] = f
      end
    end
  end
  for i,dir in ipairs(dirs) do
    local f = findFile(dir,fn,n+1)
    if f then return f end
  end
  return nil
end

-- Try to locate the user's rsrcrs directory in the installed rock
local function findRsrscsDir()
  local file = "devices.json"
  local path = "src/rsrcs"..fileSeparator..file
  local len = -(#file+2)
  local develop = _DEVELOP
  if type(develop)=="boolean" then 
    develop = ".."..fileSeparator..lfs.currentdir():match("[%w+%-_ ]+$")
  end
  if develop then
    path = develop..fileSeparator.."src"..fileSeparator.."rsrcs"
    local currentDir = lfs.currentdir()
    local prefs = develop:match("([/\\%.]+)") or develop
    prefs:gsub("(%.%.)",function() 
      path = path:match("^.-[/\\](.*)")
      currentDir = currentDir:match("(.-)[/\\][%w+%-_ ]+$") 
    end)
    path = currentDir..fileSeparator..path
    local attr = lfs.attributes(path)
    if attr and attr.mode == "directory" then return path end
    assert(attr, "Failed to get _DEVELOP path to /rsrcs "..path)
  end
  local datafile = require("datafile")
  local f,p = datafile.open(path)
  if (not _DEVELOP) and p:match("^.[/\\]rsrcs") then f:close(); f = nil end -- found wrong (local) directory
  if f then f:close() return p:sub(1,len) end
  p = package.searchpath("hc3emu2",package.path)
  assert(p,"Failed to find "..path)
  
  -- Try to locate scoop installed rock
  -- C:\Users\jgab\scoop\apps\luarocks\3.11.1\rocks\lib\luarocks\rocks-5.4\hc3emu\1.0.70-1\rsrcs
  local dir = p:match(".:\\Users\\%w+\\scoop\\apps\\luarocks\\")
  if dir then
    dir = dir.."3.11.1\\rocks\\lib\\luarocks\\rocks-5.4\\hc3emu\\"
    local p = findFile(dir,file)
    if p then return p:sub(1,len) end
  end
  
  local p = os.getenv("EMU_RSRCS")
  if p then 
    local f = findFile(p,file)
    if f then return f:sub(1,len) end
  end
end

local function readFile(fname,silent)
  local f = io.open(fname, "r")
  if not f and silent then return end
  assert(f, "Cannot open file: " .. fname)
  local code = f:read("*a")
  f:close()
  return code
end

local function writeFile(filename, content)
  local file = io.open(filename, "w")
  if file then
    file:write(content)
    file:close()
    return true
  else
    Emu:ERRORF("Error writing to file %s", filename)
    return false
  end
end

local rsrcsDir = findRsrscsDir()
assert(rsrcsDir, "Failed to find rsrcs directory")

local function rsrcsPath(name) return rsrcsDir..fileSeparator..name end
local function loadResource(path) return readFile(rsrcsPath(path)) end

local someRandomIP = "192.168.1.122" --This address you make up
local someRandomPort = "3102" --This port you make up
local mySocket = socket.udp() --Create a UDP socket like normal
mySocket:setpeername(someRandomIP,someRandomPort)
local myDevicesIpAddress,_ = mySocket:getsockname()-- returns IP and Port
myDevicesIpAddress = myDevicesIpAddress == "0.0.0.0" and "127.0.0.1" or myDevicesIpAddress

local function setupRsrscsDir(flag)
  local function transVars(page)
    local function patchVar(var,value)
      page = page:gsub(var.." = \"(.-)\";",function(ip) 
        return fmt(var.." = \"%s\";",value)
      end)
    end
    patchVar("EMU_API",fmt("http://%s:%s",Emu.config.pip,Emu.config.wport))
    patchVar("USER_HOME",homeDir:gsub("\\","/"))
    patchVar("EMUSUB_DIR",EMUSUB_DIR)
    return page
  end
  
  local files = {
    ['style.css']={dest=EMUSUB_DIR.."/style.css"},
    ['script.js']={dest=EMUSUB_DIR.."/script.js"},
    ['quickapps.html']={dest=EMUSUB_DIR.."/quickapps.html"},
    ['devices.html']={dest=EMUSUB_DIR.."/devices.html",trans=transVars},
    --['editSettings.html']={dest=EMUSUB_DIR.."/editSettings.html"},
    ['emu.html']={dest=EMU_DIR.."/_emu.html"}
  }
  
  local a,b = lfs.mkdir(EMU_DIR)
  local a,b = lfs.mkdir(EMUSUB_DIR)
  assert((b==nil or b=="File exists"),"Failed to create directory "..EMU_DIR)
  
  if b == "File exists" then
    for file in lfs.dir(EMU_DIR) do
      if file:sub(1,1) ~= "_" and file:sub(-5) == ".html" then
        os.remove(EMU_DIR..fileSeparator..file)
      end
    end
  end
  
  if flag ~= "install" and b == "File exists" then return end
  
  for source,dest in pairs(files) do
    local page = loadResource(source)
    if dest.trans then page = dest.trans(page) end
    writeFile(dest.dest, page)
    Emu:DEBUG("%s installed",dest.dest)
  end
end

local function loadLuaFile(path)
  local res = {}
  if not lfs.attributes(path) then return true,res,path end
  local f,err = loadfile(path,"bt",_G)
  if not f then return f,err,path end
  local err,res = pcall(f)
  return err,res,path
end

local function merge(a, b)
  if type(a) == 'table' and type(b) == 'table' then
    for k,v in pairs(b) do if type(v)=='table' and type(a[k] or false)=='table' then merge(a[k],v) else a[k]=v end end
  end
  return a
end

local stat,homeCfg,path = loadLuaFile(homeDir..fileSeparator..homeCfgFileName)
assert(stat and type(homeCfg)=='table',"Config file error: "..path.." "..tostring(homeCfg))
local stat,projCfg,path = loadLuaFile(cfgFileName)
assert(stat and type(projCfg)=='table',"Config file error: "..path.." "..tostring(projCfg))

local userConfig = merge(homeCfg,projCfg)

local function formatedLua(tab)
  local function format(tab,indent)
    indent = indent or 2
    local buff = {"{"}
    for k,v in pairs(tab) do
      if type(v) == "table" then
        buff[#buff+1] = fmt("%s%s = %s",string.rep(" ",indent),k,format(v,indent+2))
        buff[#buff+1]= string.rep(" ",indent).."},"
      elseif type(v) == "string" then
        buff[#buff+1] = fmt("%s%s = \"%s\",",string.rep(" ",indent),k,v)
      else
        buff[#buff+1] = fmt("%s%s = %s,",string.rep(" ",indent),k,tostring(v))
      end
    end
    return table.concat(buff,"\n")
  end
  return format(tab,2).."\n}"
end

local function installation(creds,hc3)
  setupRsrscsDir(true)
  local homeFile = homeDir..fileSeparator..homeCfgFileName
  local stat,cfg,path = loadLuaFile(homeFile)
  assert(stat and type(homeCfg)=='table',"Failed to load "..path)
  cfg.user = creds.user or cfg.user
  hc3.user = cfg.user or hc3.user
  cfg.password = creds.pass or cfg.password
  hc3.pwd = cfg.password or hc3.pwd
  cfg.url = creds.url or cfg.url
  hc3.url = cfg.url or hc3.url
  cfg.pin = creds.url or cfg.pin
  hc3.pin = cfg.pin or hc3.pin
  writeFile(homeFile, "return "..formatedLua(cfg))
  Emu:DEBUG("Set user,password,url in %s",homeFile)
end

do
  local f = io.open(".env")
  if f then
    local txt = f:read("*a")
    f:close()
    txt = txt.."\n"
    local vars = {}
    txt:gsub("([%w_]+)%s*=%s*(.-)%s*\n",function(name,value)
      vars[name] = value
    end)
    local getenv = os.getenv
    function os.getenv(name)
      if vars[name] ~= nil then return vars[name] else return getenv(name) end
    end
  end
end

return {
  EMU_DIR = EMU_DIR,
  EMUSUB_DIR = EMUSUB_DIR,
  userConfig = userConfig,
  readFile = readFile,
  writeFile = writeFile,
  installation = installation,
  rsrcsDir = rsrcsDir,
  rsrcsPath = rsrcsPath,
  filePath = function(mname) return package.searchpath(mname,package.path) end,
  readRsrcsFile = function(name) return readFile(rsrcsPath(name)) end,
  
  setupRsrscsDir = setupRsrscsDir,
  ipAddress = myDevicesIpAddress,
  debuggerType = debuggerType,
  cfgFileName = cfgFileName,
  homeCfgFileName = homeCfgFileName,
  win = win,
  fileSeparator = fileSeparator,
  tempDir = tempDir,
  homeDir = homeDir,
  currentDir = currentDir,
  isVscode = isVscode,
  isZerobrane = isZerobrane,
}
