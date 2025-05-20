_emu = _emu
_print = print

local fmt = string.format
function print(...) fibaro.debug(__TAG,...) end

function class(name)
  local cls = setmetatable({__USERDATA=true}, {
    __call = function(t,...)
      assert(rawget(t,'__init'),"No constructor")
      local obj = {__USERDATA=true}
      setmetatable(obj,{__index=t, __tostring = t.__tostring or function() return "object "..name end})
      obj:__init(...)
      return obj
    end,
    __tostring = function() return "class "..name end,
  })
  cls.__org = cls
  _G[name] = cls
  return function(p) getmetatable(cls).__index = p end
end

_PI = { timers = {}, env = _G, dbg={} } -- Process info to keep track of
function _PI.cancelTimers() -- Cancel all timer started by QA (for restarts)
  for ref,_ in pairs(_PI.timers) do print("Cancelling",tostring(ref)) _emu:clearTimeout(ref) end
  _PI.timers = {}
end
function _PI.addTimer(ref) _PI.timers[ref] = true return ref end
function _PI.cancelTimer(ref) _PI.timers[ref] = nil return ref end
function _PI.errorHandler(err,traceback)
  fibaro.error(__TAG,err)
  if traceback then _print(traceback) end
end
function _PI.debugHandler(flag,...) if flag==true or _PI.dbg[flag] then fibaro.debug(__TAG,_emu.lib.formatArg(...)) end end
function _PI.name() return __TAG end

plugin = plugin or {}
function plugin.getDevice(deviceId) return api.get("/devices/"..deviceId) end
function plugin.deleteDevice(deviceId) return api.delete("/devices/"..deviceId) end
function plugin.getProperty(deviceId, propertyName) return api.get("/devices/"..deviceId).properties[propertyName] end
function plugin.getChildDevices(deviceId) return api.get("/devices?parentId="..deviceId) end
function plugin.createChildDevice(opts) return api.post("/plugins/createChildDevice", opts) end
function plugin.restart(id) return api.post("/plugins/restart",{deviceId=id or plugin.mainDeviceId}) end

function setInterval(fun,delay) return _PI.addTimer(_emu:setInterval(fun,delay,_PI)) end
function setTimeout(fun,delay) 
  local ref
  local function cb() _PI.cancelTimer(ref) fun() end
  ref = _PI.addTimer(_emu:setTimeout(cb,delay,_PI))
  return ref
end
function clearTimeout(ref) _emu:clearTimeout(_PI.cancelTimer(ref)) end
function clearInterval(ref) _emu:clearInterval(_PI.cancelTimer(ref)) end

class 'QuickAppBase'
function QuickAppBase:__init(dev)
  self.id = dev.id
  self.type = dev.type
  self.roomID = dev.roomID
  self.name = dev.name
  self.properties = table.copy(dev.properties)
  self.uiCallbacks = {}
end

function QuickAppBase:debug(...) fibaro.debug(__TAG,...) end
function QuickAppBase:trace(...) fibaro.trace(__TAG,...) end
function QuickAppBase:warning(...) fibaro.warning(__TAG,...) end
function QuickAppBase:error(...) fibaro.error(__TAG,...) end

function QuickAppBase:registerUICallback(elm, typ, fun)
  local uic = self.uiCallbacks
  uic[elm] = uic[elm] or {}
  uic[elm][typ] = fun
end

function QuickAppBase:setupUICallbacks()
  local callbacks = (self.properties or {}).uiCallbacks or {}
  for _, elm in pairs(callbacks) do
    self:registerUICallback(elm.name, elm.eventType, elm.callback)
  end
end

QuickAppBase.registerUICallbacks = QuickAppBase.setupUICallbacks

function QuickAppBase:callAction(name, ...)
  --if name == "" then return end
  if (type(self[name]) == 'function') then return self[name](self, ...)
  else print(fmt("[WARNING] Class does not have '%s' function defined - action ignored",tostring(name))) end
end

function QuickAppBase:updateProperty(name,value)
  self.properties[name] = value
  api.post("/plugins/updateProperty",{
    deviceId=self.id,
    propertyName=name,
    value=table.copy(value)
  })
end

function QuickAppBase:updateView(elm,prop,value)
end

function QuickAppBase:setVariable(name, value)
  local qvars,found = self.properties.quickAppVariables,false
  for _,v in ipairs(qvars) do
    if v.name == name then
      v.value = value
      found = true
      break
    end
  end
  if not found then
    table.insert(qvars, {name=name, value=value})
  end
end

function QuickAppBase:getVariable(name)
  local qvars = self.properties.quickAppVariables
  for _,v in ipairs(qvars) do
    if v.name == name then
      return v.value
    end
  end
  return ""
end


function QuickAppBase:internalStorageSet(key, val, hidden)
  __assert_type(key, 'string')
  local data = { name = key, value = val, isHidden = hidden }
  local _, stat = api.put("/plugins/" .. self.id .. "/variables/" .. key, data, true)
  --print(key,stat)
  if stat > 206 then
    local _, stat = api.post("/plugins/" .. self.id .. "/variables", data)
    --print(key,stat)
    return stat
  end
end

function QuickAppBase:internalStorageGet(key)
  __assert_type(key, 'string')
  if key then
    local res, stat = api.get("/plugins/" .. self.id .. "/variables/" .. key)
    if stat ~= 200 then return nil end
    return res.value
  else
    local res, stat = api.get("/plugins/" .. self.id .. "/variables")
    if stat ~= 200 then return nil end
    local values = {}
    for _, v in pairs(res) do values[v.name] = v.value end
    return values
  end
