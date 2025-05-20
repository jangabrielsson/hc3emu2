local VERSION = "1.0.2"

mainFile = arg[1]
if arg[2] == "develop" or _DEVELOP then -- Running in developer mode
  _DEVELOP = true
  package.path = ";src/?;src/?.lua;"..package.path
end

local fmt = string.format

local copas = require("copas")
local mobdebug = require("mobdebug")
local socket = require("socket")
copas.https = require("ssl.https")
local ltn12 = require("ltn12")

-- Figure out where we are and what we run...
local config = require("hc3emu2.config")

local copiMap = setmetatable({}, { __mode = "k" }) -- Weak table for coroutine to process info mapping

local function startUp()
  Emu = Emulator() -- Global
  Emu.config.rsrcsDir = config.rsrcsDir
  Emu.config.EMU_DIR = config.EMU_DIR
  Emu.config.EMUSUB_DIR = config.EMUSUB_DIR
  
  local function mergeLib(lib1,lib2) for k,v in pairs(lib2 or {}) do lib1[k] = v end end
  mergeLib(Emu.lib,require("hc3emu2.log"))
  mergeLib(Emu.lib,require("hc3emu2.utilities"))
  mergeLib(Emu.lib,require("hc3emu2.tools"))
  mergeLib(Emu.lib,require("hc3emu2.embedui"))
  Emu.lib.ui = require("hc3emu2.ui")
  
  mainFile = arg[1]
  local src = Emu.lib.readFile(mainFile)
  local headers,eval = Emu:getHeaders(src),Emu.lib.eval
  Emu.offline = eval("Header:",headers.offline,'boolean','offline',false)
  Emu.config.dport = eval("Header:",headers.pport,'number','dport',8172) -- debugger port
  Emu.config.pport = eval("Header:",headers.pport,'number','pport',8265) -- proxy port
  Emu.config.wport = eval("Header:",headers.wport,'number','wport',8266) -- web port
  Emu.config.hport = eval("Header:",headers.hport,'number','hport',8267) -- helper port
  Emu.config.hip = eval("Header:",headers.hip,'string','hport','127.0.0.1')
  Emu.config.hc3.url = headers.url or os.getenv("HC3URL")
  Emu.config.hc3.user = headers.user or os.getenv("HC3USER")
  Emu.config.hc3.pwd = headers.pwd or os.getenv("HC3PASSWORD")
  Emu.config.hc3.pin = headers.pin or os.getenv("HC3PIN")
  Emu.stateTag = headers.state
  Emu.config.startTime = headers.startTime
  Emu.config.speedTime = headers.speedTime
  Emu.config.condensedLog = headers.condensedLog
  -- copy over some debugflags to be overall emulator debug flags
  for _,k in ipairs({"refresh","rawrefresh"}) do Emu.config.dbg[k] = headers.debug[k] end
  Emu.config = table.merge(config.userConfig,Emu.config) -- merge in user config  from .hc3emu.lua
  
  Emu.api = require("hc3emu2.api")(Emu)
  if Emu.offline then require("hc3emu2.offline")(Emu) 
  else Emu.helper = require("hc3emu2.helper") end
  
  mergeLib(Emu.lib,require("hc3emu2.timers"))
  mergeLib(Emu.lib,require("hc3emu2.proxy"))
  Emu.refreshState = require("hc3emu2.refreshstate")(Emu)
  Emu.web = require("hc3emu2.webserver")
  
  Emu.lib.setDark(true)
  if Emu.stateTag then Emu:loadState() end
  
  Emu.config.ipAddress = config.ipAddress
  Emu.config.pip = config.ipAddress -- Proxy server IP (used by HC3 to find emulator)
  Emu.config.pip2 = os.getenv("HC3EMUHOST") or Emu.config.pip -- Running in container, we may have different ip...
  
  Emu.mobdebug = { on = function() end, start = function(_,_) end, setbreakpoint = function() end }
  if not Emu.nodebug then
    if config.debuggerType == "actboy168" then
      -- functions?
    elseif config.debuggerType == "mobdebug" or true then
      Emu.mobdebug = require("mobdebug") or Emu.mobdebug
      Emu.mobdebug.start('localhost',Emu.config.dport or 8172) 
    end
  end
  mobdebug = Emu.mobdebug
  
  -- qa = { watches = {}, updateView(elm, prop, val), device = ..., }
  local function initializeUI(QA,UI,index)
    if type(UI) ~= 'table' then return end
    local typ = Emu.lib.ui.getElmType(UI)
    if not typ then for _,r in ipairs(UI) do initializeUI(QA,r,index) end return end
    UI.type = typ
    local componentName = UI[typ]
    if index[componentName] then
      Emu:DEBUGF('warn',"Duplicate UI element %s in %s",componentName,QA.name)
    end
    index[componentName] = UI
    if componentName then -- Also primes the UI element with default values, in paricular from embedded UI elements
      local sval = Emu.lib.embedProps[componentName] and Emu.lib.embedProps[componentName](QA) or nil
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
  
  function Emu:setupUIstruct(qa)
    local embed = self.lib.embedUIs[qa.device.type] -- Add embed/stock UI elements for device type
    for i,r in ipairs(embed or {}) do table.insert(qa.ui.UI,i,r) end
    
    if qa.device.isChild then -- Decide html page name for QA
      local name = (qa.device.name or "Child"):gsub("[^%w]","")
      qa.ui.pageName = fmt("%s_%s.html",name,qa.id)
    else
      local name = qa.device.name:gsub("[^%w]","")
      qa.ui.pageName = fmt("%s.html",name)
    end
    local index = {}
    local QA = { watches = qa.ui.watches, updateView = qa.ui.updateView, device = qa.device }
    initializeUI(QA,qa.ui.UI,index) -- Prime the UI struct to serve as value holder for the page renderer
    setmetatable(qa.ui.UI,{
      __index=function(t,k) if index[k] then return index[k] else return rawget(t,k) end end,
    })
  end
  
  function Emu.EVENT.device_created(event,emu)
    local qa = emu.qas[event.id]
    if qa.headers.webUI then -- setup for generating web page
      Emu:setupUIstruct(qa)
      Emu.web.generateUIpage(qa.device.id,qa.device.name,qa.ui.pageName,qa.ui.UI)
    end
    emu:startQA(event.id) 
  end
  
  config.setupRsrscsDir()
  Emu.templates = json.decode(Emu.lib.readRsrcsFile("devices.json"))
  Emu:process{
    pi = Emu.PI,
    fun = function() 
      if Emu.config.startTime then Emu.lib.setTime(Emu.config.startTime) end
      if Emu.config.speedTime then Emu.lib.speedFor(Emu.config.speedTime) end
      Emu.lib.midnightLoop()
      Emu.lib.startScheduler()
      Emu.web.startServer()
      Emu.web.generateEmuPage()
      Emu:installQuickAppCode(mainFile,src,headers) 
    end
  }
  Emu:start()
