local cmdLine, mode, mainFile, args
local startupMode = { 
  run=true, test=true, terminal=true,
  uploadQA=true, downloadUnpack=true, updateFile=true, updateQA=true,
}
for i=-1,5 do
  local a = arg[i] or ""
  if startupMode[a] then
    cmdLine = {table.unpack(arg,i)}
    break
  end
end
assert(cmdLine,"hc3emu2 not found in command line arguments")
args = {}
local flags = {}
for i,f in ipairs(cmdLine) do 
  if f:sub(1,1)=='-' then flags[f:sub(2)]=true
  else args[#args+1]=f end
end

mode = args[1]
table.remove(args,1) -- remove mode from args
mainFile = args[1]

assert(mode,"Missing mode command line argument")
assert(not flags.terminal or mainFile,"Missing file command line argument")

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

if flags.develop or _DEVELOP then -- Running in developer mode
  _DEVELOP = "./"
  local root = os.getenv("HC3EMUROOT")
  if root then
    _DEVELOP = root
    if not _DEVELOP:match("/$") then _DEVELOP = _DEVELOP.."/" end
  end
  package.path = ";".._DEVELOP.."src/?;".._DEVELOP.."src/?.lua;"..package.path
end

local taskArgs = {}
if mode ~= "run" then
  local taskrunner = package.searchpath("hc3emu2.plugin.taskrunner",package.path)
  taskArgs = {cmd=mode,args=args,flags=flags}
  mainFile = taskrunner
end

local emu = package.searchpath("hc3emu2.emu",package.path)
assert(emu,"hc3emu2.emu not found in package.path")

loadfile(emu)(mode, mainFile, flags, taskArgs)