end

function QuickAppBase:internalStorageRemove(key) return api.delete("/plugins/" .. self.id .. "/variables/" .. key) end

function QuickAppBase:internalStorageClear() return api.delete("/plugins/" .. self.id .. "/variables") end

class 'QuickApp'(QuickAppBase)
function QuickApp:__init(dev)
  __TAG = dev.name..dev.id
  plugin.mainQA = self
  QuickAppBase.__init(self, dev)
  self.childDevices = {}
  self.childsInitialized = false
  self:setupUICallbacks()
  if self.onInit then self:onInit() end
  if not self.childsInitialized then self:initChildDevices() end
end

---@diagnostic disable-next-line: duplicate-set-field
function QuickApp:initChildDevices(map)
  map = map or {}
  local children = api.get("/devices?parentId="..self.id)
  local childDevices = self.childDevices
  for _, c in pairs(children) do
    if childDevices[c.id] == nil and map[c.type] then
      childDevices[c.id] = map[c.type](c)
    elseif childDevices[c.id] == nil then
      self:error(fmt("Class for the child device: %s, with type: %s not found. Using base class: QuickAppChild", c.id, c.type))
      childDevices[c.id] = QuickAppChild(c)
    end
---@diagnostic disable-next-line: inject-field
    childDevices[c.id].parent = self
  end
  self.childsInitialized = true
end

function QuickApp:createChildDevice(options, classRepresentation)    
    __assert_type(options, "table")
    __assert_type(options.name, "string")
    __assert_type(options.type, "string")
    options.parentId = self.id
    if options.initialInterfaces then
        __assert_type(options.initialInterfaces, "table")
        table.insert(options.initialInterfaces, "quickAppChild")
    else
        options.initialInterfaces = {"quickAppChild"}
    end
    if options.initialProperties then
        __assert_type(options.initialProperties, "table")
    end
    local child = api.post("/plugins/createChildDevice", options)
    if classRepresentation == nil then
        classRepresentation = QuickAppChild
    end
    self.childDevices[child.id] = classRepresentation(child)
---@diagnostic disable-next-line: inject-field
    self.childDevices[child.id].parent = self

    return self.childDevices[child.id]
end

class 'QuickAppChild'(QuickAppBase)
function QuickAppChild:__init(dev)
  QuickAppBase.__init(self, dev)
  self.parentId = dev.parentId
  if self.onInit then self:onInit() end
end

function onAction(id,event) -- { deviceID = 1234, actionName = "test", args = {1,2,3} }
  --if Emu:DBGFLAG('onAction') then print("onAction: ", json.encode(event)) end
  local self = plugin.mainQA
---@diagnostic disable-next-line: undefined-field
  if self.actionHandler then return self:actionHandler(event) end
  if event.deviceId == self.id then
    return self:callAction(event.actionName, table.unpack(event.args))
  elseif self.childDevices[event.deviceId] then
    return self.childDevices[event.deviceId]:callAction(event.actionName, table.unpack(event.args))
  end
  self:error(fmt("Child with id:%s not found",id))
end

function onUIEvent(id, event)
  local quickApp = plugin.mainQA
  --if Emu:DBGFLAG('onUIEvent') then print("UIEvent: ", json.encode(event)) end
---@diagnostic disable-next-line: undefined-field
  if quickApp.UIHandler then quickApp:UIHandler(event) return end
  if quickApp.uiCallbacks[event.elementName] and quickApp.uiCallbacks[event.elementName][event.eventType] then
    quickApp:callAction(quickApp.uiCallbacks[event.elementName][event.eventType], event)
  else
    fibaro.warning(__TAG,fmt("UI callback for element:%s not found.", event.elementName))
  end
end

function QuickAppBase:UIAction(eventType, elementName, arg)
  local event = {
    deviceId = self.id, 
    eventType = eventType,
    elementName = elementName
  }
  event.values = arg ~= nil and  { arg } or json.util.InitArray({})
  onUIEvent(self.id, event)
end

class 'RefreshStateSubscriber'

function RefreshStateSubscriber:__init()
 self.time = os.time() -- Skip events before this time
  self.subscribers = {}
  self.last = 0
  function self.handle(event)
    if self.time > event.created+2 then return end -- Allow for 2 seconds mismatch between emulator and HC3
    for sub,_ in pairs(self.subscribers) do
      if sub.filter(event) then pcall(sub.handler,event) end
    end
  end
end

function RefreshStateSubscriber:subscribe(filter, handler)
  return self.subject:filter(function(event) return filter(event) end):subscribe(function(event) handler(event) end)
end

local MTsub = { __tostring = function(self) return "Subscription" end }

local SUBTYPE = '%SUBSCRIPTION%'
function RefreshStateSubscriber:subscribe(filter, handler)
  local sub = setmetatable({ type=SUBTYPE, filter = filter, handler = handler },MTsub)
  self.subscribers[sub]=true
  return sub
end

function RefreshStateSubscriber:unsubscribe(subscription)
  if type(subscription)=='table' and subscription.type==SUBTYPE then 
    self.subscribers[subscription]=nil
  end
end

function RefreshStateSubscriber:run() fibaro.hc3emu.refreshState:addListener(self.handle) end
function RefreshStateSubscriber:stop() fibaro.hc3emu.refreshState:removeListener(self.handle) end
