--%%name=TaskRunner
--%%plugin=$hc3emu2.plugin.terminal

local emu = fibaro.hc3emu
local lfs = emu.lua.require("lfs")
local io = emu.lua.io
local args = fibaro.hc3emu.taskargs
local task = {}

local function printf(...) print(string.format(...)) end
local function ERROR(...)
  print("ERROR:", string.format(...))
  os.exit(-1)
end

function task.error()
  ERROR("No task command specified")
end

function task.uploadQA(name)
  print("Uploading QuickApp:", name)
  local stat,err = pcall(function()
    local device = emu.loadQA(name,{proxy="false"}, true)
    assert(device, "Emulator installation error")
    local fqa = emu.getFQA(device.id)
    assert(fqa, "FQA creation error")
    local dev = emu.devices[device.id]
    if dev and dev.headers and dev.headers.minify then
      emu.minifyCode(fqa.files)
    end
    res,code = emu.uploadFQA(fqa)
    assert(code < 206, "Failed to upload QuickApp: " .. (tostring(code) or "unknown error"))
  end)
  if not stat then
    ERROR("Failed to upload QuickApp: %s (%s)", name, err)
  else
    print("QuickApp uploaded successfully:", name)
  end
end

local function findIdAndName(fname)
  local function find(path)
    local f = io.open(path,"r")
    if not f then return false,nil end
    local p = f:read("*a")
    f:close()
    local _,data = pcall(json.decode,p)
    for qn,fn in pairs(data.files or {}) do
      if fn==fname then
        return true,data.id, qn
      end
    end
  end
  local path,file = fname:match("^(.-)([^/\\]+)$")
  if not path then path = "" end
  local p1 = path..".project"
  local p2 = ".project"
  local _,id,name = find(p1)
  if id then return true,id,name end
  return find(p2)
end

function task.updateFile(fname)
  print("Updating QA file:",tostring(fname)) -- fname
  local exist,id,qn = findIdAndName(fname)
  assert(exist,"No .project file found for " .. fname)
  assert(id,"No entry for "..fname.." in .project file")
  local qa = api.hc3.get("/devices/"..id)
  if not qa then
    ERROR("QuickApp on HC3 with ID %s not found", id)
  end
  local content = emu.readFile(fname)
  local f = {name=qn, isMain=qn=='main', isOpen=false, type='lua', content=content}
  local r,err = api.hc3.put("/quickApp/"..id.."/files/"..qn,f)
  if not r then 
    local r,err = api.hc3.post("/quickApp/"..id.."/files",f)
    if err then
      ERROR("creating QA:%s, file:%s, QAfile%s",id,fname,qn)
    else
      printf("Created QA:%s, file:%s, QAfile%s",id,fname,qn)
    end
  else 
    printf("Updated QA:%s, file%s, QAfile:%s ",id,fname,qn)
  end
  os.exit(0)
end

function task.downloadUnpack(id,path)
  local stat,res = pcall(function()
    if path=="." or path=="" then path="./" end
    if not path:match("/$") then path = path.."/" end
    printf("Downloading QA: %s to %s",tostring(id),tostring(path)) -- id
    local deviceId = tonumber(id)
    __assert_type(deviceId, "number")
    emu.downloadFQA(deviceId,path)
  end)
  if not stat then
    ERROR("Failed to download QuickApp: %s", res)
  else
    print("QuickApp downloaded successfully:", id)
  end
end

function task.terminal(path) -- file to run in terminal, if any
  fibaro.hc3emu.plugin.terminal()
  if path and lfs.attributes(path) then
    local flags = args.flags
    local extra = {}
    emu.loadQA(path,extra)
  end
  return "run"
end

__TAG = "TASKRUNNER"
if type(args) ~= "table" then ERROR("No task command specified") end
__TAG = args.cmd or __TAG 
if task[args.cmd or "error"](table.unpack(args.args)) ~= "run" then
  os.exit(0)
end