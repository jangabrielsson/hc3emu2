_DEVELOP=_DEVELOP

local EMU_DIR = "emu"
local EMUSUB_DIR = "emu/pages"

lfs = require("lfs")
socket = require("socket")
local fmt = string.format

local cmdLine = arg[-1] or ""
local debuggerType = "unknown"
if cmdLine:match("actboy168") then debuggerType="actboy168" end
if cmdLine:match("mobdebug") then debuggerType="mobdebug" end
local cfgFileName = "hc3emu.json"   -- Config file in current directory
local homeCfgFileName = ".hc3emu.json"  -- Config file in home directory
  
local win = (os.getenv('WINDIR') or (os.getenv('OS') or ''):match('[Ww]indows')) and not (os.getenv('OSTYPE') or ''):match('cygwin') -- exclude cygwin
local fileSeparator = win and '\\' or '/'
local tempDir = os.getenv("TMPDIR") or os.getenv("TEMP") or os.getenv("TMP") or "/tmp/" -- temp directory
local homeDir = os.getenv("HOME") or os.getenv("homepath") or ""
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

local rsrcDir = findRsrscsDir()
assert(rsrcDir, "Failed to find rsrcs directory")

local function rsrcsPath(name) return rsrcDir..fileSeparator..name end
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
    ['editSettings.html']={dest=EMUSUB_DIR.."/editSettings.html"},
    ['emu.html']={dest=EMU_DIR.."/_emu.html"},
    ['setup.html']={dest=EMU_DIR.."/_setup.html",trans=transVars},
  }

  local a,b = lfs.mkdir(EMU_DIR)
  local a,b = lfs.mkdir(EMUSUB_DIR)
  assert((b==nil or b=="File exists"),"Failed to create directory "..EMU_DIR)
  if flag ~= "install" and b == "File exists" then return end

  for source,dest in pairs(files) do
    local page = loadResource(source)
    if dest.trans then page = dest.trans(page) end
    writeFile(dest.dest, page)
    Emu:DEBUG("%s installed",dest.dest)
  end
end

return {
  readFile = readFile,
  writeFile = writeFile,
  rsrcDir = rsrcDir,
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
  isVscode = isVscode,
  isZerobrane = isZerobrane,
}
