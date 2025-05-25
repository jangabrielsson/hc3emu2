local VERSION = "1.1.2"

local mode, mainFile
local startupMode = { run=true, develop=true, test=true }
for i=0,4 do
  if startupMode[arg[i]] then mode = arg[i] mainFile = arg[i+1] break end
end

assert(mode,"Missing mode command line argument")
assert(mainFile,"Missing file command line argument")
if mode == "develop" or _DEVELOP then -- Running in developer mode
  print("Developer mode")
  _DEVELOP = true
  package.path = ";src/?;src/?.lua;"..package.path
end

local fmt = string.format

local copas = require("copas")
local mobdebug = require("mobdebug")
local socket = require("socket")
copas.https = require("ssl.https")
local ltn12 = require("ltn12")
local lfs = require("lfs")
require("copas.http")

-- Figure out where we are and what we run...
local config = require("hc3emu2.config")

local copiMap = setmetatable({}, { __mode = "k" }) -- Weak table for coroutine to process info mapping

local function startUp()
  Emu = Emulator() -- Global
  Emu.config.rsrcsDir = config.rsrcsDir
  Emu.config.tempDir = config.tempDir
  Emu.config.EMU_DIR = config.EMU_DIR
  Emu.config.EMUSUB_DIR = config.EMUSUB_DIR
  
  local function mergeLib(lib1,lib2) for k,v in pairs(lib2 or {}) do lib1[k] = v end end
  mergeLib(Emu.lib,require("hc3emu2.log"))
  mergeLib(Emu.lib,require("hc3emu2.utilities"))
  mergeLib(Emu.lib,require("hc3emu2.tools"))
  mergeLib(Emu.lib,require("hc3emu2.unittest"))
  mergeLib(Emu.lib,require("hc3emu2.device"))
  Emu.lib.ui = require("hc3emu2.ui")
  
  local src = Emu.lib.readFile(mainFile)
  local headers,eval = Emu:getHeaders(src),Emu.lib.eval
  Emu.offline = headers.offline
  Emu.config.hc3.url = headers.url or os.getenv("HC3URL") or config.userConfig.url
  Emu.config.hc3.user = headers.user or os.getenv("HC3USER") or config.userConfig.user
  Emu.config.hc3.pwd = headers.pwd or os.getenv("HC3PASSWORD") or config.userConfig.password
  Emu.config.hc3.pin = headers.pin or os.getenv("HC3PIN") or config.userConfig.pin
  Emu.config.pport = headers.pport or 8265  -- debugger port
  Emu.config.wport = headers.wport or 8266  -- debugger port
  Emu.config.hport = headers.hport or 8267  -- debugger port
  Emu.config.dport = headers.dport or 8172  -- debugger port
  Emu.config.hip = headers.hip or "127.0.0.1"  -- help ip
  Emu.stateTag = headers.state
  Emu.nodir = headers.nodir
  local globalHeaders = {
    "latitude","longitude","startTime","speedTime","condensedLog",
  }
    for _,v in ipairs(globalHeaders) do Emu.config[v] = headers[v] end
  -- copy over some debugflags to be overall emulator debug flags
  for _,k in ipairs({"refresh","rawrefresh","system","http","notrace"}) do Emu.config.dbg[k] = headers.debug[k] end
  Emu.config = table.merge(config.userConfig,Emu.config) -- merge in user config  from .hc3emu.lua
  
  if Emu.config.hc3.url:sub(-1) ~= "/" then Emu.config.hc3.url = Emu.config.hc3.url.."/" end
  
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
  
  Emu.mobdebug = { on = function() end, start = function(_,_) end, setbreakpoint = function(_,_) end }
  if not Emu.nodebug then
    if config.debuggerType == "actboy168" then
      -- functions?
    elseif config.debuggerType == "mobdebug" or true then
      Emu.mobdebug = require("mobdebug") or Emu.mobdebug
      Emu.mobdebug.start('localhost',Emu.config.dport or 8172) 
    end
  end
  mobdebug = Emu.mobdebug 
  
  if not Emu.nodir then config.setupRsrscsDir() end
  if headers.installation then 
    config.installation(headers.installation,Emu.config.hc3) 
  end
  Emu.templates = json.decode(Emu.lib.readRsrcsFile("devices.json"))
  Emu:process{
    pi = Emu.PI,
    fun = function() 
      if Emu.config.startTime then Emu.lib.setTime(Emu.config.startTime) end
      if Emu.config.speedTime then Emu.lib.speedFor(Emu.config.speedTime) end
      Emu.sunriseHour,Emu.sunsetHour = Emu.lib.sunCalc()
      Emu.lib.midnightLoop()
      Emu.lib.startScheduler()
      Emu.web.startServer()
      Emu.web.generateEmuPage()
      Emu:installQuickAppCode(mainFile,src,headers) 
    end
  }

  function Emu.EVENT.midnight()
    local count = Emu.lib.masterGate:get_count()
    if count > 0 then Emu.lib.masterGate:take() end
    Emu.sunriseHour,Emu.sunsetHour = Emu.lib.sunCalc() 
    if count > 0 then Emu.lib.masterGate:give() end
  end

  Emu:start()
