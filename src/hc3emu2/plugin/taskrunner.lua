--%%name=TaskRunner

local emu = fibaro.hc3emu
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
    local device = emu.loadQA(name,nil, true)
    assert(device, "Emulator installation error")
    local fqa = emu.getFQA(device.id)
    assert(fqa, "FQA creation error")
    res,code = emu.uploadFQA(fqa)
    assert(code < 206, "Failed to upload QuickApp: " .. (res or "unknown error"))
  end)
  if not stat then
    ERROR("Failed to upload QuickApp: %s (%s)", name, err)
  else
    print("QuickApp uploaded successfully:", name)
  end
end

function task.updateFile(fname)
  print("Updating QA file:",tostring(fname)) -- fname
  local f = io.open(".project","r")
  assert(f,"No .project file found")
  local p = f:read("*a")
  f:close()
  p = json.decode(p)
  for qn,fn in pairs(p.files or {}) do
    if fname==fn then 
      local content = emu.readFile(fn)
      local f = {name=qn, isMain=qn=='main', isOpen=false, type='lua', content=content}
      local r,err = api.put("/quickApp/"..p.id.."/files/"..qn,f)
      if not r then 
        local r,err = api.post("/quickApp/"..p.id.."/files",f)
        if err then
          ERROR("creating QA:%s, file:%s, QAfile%s",p.id,fn,qn)
        else
          printf("Created QA:%s, file:%s, QAfile%s",p.id,fn,qn)
        end
      else 
        printf("Updated QA:%s, file%s, QAfile:%s ",p.id,fn,qn)
      end
      os.exit(0)
    end
  end
  ERROR("%s not found in current project",fname)
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

__TAG = "TASKRUNNER"
if type(args) ~= "table" then ERROR("No task command specified") end
__TAG = args.cmd or __TAG 
task[args.cmd or "error"](table.unpack(args.args))
os.exit(0)