Emu = Emu
local fmt = string.format
local copas = require("copas")
local embed = require("hc3emu2.embedui")

---@class Device
Device = {}
class 'Device'
function Device:__init(args)
  self.id = args.id
  self.device = args.device
  if args.resource then return end -- "Non QA devices, ex. deviceId 1"
  self.files = args.files or {}
  self.env = args.env
  self.vars = args.vars   -- internalStorageVars
  self.UI = args.UI or {}
  self.orgUI = table.copy(self.UI)
  self.watches = args.watches or {}
  self.headers = args.headers or {}
  self.pageName = args.pageName
  self.uiPage = nil
  
  local embedElements = embed.embedUIs[self.device.type] -- Add embed/stock UI elements for device type
  for i,r in ipairs(embedElements or {}) do table.insert(self.UI,i,r) end
  if self.headers.webUI then
    if self.device.isChild then -- Decide html page name for QA
      local name = (self.device.name or "Child"):gsub("[^%w]","")
      self.pageName = fmt("%s_%s.html",name,self.id)
    else
      local name = self.device.name:gsub("[^%w]","")
      self.pageName = fmt("%s.html",name)
    end
  end
  
  local index = {}
  self:initializeUI(self.UI,index)
  setmetatable(self.UI,{
    __index=function(t,k) if index[k] then return index[k] else return rawget(t,k) end end,
  })
end

function Device:watching(prop,value) 
  --print("WATCH",args.id,prop)
  if self.watches[prop] then self.watches[prop](value) end
end

local compMap = {
  text = function(v) return v end, 
  value = function(v) if type(v)=='table' then return v[1] else return v end end,
  options = function(v) return v end,
  selectedItem = function(v) return v end,
  selectedItems = function(v) return v end
}

function Device:updateView(componentName,propertyName,value) 
  --print("UPDATEVIEW",args.id,componentName,propertyName,value)
  local UI = self.UI
  local elm = UI[componentName]
  if not elm then return end
  if compMap[propertyName] then value = compMap[propertyName](value) end
  if value ~= elm[propertyName] then 
    elm[propertyName] = value 
    Emu:post({type='quickApp_updateView',id=self.id})
  end
end

function Device:toArgs() 
  return {
    id=self.id, 
    device=self.device, 
    files=self.files,
    vars=self.vars, 
    UI=self.orgUI,
    headers=self.headers, 
    uiPage=self.uiPage
  }
end

function Device:initializeUI(UI,index)
  if type(UI) ~= 'table' then return end
  local typ = Emu.lib.ui.getElmType(UI)
  if not typ then for _,r in ipairs(UI) do self:initializeUI(r,index) end return end
  UI.type = typ
  local componentName = UI[typ]
  if index[componentName] then
    Emu:DEBUGF('warn',"Duplicate UI element %s in %s",componentName,self.device.name)
  end
  index[componentName] = UI
  if componentName then -- Also primes the UI element with default values, in particular from embedded UI elements
    local sval = embed.embedProps[componentName] and embed.embedProps[componentName](self) or nil
    if UI.label then UI.text = sval or UI.text end
    if UI.button then UI.text = UI.text end
    if UI.slider then 
      UI.value = sval or UI.value 
    end
    if UI.switch then UI.value = UI.value end
    if UI.select then 
      UI.value = UI.values 
      UI.options = UI.options or {}
    end
    if UI.multi then 
      UI.value = UI.values 
      UI.options = UI.options or {}
    end
  end
end

local stdFuns = { 
  'setmetatable', 'getmetatable', 'assert', 'rawget', 'rawset', 'pairs', 
  'print', 'ipairs', 'tostring', 'tonumber', 'string', 'table', 
  'math', 'pcall', 'xpcall', "error", "json", "select", "collect_garbage",
  "next"
}

SocketServer = SocketServer
local hc3emuFuns = nil
local function hc3emuExports(emu) 
  return { 
  lua = emu.lua, loadQA = emu.lib.loadQA, loadQAString = emu.lib.loadQAString, uploadFQA = emu.lib.uploadFQA, minifyCode = emu.lib.minifyCode,
  downloadFQA = emu.lib.downloadFQA,
  getFQA = emu.lib.getFQA, getDevice = function(id) return Emu.devices[id] end,
  getDevices = function() return Emu.devices end,
  speedFor = emu.lib.speedFor, offline = emu.offline, refreshState = emu.refreshState,
  hasState = emu.stateTag ~= nil, taskargs = emu.taskArgs, runTest = emu.lib.runTest,
  createSimDevice = emu.lib.createSimDevice, readFile = emu.lib.readFile, writeFile = emu.lib.writeFile,
  SocketServer = SocketServer, config = emu.config,
  plugin = emu.plugin
}
end

function Device:startQA()
  Emu:DEBUGF('device',"Starting QuickApp %s %s",self.device.name,self.id)
  local id = self.id
  
  if #self.files == 0 then return end
  local env = { 
    api = Emu.api, 
    os = { time = Emu.lib.userTime, date = Emu.lib.userDate, exit = os.exit, clock = os.clock, difftime = os.difftime } 
  }
  local struct = self.device
  for _,v in ipairs(stdFuns) do env[v] = _G[v] end
  env.type = function(e) local t = type(e) return t == "table" and e.__USERDATA and "userdata" or t end
  env._G = env
  env._emu = Emu
  self.env = env
  
  loadfile(Emu.lib.filePath("hc3emu2.class"), "t", env)()
  loadfile(Emu.lib.filePath("hc3emu2.fibaro"), "t", env)()
  hc3emuFuns = hc3emuFuns or hc3emuExports(Emu)
  env.fibaro.hc3emu = hc3emuFuns
  env.fibaro._hc3emu = Emu
  loadfile(Emu.lib.filePath("hc3emu2.net"), "t", env)()
  loadfile(Emu.lib.filePath("hc3emu2.quickapp"), "t", env)()
  env.plugin.mainDeviceId = id
  env.__TAG = struct.name..struct.id
  env._PI.dbg = self.headers and self.headers.debug or {}
  local main = nil
  local finished = Emu:createLock(math.huge,true)
  finished:get()
  local function start()
    for _,file in ipairs(self.files) do
      if file.content == nil then
        file.content = Emu.lib.readFile(file.fname)
      end
      if file.name == "main" then main = file
      else
        Emu:DEBUGF('device',"Loading file %s for device %s",file.fname,self.id)
        local code,res = load(file.content, file.fname or file.name, "t", env)
        assert(code, "Error loading file: "..file.fname.." "..tostring(res))
        code()
      end
    end
    assert(main, "No main file found")
    if self.headers.breakOnLoad then
      local firstLine,onInitLine = Emu.lib.findFirstLine(main.content)
      if firstLine then Emu.mobdebug.setbreakpoint(main.fname,firstLine) end
    end
    Emu:DEBUGF('device',"Loading file %s for device %s",main.fname,self.id)
    local code,res = load(main.content, main.fname or main.name, "t", env)
    assert(code, "Error loading main file: "..main.fname.." "..tostring(res)) 
    code()
    Emu:DEBUGF('device',"QuickApp process starting %s",self.id)
    env.quickApp = env.QuickApp(struct)
    Emu:post({type='quickapp_started',id=id})
    finished:destroy()
  end
  env.setTimeout(start,0)
  finished:get()
  if self.headers.save then Emu.lib.saveQA(struct.id) end
  if self.headers.project then Emu.lib.saveProject(self.headers.project,self) end
end

return {}