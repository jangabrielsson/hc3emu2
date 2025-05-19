local VERSION = "1.1.10"

if arg[2] == "develop" then
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
  
  local function mergeLib(lib1,lib2) for k,v in pairs(lib2 or {}) do lib1[k] = v end end
  mergeLib(Emu.lib,require("hc3emu2.log"))
  mergeLib(Emu.lib,require("hc3emu2.utilities"))
  mergeLib(Emu.lib,require("hc3emu2.tools"))
  Emu.lib.ui = require("hc3emu2.ui")
  
  mainFile = arg[1]
  local src = Emu.lib.readFile(mainFile)
  local headers,eval = Emu:getHeaders(src),Emu.lib.eval
  Emu.offline = eval("Header:",headers.offline,'boolean','offline',false)
  Emu.config.dport = eval("Header:",headers.pport,'number','dport',8172)
  Emu.config.pport = eval("Header:",headers.pport,'number','pport',8265)
  Emu.config.wport = eval("Header:",headers.wport,'number','wport',8266)
  Emu.config.hport = eval("Header:",headers.hport,'number','hport',8267)
  Emu.config.hip = eval("Header:",headers.hip,'string','hport','127.0.0.1')
  Emu.config.hc3.url = headers.url or os.getenv("HC3URL")
  Emu.config.hc3.user = headers.user or os.getenv("HC3USER")
  Emu.config.hc3.pwd = headers.pwd or os.getenv("HC3PASSWORD")
  Emu.config.hc3.pin = headers.pin or os.getenv("HC3PIN")
  Emu.stateTag = headers.state
  Emu.config.startTime = headers.startTime
  Emu.config.speedTime = headers.speedTime
  Emu.config.condensedLog = headers.condensedLog
  for _,k in ipairs({"refresh","rawrefresh"}) do Emu.config.dbg[k] = headers.debug[k] end
  
  Emu.api = require("hc3emu2.api")(Emu)
  if Emu.offline then require("hc3emu2.offline")(Emu) 
  else Emu.helper = require("hc3emu2.helper") end
  
  mergeLib(Emu.lib,require("hc3emu2.timers"))
  mergeLib(Emu.lib,require("hc3emu2.proxy"))
  Emu.refreshState = require("hc3emu2.refreshstate")(Emu)
  
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

  function Emu.EVENT.device_created(event,emu) emu:startQA(event.id) end
  
  config.setupRsrscsDir()
  Emu.templates = json.decode(Emu.lib.readRsrcsFile("devices.json"))
  Emu:process{
    pi = Emu.PI,
    fun = function() 
      if Emu.config.startTime then Emu.lib.setTime(Emu.config.startTime) end
      if Emu.config.speedTime then Emu.lib.speedFor(Emu.config.speedTime) end
      Emu.lib.midnightLoop()
      Emu.lib.startScheduler()
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
  self.stats = { ports = {}, timers = {} }
  self.lib = { userTime = os.time, readFile= config.readFile, readRsrcsFile = config.readRsrcsFile, filePath = config.filePath }
  self.qas = { devices = {}, files = {}, envs = {}, vars={} }
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
function headerKeys.logUI(v,h,k) h.logUI = validate(v,k,"boolean") end
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

function Emulator:getHeaders(code)
  local headers = { debug = {}, files = {}, UI={} }
  for key,fun in pairs(headerKeys) do 
    code:gsub("%-%-%%%%"..key.."=([^\n]+)",function(v) fun(v,headers,key) end)
  end
  local UI = {}
  for _,v in ipairs(headers.UI) do UI[#UI+1] = validate(v,"UI","table") end
  headers.UI = UI
  return headers
end

local function stringIndex(keyMap) local r={} for k,v in pairs(keyMap) do r[tostring(k)] = v end return r end
local function intIndex(keyMap) local r,n={},0 for k,v in pairs(keyMap) do r[tonumber(k)] = v n=n+1 end return r,n end

function Emulator:loadState()
  local state = json.decode(self.lib.readFile(".state.db",true) or "{}")
  if state.tag ~= self.stateTag then return end
  local d,f = 0,0
  self.qas.devices,d = intIndex(state.devices or {}) 
  self.qas.files,f = intIndex(state.files or {})
  self.qas.vars,f = intIndex(state.vars or {})
  self:DEBUG("Loaded state, %s device(s) and %s file(s)",d,f)
end

function Emulator:saveState()
  local f = io.open(".state.db", "w")
  if not f then return end
  local state = { 
    tag = self.stateTag, 
    devices = stringIndex(self.qas.devices), 
    files = stringIndex(self.qas.files),
    vars = stringIndex(self.qas.vars) 
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
  --addEmbedUI(flags.type, self.UI)
  return uiCallbacks,viewLayout,uiView
end

local ID = 5000
function Emulator:installDevice(d,headers)
  local isProxy = headers and headers.proxy
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
  device.uiCallbacks,device.viewLayout,device.uiView = self:createUI(headers and headers.UI or {})
  device.isProxy = d.isProxy
  device.isChild = d.isChild or false
  if isProxy then
    device.name = device.name.."_Proxy"
    device = self.lib.createProxy(device)
    device.isProxy = true
    if headers.logUI then Emu.lib.ui.logUI(device.id) end
  elseif d.id then device.id = d.id
  else device.id = ID; ID = ID + 1 end
  device._headers = headers
  self.qas.devices[device.id] = device
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
  if not self.qas.files[id] then return end
  local env = { 
    api = self.api, 
    os = { time = self.lib.userTime, date = self.lib.userDate, exit = os.exit, clock = os.clock() } 
  }
  local dev = self.qas.devices[id]
  for _,v in ipairs(stdFuns) do env[v] = _G[v] end
  env._G = env
  env._emu = self
  self.qas.envs[id] = env

  loadfile(self.lib.filePath("hc3emu2.class"), "t", env)()
  loadfile(self.lib.filePath("hc3emu2.fibaro"), "t", env)()
  env.fibaro.hc3emu = self
  loadfile(self.lib.filePath("hc3emu2.net"), "t", env)()
  loadfile(self.lib.filePath("hc3emu2.quickapp"), "t", env)()
  env.plugin.mainDeviceId = id
  env.__TAG = dev.name..dev.id
  env._PI.dbg = dev._headers and dev._headers.debug or {}
  self:process{
    pi = env._PI,
    fun = function()
      for _,file in ipairs(self.qas.files[id]) do
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
  self.qas.files[device.id] = {{fname = fname, name='main', content = code}}
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
  self.qas.files[device.id] = fqa.files
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