end

local extraLua =  {
  os = os, require = require, dofile = dofile, loadfile = loadfile, 
  type = type, io = io, print = _print, package = package, coroutine = coroutine,
  rawset = rawset, rawget = rawget
}

require("hc3emu2.class")

Emulator = Emulator
class 'Emulator'
function Emulator:__init()
  self.config = { hc3 = {}, dbg = {}, emu = {} }
  self.stats = { ports = {}, timers = {}, qas = {} }
  self.lib = { userTime = os.time, readFile= config.readFile, readRsrcsFile = config.readRsrcsFile, filePath = config.filePath }
  self.qas = {} -- []{ device = {}, files = {}, env = {}, vars = {}, ui = {} }
  self.EVENT = {}
  self.stateTag = nil
  self.lua = extraLua
  setmetatable(self.EVENT, { __newindex = function(t,k,v) rawset(t,k, t[k] or {}) table.insert(t[k],v) end })
  self.PI = {}
  function self.PI.debugHandler(flag,...) 
    if flag==true or self.config.dbg[flag] then self:debugOutput("EMU",fmt(self.lib.formatArgs(...)),"DEBUG") end
  end
  function self.PI.errorHandler(err,tb) self:debugOutput("EMU",err,"ERROR") if tb then print(tb) end end
  function self.PI.name() return "Hc3Emu" end
end

function Emulator:DEBUG(...) self:DEBUGF(true,...) end
function Emulator:DEBUGF(flag,...) 
  local pi = copiMap[coroutine.running()] or self.PI pi.debugHandler(flag,...) 
end
function Emulator:ERRORF(...) local pi = copiMap[coroutine.running()] pi.errorHandler(...) end

