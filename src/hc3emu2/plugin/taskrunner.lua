--%%name=TaskRunner
--%%nodebug=true
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
    local dev = _emu.devices[device.id]
    if dev and dev.headers and dev.headers.minify then
      emu.minifyCode(fqa.files)
    end
    local res,code = emu.uploadFQA(fqa)
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
    data = data or {}
    for qn,fn in pairs(data.files or {}) do
      if fn==fname then
        return true,data.id, qn, data
      end
    end
  end
  local path,file = fname:match("^(.-)([^/\\]+)$")
  if not path then path = "" end
  local p1 = path..".project"
  local p2 = ".project"
  local _,id,name,data = find(p1)
  if id then return true,id,name,data end
  return find(p2)
end

function task.updateQA(fname)
  print("Updating QA:",tostring(fname)) -- fname
  local exist,id,qn,data = findIdAndName(fname)
  assert(exist,"No .project file found for " .. fname)
  assert(id,"No entry for "..fname.." in .project file")
  assert(data,"No .project found for "..fname)
  local qa = api.hc3.get("/devices/"..id)
  if not qa then
    ERROR("QuickApp on HC3 with ID %s not found", id)
  end
  local device = emu.loadQA(fname,{proxy="false"}, true)
  assert(device, "Emulator installation error")
  assert(qa.type == device.type, "QuickApp type mismatch: expected " .. device.type .. ", got " .. qa.type)
  local fqa = emu.getFQA(device.id)
  assert(fqa, "FQA creation error")

  local oldFiles = api.get("/quickApp/"..id.."/files") or {}
  local oldMap,existingFiles,newFiles = {},{},{}
  for _,f in ipairs(oldFiles) do oldMap[f.name] = f end
  for n,_ in pairs(data.files) do
    local flag = oldMap[n]
    oldMap[n]=nil
    if flag then existingFiles[n] = true else newFiles[n] = true end
  end

  -- Delete files no longer part of QA
  for name,_ in pairs(oldMap) do
    local r,err = api.hc3.delete("/quickApp/"..id.."/files/"..name)
    if err > 206 then
      ERROR("Failed to delete file %s from QuickApp %s: %s", name, id, err)
    else
      printf("Deleted file %s from QuickApp %s", name, id)
    end
  end

  -- Create new files
  for name,_ in pairs(newFiles) do
    local path = data.files[name]
    local f = {name=name, isMain=false, isOpen=false, type='lua', content=emu.readFile(path)}
    local r,err = api.hc3.post("/quickApp/"..id.."/files",f)
    if err > 206 then
      ERROR("Failed to create file %s in QuickApp %s: %s", name, id, err)
    else
      printf("Created file %s in QuickApp %s", name, id)
    end
  end

  -- Update existing files
  local ufiles = {}
  for name,_ in pairs(existingFiles) do
    local path = data.files[name]
    local ef = api.hc3.get("/quickApp/"..id.."/files/"..name)
    local content = emu.readFile(path)
    if content == ef.content then
      printf("Untouched file %s:%s in QuickApp %s", name, path, id)
    else
      local f = {name=name, isMain=name=='main', isOpen=false, type='lua', content=content}
      ufiles[#ufiles+1] = f
    end
  end
  if ufiles[1] then
    local r,err = api.hc3.put("/quickApp/"..id.."/files",ufiles)
    if err > 206 then
      ERROR("Failed to update files for QuickApp %s: %s", id, err)
    else
      for name,_ in pairs(existingFiles) do
        printf("Updated file %s:%s in QuickApp %s", name, data.files[name], id)
      end
    end
  end

  local function update(prop,value)
    return api.hc3.post("/plugins/updateProperty",{
      deviceId = id,
      propertyName = prop,
      value = value
    })
  end

  -- Update UI...
  local res,err = api.hc3.put("/devices/"..id,{
    properties = {
      viewLayout = fqa.initialProperties.viewLayout,
      uiCallbacks = fqa.initialProperties.uiCallbacks
    }
  })
  if err > 206 then ERROR("Failed to update QuickApp viewLayout for %s: %s", id, err) end
  -- r, err = update("uiView", fqa.initialProperties.uiView)
  -- if err > 206 then ERROR("Failed to update QuickApp uiView for %s: %s", id, err) end
  -- r, err = update("uiCallbacks", fqa.initialProperties.uiCallbacks)
  -- if err > 206 then ERROR("Failed to update QuickApp uiCallbacks for %s: %s", id, err) end

  -- Update other properties
  local updateProps = {
    "quickAppVariables","manufacturer","model","buildNumber",
    "userDescription","quickAppUuid","deviceRole"
  }
  for _,prop in ipairs(updateProps) do 
    local value = fqa.initialProperties[prop]
    if value ~= nil and value ~= "" and value ~= device.properties[prop] then 
      update(prop, value) 
      if prop == "quickAppVariables" then
        value = json.encode(value)
        if #value > 40 then 
          value = value:sub(1, 40) .. "..."
        end
      end
      printf("Updated property %s to '%s' for QuickApp %s", prop, value, id)
    end
  end

  local function trueMap(arr) local r={} for _,v in ipairs(arr) do r[v]=true end return r end
  -- Update interfaces
  local interfaces = fqa.initialInterfaces or {}
  local oldInterfaces = qa.interfaces or {}
  local newMap,oldMap = trueMap(interfaces),trueMap(oldInterfaces)
  local newIfs,oldIfs = {},{}
  for i,_ in pairs(newMap) do if not oldMap[i] then newIfs[#newIfs+1] = i end end
  for i,_ in pairs(oldMap) do if not newMap[i] then oldIfs[#oldIfs+1] = i end end
  if #newIfs > 0 then 
    local res,code = api.hc3.restricted.post("/plugins/interfaces", {action = 'add', deviceId = id, interfaces = newIfs})
    if code > 206 then
      ERROR("Failed to add interfaces to QuickApp %s: %s", id, code)
    else
      printf("Added interfaces to QuickApp %s: %s", id, table.concat(newIfs, ", "))
    end
  end
  if #oldIfs > 0 then 
    local res,code = api.hc3.restricted.post("/plugins/interfaces", {action = 'delete', deviceId = id, interfaces = oldIfs})
    if code > 206 then
      ERROR("Failed to delete interfaces from QuickApp %s: %s", id, code)
    else
      printf("Deleted interfaces from QuickApp %s: %s", id, table.concat(oldIfs, ", "))
    end
  end

  printf("Done")
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