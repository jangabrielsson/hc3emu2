local fileNum = 0
local function createTempName(suffix)
  fileNum = fileNum + 1
  return os.date("hc3emu%M%M")..fileNum..suffix
end

local function findFirstLine(src)
  local n,first,init = 0,nil,nil
  for line in string.gmatch(src,"([^\r\n]*\r?\n?)") do
    n = n+1
    line = line:match("^%s*(.*)")
    if not (line=="" or line:match("^[%-]+")) then 
      if not first then first = n end
    end
    if line:match("%s*QuickApp%s*:%s*onInit%s*%(") then
      if not init then init = n end
    end
  end
  return first or 1,init
end

local function loadQAString(src,optionalDirectives) -- Load QA from string and run it
  local path = Emu.config.tempDir..createTempName(".lua")
  local f = io.open(path,"w")
  assert(f,"Can't open file "..path)
  f:write(src)
  f:close()
  ---@diagnostic disable-next-line: need-check-nil
  return Emu:installQuickAppFile(path)
end


local function markArray(t) if type(t)=='table' then json.util.InitArray(t) end end
local function arrayifyFqa(fqa)
  markArray(fqa.initialInterfaces)
  markArray(fqa.initialProperties.quickAppVariables)
  markArray(fqa.initialProperties.uiView)
  markArray(fqa.initialProperties.uiCallbacks)
  markArray(fqa.initialProperties.supportedDeviceRoles)
end

local function uploadFQA(fqa)
  assert(type(fqa) == "table", "fqa must be a table")
  assert(fqa.name, "fqa must have a name")
  assert(fqa.type, "fqa must have a type")
  assert(fqa.files, "fqa must have files")
  assert(fqa.files[1], "fqa must have a main file")
  arrayifyFqa(fqa)
  local res,code = Emu.api.hc3.post("/quickApp/",fqa)
  if not code or code > 201 then
    Emu:ERRORF("Failed to upload FQA: %s", res)
  else
    Emu:DEBUG("Successfully uploaded FQA with ID: %s", res.id)
  end
  return res,code
end

local function getFQA(id) -- Creates FQA structure from installed QA
  local dev = Emu.devices[id]
  assert(dev,"QuickApp not found, ID"..tostring(id))
  local struct = dev.device
  local files = {}
  for _,f in ipairs(dev.files) do
    if f.content == nil then f.content = Emu.lib.readFile(f.fname) end
    files[#files+1] = {name=f.name, isMain=false, isOpen=false, type='lua', content=f.content}
  end
  local initProps = {}
  local savedProps = {
    "uiCallbacks","quickAppVariables","uiView","viewLayout","apiVersion","useEmbededView",
    "manufacturer","useUiView","model","buildNumber","supportedDeviceRoles",
    "userDescription","typeTemplateInitialized","quickAppUuid","deviceRole"
  }
  for _,k in ipairs(savedProps) do initProps[k]=struct.properties[k] end
  return {
    apiVersion = "1.3",
    name = struct.name,
    type = struct.type,
    initialProperties = initProps,
    initialInterfaces = struct.interfaces,
    files = files
  }
end

local function saveQA(id,fileName) -- Save installed QA to disk as .fqa  //Move to QA class
  local dev = Emu.devices[id]        
  fileName = fileName or dev.headers.save
  assert(fileName,"No save filename found")
  local fqa = getFQA(id)
  arrayifyFqa(fqa)
  local vars = table.copy(fqa.initialProperties.quickAppVariables or {})
  markArray(vars) -- copied
  fqa.initialProperties.quickAppVariables = vars
  local conceal = dev.headers.conceal or {}
  for _,v in ipairs(vars) do
    if conceal[v.name] then 
      v.value = conceal[v.name]
    end
  end
  local f = io.open(fileName,"w")
  assert(f,"Can't open file "..fileName)
  f:write(json.encode(fqa))
  f:close()
  Emu:DEBUG("Saved QuickApp to %s",fileName)
end

local function loadQA(path,optionalHeaders,noRun)   -- Load QA from file and maybe run it
  optionalHeaders = optionalHeaders or {}
  optionalHeaders.norun = tostring(noRun==true) -- If noRun is true, don't run the QuickApp
  local struct = Emu:installQuickAppFile(path,optionalHeaders)
  return struct
end

local function saveProject(id,dev)  -- Save project to .project file
  local r = {}
  for _,f in ipairs(dev.files) do
    r[f.name] = f.fname
  end
  r.main = self.fname
  local f = io.open(".project","w")
  assert(f,"Can't open file "..".project")
  f:write(json.encodeFormated({files=r,id=id}))
  f:close()
end

return {
  createTempName = createTempName,
  findFirstLine = findFirstLine,
  loadQAString = loadQAString,
  uploadFQA = uploadFQA,
  getFQA = getFQA,
  saveQA = saveQA,
  loadQA = loadQA,
  saveProject = saveProject,
}