function Emulator:httpRequest(method,url,headers,data,timeout,user,pwd,silent)
  local resp, req = {}, {}
  req.url = url
  req.method = method or "GET"
  req.headers = headers or {}
  req.timeout = timeout and timeout / 1000
  req.sink = ltn12.sink.table(resp)
  req.headers["Accept"] = req.headers["Accept"] or "*/*"
  req.headers["Content-Type"] = req.headers["Content-Type"] or "application/json"
  req.user = user
  req.password = pwd
  if method == "PUT" or method == "POST" then
    data = data== nil and "[]" or data
    req.headers["Content-Length"] = #data
    req.source = ltn12.source.string(data)
  else
    req.headers["Content-Length"] = 0
  end
  local r,status,h
  local t0 = socket.gettime()
  if url:starts("https") then
    req.ssl_verify = false
    r,status,h = copas.https.request(req)
  else r,status,h = copas.http.request(req) end
  local t1 = socket.gettime()
  --if not silent then self:DEBUGF('http',"HTTP %s %s %s (%.3fs)",method,url,status,t1-t0) end
  if tonumber(status) and status < 300 then
    return resp[1] and table.concat(resp) or nil, status, h
  else
    return nil, status, h, resp
  end
end

local BLOCK = false 
function Emulator:HC3Call(method,path,data,silent)
  if BLOCK then self:ERRORF("HC3 authentication failed again, Emu access turned off") return nil, 401, "Blocked" end
  if type(data) == 'table' then data = json.encode(data) end
  local creds = self.config.hc3
  assert(creds.url,"Missing hc3emu.URL - Please set url to HC3")
  assert(creds.user,"Missing hc3emu.USER - Please set user for HC3")
  assert(creds.pwd,"Missing hc3emu.PASSWORD - Please set password for HC3")
  local res,stat,headers = self:httpRequest(method,creds.url.."api"..path,{
    ["Accept"] = '*/*',
    ["X-Fibaro-Version"] = 2,
    ["Fibaro-User-PIN"] = self.PIN,
  },
  data,35000,creds.user,creds.pwd,silent)
  if stat == 401 then self:ERRORF("HC3 authentication failed, Emu access cancelled") BLOCKED = true end
  if stat == 'closed' then self:ERRORF("HC3 connection closed %s",path) end
  if stat == 500 then self:ERRORF("HC3 error 500 %s",path) end
  if not tonumber(stat) then return res,stat end
  if stat and stat >= 400 then return nil,stat end
  local jf,data = pcall(json.decode,res)
  return (jf and data or res),stat
end

local compMap = {
  text = function(v) return v end, 
  value = function(v) if type(v)=='table' then return v[1] else return v end end,
  options = function(v) return v end,
  selectedItem = function(v) return v end,
  selectedItems = function(v) return v end
}

function Emulator:registerDevice(args)
  local dflt = { device = {}, files = {}, env = {}, vars = {}, ui = { UI={}, watches={} } }
  local qa = self.qas[args.id] or dflt
  self.qas[args.id] = qa
  qa.ui = qa.ui or { UI={}, watches={} }
  qa.device = args.device or qa.device
  qa.files =  args.files or qa.files
  qa.vars = args.vars or qa.vars
  qa.ui.UI = args.UI or qa.ui.UI
  qa.headers = args.headers or qa.headers
  qa.env = args.env or qa.env
  function qa.ui.watching(prop,value) 
    print("WATCH",args.id,prop)
    if qa.ui.watches[prop] then qa.ui.watches[prop](value) end
  end
  function qa.ui.updateView(componentName,propertyName,value) 
    print("UPDATEVIEW",args.id,componentName,propertyName,value)
    local UI = qa.ui.UI
    local elm = UI[componentName]
    if not elm then return end
    if compMap[propertyName] then value = compMap[propertyName](value) end
    if value ~= elm[propertyName] then 
      elm[propertyName] = value 
      Emu:post({type='quickApp_updateView',id=args.id})
    end
  end
  return qa
end

local function validate(v,k,typ)
  return Emu.lib.eval("Header:",v,k,typ)
end