end

local extraLua =  {
  os = os, require = require, dofile = dofile, loadfile = loadfile, 
  type = type, io = io, print = _print, package = package, coroutine = coroutine,
  rawset = rawset, rawget = rawget, debug = debug
}

require("hc3emu2.class")

Emulator = Emulator
class 'Emulator'
function Emulator:__init()
  self.config = { hc3 = {}, dbg = {}, emu = {} }
  self.stats = { ports = {}, timers = {}, qas = {} }
  self.lib = { userTime = os.time, readFile= config.readFile, readRsrcsFile = config.readRsrcsFile, filePath = config.filePath }
  self.devices = {} -- []{ device = {}, files = {}, env = {}, vars = {}, ui = {} }
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
  if not silent then self:DEBUGF('http',"HTTP %s %s %s (%.3fs)",method,url,status,t1-t0) end
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
  if stat == 'closed' then self:ERRORF("HC3 connection closed "..path) end
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
do
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
  function headerKeys.uid(v,h,k) h.uid = validate(v,k,"string") end
  function headerKeys.manufacturer(v,h,k) h.manufacturer = validate(v,k,"string") end
  function headerKeys.model(v,h,k) h.model = validate(v,k,"string") end
  function headerKeys.role(v,h,k) h.role = validate(v,k,"string") end
  function headerKeys.description(v,h,k) h.description = validate(v,k,"string") end
  function headerKeys.latitude(v,h,k) h.latitude = validate(v,k,"number") end
  function headerKeys.longitude(v,h,k) h.longitude = validate(v,k,"number") end
  function headerKeys.temp(v,h,k) h.temp = validate(v,k,"string") end
  function headerKeys.nodebug(v,h,k) h.nodebug = validate(v,k,"boolean") end
  function headerKeys.silent(v,h,k) h.silent = validate(v,k,"boolean") end
  function headerKeys.breakOnLoad(v,h,k) h.breakOnLoad = validate(v,k,"boolean") end
  function headerKeys.breakOnInit(v,h,k) h.breakOnInit = validate(v,k,"boolean") end
  function headerKeys.save(v,h,k) h.save = v end
  function headerKeys.nodir(v,h,k) h.nodir = validate(v,k,"boolean") end
  function headerKeys.conceal(v,h,k) h.conceal = validate(v,k,"boolean") end
  function headerKeys.condensedLog(v,h,k) h.condensedLog = validate(v,k,"boolean") end
  function headerKeys.pport(v,h,k) h.pport = validate(v,k,"number") end 
  function headerKeys.wport(v,h,k) h.wport = validate(v,k,"number") end 
  function headerKeys.hport(v,h,k) h.hport = validate(v,k,"number") end
  function headerKeys.dport(v,h,k) h.hport = validate(v,k,"number") end 
  function headerKeys.hip(v,h,k) h.hip = validate(v,k,nil) end 
  function headerKeys.url(v,h) h.url = v end
  function headerKeys.user(v,h) h.user = v end
  function headerKeys.pwd(v,h) h.pwd = v end
  function headerKeys.pin(v,h) h.pin = v end
  function headerKeys.u(v,h) h._UI[#h.UI+1] = v end
  function headerKeys.breakOnLoad(v,h,k) h.breakOnLoad = validate(v,k,"boolean") end
  function headerKeys.debug(v,h)
    local flags = v:split(",")
    for _,flagv in ipairs(flags) do 
      local flag,val = flagv:match("(.*):(.*)")
      h.debug[flag] = Emu.lib.eval("Header:",val,flag)
    end
  end
  function headerKeys.file(v,h)
    local function addFile(val) 
      local path,m = val:match("(.-),(.-);?%s*$")
      if not path then path,m = val:match("(.-):(.+);?%s*$") end
      assert(path and m,"Bad file directive: "..val)
      if path:match("%$") then 
        local lib = path:sub(2)
        path = package.searchpath(lib,package.path)
        assert(path,"File library not found: "..lib)
      end
      assert(lfs.attributes(path),"File not found: "..path)
      h.files[m] = path
    end
    addFile(v)
  end
  function headerKeys.var(v,h)
    local name,value = v:match("(.-):(.*)")
    -- eval(prefix,str,expr,typ,dflt,env)
    value = Emu.lib.eval("Header:",value,name,nil,nil,{config=config.userConfig})
    h.vars[#h.vars+1] = { name = name, value = value }
  end
  function headerKeys.install(v,h)
    local user,pass,url = v:match("([^,]+),([^,]+),(.+)")
    h.installation = {user=user,pass=pass,url=url}
  end
end

function Emulator:getHeaders(src,extraHeaders)
  local headers = { debug = {}, files = {}, _UI={}, vars = {} }
  local code = src
  local eod = src:find("%-%-ENDOFHEADERS") -- Embedded headers
  if eod then code = src:sub(1,eod-1) end
  if code:sub(1) ~= "\n" then code = "\n"..code end

  code:gsub("\n%-%-%%%%([%w_]-)=([^\n]*)",function(key,str) 
    str = str:match("^%s*(.-)%s*$") or str
    str = str:match("^(.*)%s* %-%- (.*)$") or str
    if headerKeys[key] then
      headerKeys[key](str,headers,key)
    else print(fmt("Unknown header key: '%s' - ignoring",key)) end
   end)
  for key,value in pairs(extraHeaders or {}) do
    if headerKeys[key] then
      headerKeys[key](value,headers,key)
    else print(fmt("Unknown extra header key: '%s' - ignoring",key)) end
  end
  local UI = (extraHeaders or {}).UI or {}
  for _,v in ipairs(headers._UI) do UI[#UI+1] = validate(v,"UI","table") end
  local files = {}
  for name,path in pairs(headers.files) do files[#files+1] = { name=name, fname=path, isMain=false, isOpen=false, type="lua" } end
  headers.files = files
  headers.UI = UI
  return headers
end

function Emulator:loadState()
  local state = json.decode(self.lib.readFile("./.state.db",true) or "{}")
  if state.tag ~= self.stateTag then return end
  local d = 0
  for k,_ in pairs(self.devices) do self.devices[k] = nil end
  for _,devArgs in pairs(state.devices) do d=d+1 self.devices[devArgs.id] = Device(devArgs) end
  self:DEBUG("Loaded state, %s device(s)",d)
end

function Emulator:saveState()
  local f = io.open("./.state.db", "w")
  if not f then return end
  local devices = {}
  for _,dev in pairs(self.devices) do devices[#devices+1] = dev:toArgs() end
  local state = { 
    tag = self.stateTag,
    devices = devices,
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
function Emulator:installDevice(d,files,headers) -- Move to device?
  Emu:DEBUGF('system',"Installing device %s %s",d.type,d.name or "unnamed")

  headers = headers or {}
  files = files or {}
  for _,f in ipairs(headers.files or {}) do files[#files+1] = f end

  if headers.proxy and self.offline then
    headers.proxy = false -- No proxies in offline mode
    Emu:DEBUG("Proxy devices not supported in offline mode -ignored")
  end

  local isProxy = headers.proxy
  if isProxy then                                  -- Existing proxy device?
    local dev = self.lib.existingProxy(d,headers)
    if dev then 
      if headers.logUI then
        self.lib.ui.logUI(dev.id)
      end
      dev.files = files
      self.devices[dev.id] = dev
      dev:startQA()
      return dev.device
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
  device.properties.quickAppVariables = headers.vars or {}
  local specProps = {
    uid='quickAppUuid',manufacturer='manufacturer',
    mode='model',role='deviceRole',
    description='userDescription'
  }
  for _,prop in ipairs(specProps) do
    if headers[prop] then device.properties[prop] = headers[prop] end
  end
  device.isProxy = d.isProxy
  device.isChild = d.isChild or false
  if isProxy then
    device.name = device.name.."_Proxy"
    device = self.lib.createProxy(device)
    device.isProxy = true
    if headers.logUI then Emu.lib.ui.logUI(device.id) end
  elseif d.id then device.id = d.id
  else device.id = ID; ID = ID + 1 end
  local dev = Device{
    id=device.id,
    device=device,
    files = files,
    headers=headers or {},
    UI=headers.UI
  }
  self:saveState()
  self.devices[device.id] = dev
  self.refreshState:addEvent({type='DeviceCreatedEvent',data={id=device.id}})
  dev:startQA()
  Emu:DEBUGF('system',"Installing device done %s",dev.id)
  return dev.device
end

function Emulator:installQuickAppCode(fname,code,headers,optionalHeaders)
  local headers = headers or self:getHeaders(code,optionalHeaders)
  local device = {
    name = headers.name or "MyQA",
    type = headers.type or "com.fibaro.binarySwitch",
  }
  device = self:installDevice(device,{{fname = fname, name='main', content = code}},headers)
  self:saveState()
  return device,self.devices[device.id]
end

function Emulator:installQuickAppFile(fname,optionalHeaders)
  local code = self.lib.readFile(fname)
  return self:installQuickAppCode(fname, code, nil, optionalHeaders)
end

function Emulator:installFQA(fqa)
  local headers = self:getHeaders("") -- self:getHeaders(main)
  local device = {
    name = fqa.name,
    type = fqa.type,
  }
  struct,dev = self:installDevice(device,fqa.files or {},headers)
  self:saveState()
  return struct,dev
end

function Emulator:debugOutput(tag, msg, typ, time) 
  self.lib.debugOutput(tag, msg, typ, time or self.lib.userTime())
end

function Emulator:post(event) 
  return self:setTimeout(function() self:handleEvent(event) end, 0) 
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
      if pi then pi.errorHandler(Emu:createErrorMsg{msg=msg,trace=tb})
      else print("Error: ", tostring(msg)) print(tb) end
      os.exit() -- stop on error
      --copas.removethread(co)
    end)
    return fun(...)
  end
end
Emulator.wrapFun = wrapFun -- export

function Emulator:createLock(timeout,reentrant) return copas.lock.new(timeout or math.huge,reentrant) end
function Emulator:createErrorMsg(args)
  if type(args.msg) == 'table' then return args.msg end
  return setmetatable({err=args.msg,trace=args.trace or self.lua.debug.traceback(2)},{
    __tostring = function(_)
      local err = args.msg
      if not Emu.config.dbg.notrace then
        err = err .. "\n" .. (args.trace or self.lua.debug.traceback(2))
      end
      return err 
    end,
  })
end

function Emulator:process(args) 
  return copas.addthread(wrapFun(args.fun,args.pi,args.typ),table.unpack(args.args or {})) 
end

function Emulator:sleep(s) copas.sleep(s) end

function Emulator:start() copas() end

startUp()