local headerKeys = {}
function headerKeys.type(v,h) h.type = v end 
function headerKeys.name(v,h) h.name = v end
function headerKeys.proxy(v,h,k) h.proxy = validate(v,k,"boolean") end
function headerKeys.proxy_new(v,h,k) h.proxy_new = validate(v,k,"boolean") end
function headerKeys.proxy_set_ui(v,h,k) h.proxy_set_ui = validate(v,k,"boolean") end
function headerKeys.state(v,h) h.state = v end
function headerKeys.time(v,h,k) h.startTime = v end
function headerKeys.speed(v,h,k) h.speedTime = validate(v,k,"number") end
function headerKeys.offline(v,h,k) h.offline = validate(v,k,"boolean") end
function headerKeys.logui(v,h,k) h.logUI = validate(v,k,"boolean") end
function headerKeys.webui(v,h,k) h.webUI = validate(v,k,"boolean") end
function headerKeys.condensedLog(v,h,k) h.condensedLog = validate(v,k,"boolean") end
function headerKeys.pport(v,h,k) h.pport = validate(v,k,"number") end
function headerKeys.wport(v,h,k) h.wport = validate(v,k,"number") end
function headerKeys.hport(v,h,k) h.hport = validate(v,k,"number") end
function headerKeys.url(v,h) h.url = v end
function headerKeys.user(v,h) h.user = v end
function headerKeys.pwd(v,h) h.pwd = v end
function headerKeys.pin(v,h) h.pin = v end
function headerKeys.u(v,h) h.UI[#h.UI+1] = v end
function headerKeys.debug(v,h)
  local flags = v:split(",")
  for _,flagv in ipairs(flags) do 
    local flag,val = flagv:match("(.*):(.*)")
    h.debug[flag] = Emu.lib.eval("Header:",val,flag)
  end
end
function headerKeys.file(v,h)
  local files = v:split(",")
  for _,filev in ipairs(files) do 
    local path,name = filev:match("(.*):(.*)")
    h.files[name] = path
  end
end
function headerKeys.var(v,h)
  local name,value = v:match("(.-):(.*)")
  -- eval(prefix,str,expr,typ,dflt,env)
  value = Emu.lib.eval("Header:",value,name,nil,nil,{config=config.userConfig})
  h.vars[#h.vars+1] = { name = name, value = value }
end

function Emulator:getHeaders(code)
  local headers = { debug = {}, files = {}, UI={}, vars = {} }
  for key,fun in pairs(headerKeys) do 
    code:gsub("%-%-%%%%"..key.."=([^\n]+)",function(v) fun(v,headers,key) end)
  end
  local UI = {}
  for _,v in ipairs(headers.UI) do UI[#UI+1] = validate(v,"UI","table") end
  headers.UI = UI
  return headers
end

local function stringIndex(keyMap) 
  local r={}  
  for k,v in pairs(keyMap) do r[tostring(k)] = {device=v.device, files=v.files, vars=v.vars } end  
  return r 
end

local function intIndex(keyMap,r)   
  local n=0   
  for k,v in pairs(keyMap) do r[tonumber(k)] = v n=n+1 end  
  return r,n   
end

function Emulator:loadState()
  local state = json.decode(self.lib.readFile(".state.db",true) or "{}")
  if state.tag ~= self.stateTag then return end
  local d = 0
  for k,_ in pairs(self.qas) do self.qas[k] = nil end
  self.qas,d = intIndex(state.qas or {},self.qas)
  self:DEBUG("Loaded state, %s device(s)",d)
end

function Emulator:saveState()
  local f = io.open(".state.db", "w")
  if not f then return end
  local state = { 
    tag = self.stateTag,
    qas = stringIndex(self.qas or {}),
  }
  f:write(json.encode(state))
  f:close()
end

function Emulator:createUI(UI) -- Move to ui.lua ? 
  local uiCallbacks,viewLayout,uiView
  if UI and #UI > 0 then
    uiCallbacks,viewLayout,uiView = self.lib.ui.compileUI(UI)
  else
    viewLayout = json.decode([[{
        "$jason": {
          "body": {
            "header": {
              "style": { "height": "0" },
              "title": "quickApp_device_57"
            },
            "sections": { "items": [] }
          },
          "head": { "title": "quickApp_device_57" }
        }
      }
  ]])
    viewLayout['$jason']['body']['sections']['items'] = json.util.InitArray({})
    uiView = json.util.InitArray({})
    uiCallbacks = json.util.InitArray({})
  end
  return uiCallbacks,viewLayout,uiView
end

local ID = 5000
function Emulator:installDevice(d,headers)
  headers = headers or {}
  local isProxy = headers.proxy
  if isProxy then                                  -- Existing proxy device?
    local device = self.lib.existingProxy(d,headers)
    if device then 
      if headers.logUI then Emu.lib.ui.logUI(device.id) end
      return device 
    end
  end
  -- Create new device
  local templ = self.templates[d.type]
  assert(templ, "Unknown device type: " .. d.type)
  local device = table.copy(templ)
  device.name = d.name or device.name
  device.type = d.type
  device.roomID = d.roomID or device.roomID
  device.parentId = d.parentId or 0
  device.properties = d.initialProperties or device.properties
  device.interfaces = d.initialInterfaces or device.interfaces
  device.properties.uiCallbacks,device.properties.viewLayout,device.properties.uiView 
  = self:createUI(headers.UI or {})
  device.isProxy = d.isProxy
  device.isChild = d.isChild or false
  if isProxy then
    device.name = device.name.."_Proxy"
    device = self.lib.createProxy(device)
    device.isProxy = true
    if headers.logUI then Emu.lib.ui.logUI(device.id) end
  elseif d.id then device.id = d.id
  else device.id = ID; ID = ID + 1 end
  Emu:registerDevice{
    id=device.id,
    device=device,
    headers=headers or {},
    UI=headers.UI
  }
  self:saveState()
  self:post({type='device_created',id=device.id})
  return device
end


local stdFuns = { 
  'setmetatable', 'getmetatable', 'assert', 'rawget', 'rawset', 'pairs', 
  'print', 'ipairs', 'type', 'tostring', 'tonumber', 'string', 'table', 
  'math', 'pcall', 'xpcall', "error", "json", "select", "collect_garbage"
}

function Emulator:startQA(id)
  local qa = self.qas[id]
  if #qa.files == 0 then return end
  local env = { 
    api = self.api, 
    os = { time = self.lib.userTime, date = self.lib.userDate, exit = os.exit, clock = os.clock() } 
  }
  local dev = qa.device
  for _,v in ipairs(stdFuns) do env[v] = _G[v] end
  env._G = env
  env._emu = self
  qa.env = env
  
  loadfile(self.lib.filePath("hc3emu2.class"), "t", env)()
  loadfile(self.lib.filePath("hc3emu2.fibaro"), "t", env)()
  env.fibaro.hc3emu = self
  loadfile(self.lib.filePath("hc3emu2.net"), "t", env)()
  loadfile(self.lib.filePath("hc3emu2.quickapp"), "t", env)()
  env.plugin.mainDeviceId = id
  env.__TAG = dev.name..dev.id
  env._PI.dbg = qa.headers and qa.headers.debug or {}
  self:process{
    pi = env._PI,
    fun = function()
      for _,file in ipairs(qa.files) do
        if file.content == nil then
          file.content = self.lib.readFile(file.fname)
        end
        load(file.content, file.fname or file.name, "t", env)()
      end
      env.quickApp = env.QuickApp(dev)
    end
  }
end

function Emulator:installQuickAppCode(fname,code,headers)
  local headers = headers or self:getHeaders(code)
  local device = {
    name = headers.name or "MyQA",
    type = headers.type or "com.fibaro.binarySwitch",
  }
  device = self:installDevice(device,headers)
  table.insert(self.qas[device.id].files,{fname = fname, name='main', content = code})
  self:saveState()
  return device
end

function Emulator:installQuickAppFile(fname)
  local code = self.lib.readFile(fname)
  return self:installQuickAppCode(fname, code)
end

function Emulator:installFQA(fqa)
  local headers = self:getHeaders("") -- self:getHeaders(main)
  local device = {
    name = fqa.name,
    type = fqa.type,
  }
  device = self:installDevice(device,headers)
  self.qas[device.id].files = fqa.files or {}
  self:saveState()
  return device
end

function Emulator:debugOutput(tag, msg, typ, time) 
  self.lib.debugOutput(tag, msg, typ, time or self.lib.userTime())
end

function Emulator:handleEvent(event)
  for _,f in ipairs(self.EVENT[event.type] or {}) do
    f(event,self)
  end
end

local function pruneTB(tb)
  if tb == nil then return "<unknown error, tb==nil>" end
  tb = tb:match("^.-'copas%.gettraceback'\n(.*)$") or tb
  tb = tb:match("%s+.-[/\\]hc3emu[/\\]util.lua:%d+:.-\n(.*)$") or tb
  return tb
end

local function wrapFun(fun,pi,typ)
  return function(...)
    pi = pi or Emu.PI
    copiMap[coroutine.running()] = pi
    mobdebug.on()
    copas.setthreadname(pi and pi.name() or "EmuThread")
    copas.seterrorhandler(function(msg,co,skt)
      local tb = pruneTB(copas.gettraceback(typ or "Emulator",co,skt))
      if pi then pi.errorHandler(msg,tb)
      else print("Error: ", msg) print(tb) end
      os.exit() -- stop on error
      --copas.removethread(co)
    end)
    return fun(...)
  end
end
Emulator.wrapFun = wrapFun

function Emulator:post(event) 
  return self:setTimeout(function() self:handleEvent(event) end, 0) 
end
function Emulator:process(args) 
  return copas.addthread(wrapFun(args.fun,args.pi,args.typ),table.unpack(args.args or {})) 
end
function Emulator:start() copas() end

startUp()
