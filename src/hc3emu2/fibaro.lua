fibaro = {}
_emu = _emu
local fmt = string.format

------------- Process info for running environment ---------------- 
_PI = { timers = {}, env = _G, dbg={} } -- Process info to keep track of
function _PI.cancelTimers() -- Cancel all timer started by QA (for restarts)
  for ref,typ in pairs(_PI.timers) do 
    _emu:DEBUGF('timer',"Cancelling timer %s",tostring(ref)) 
    _emu:clearTimeout(ref)
    if typ == 'interval' then _emu:clearInterval(ref) else _emu:clearTimeout(ref) end
  end
  _PI.timers = {}
end
function _PI.addTimer(ref,typ) _PI.timers[ref] = typ return ref end
function _PI.cancelTimer(ref,op) 
  local typ = _PI.timers[ref]
  _PI.timers[ref] = nil 
  if typ == 'interval' then _emu:clearInterval(ref) else _emu:clearTimeout(ref) end
  _emu:DEBUGF('timer',"Timer %s %s",tostring(ref),op)
  if next(_PI.timers) == nil then
    _emu:DEBUGF('timer',"No timers left")
  end
  return ref 
end
function _PI.errorHandler(err,traceback)
  fibaro.error(__TAG,err)
  if traceback then _print(traceback) end
end
function _PI.warningHandler(flag,...)
if flag==true or _PI.dbg[flag] then fibaro.warning(__TAG,fmt(_emu.lib.formatArgs(...))) end 
end
function _PI.debugHandler(flag,...) 
  if flag==true or _PI.dbg[flag] then fibaro.debug(__TAG,fmt(_emu.lib.formatArgs(...))) end 
end
function _PI.name() return __TAG end

local lock = _emu.createLock()
local function gate(fun,...)
  lock:get()
  local function ef(err)
    if type(err) == "table" then return err end
    err = err:gsub("%[string \"","[file \"")
    local trace = _emu.lua.debug.traceback()
    return _emu:createErrorMsg{msg=err,trace=trace}
  end
  local res ={xpcall(fun,ef,...)}
  lock:release()
  if res[1] then return table.unpack(res,2) else error(res[2],2) end
end
_PI.gate = gate

function setInterval(fun,delay) 
  assert(type(fun) == "function", "setInterval requires a function as first argument")
  assert(type(delay) == "number", "setInterval requires a number as second argument")
  local function cb() gate(fun) end
  return _PI.addTimer(_emu:setInterval(cb,delay,_PI),'interval') 
end
function setTimeout(fun,delay) 
  assert(type(fun) == "function", "setTimeout requires a function as first argument")
  assert(type(delay) == "number", "setTimeout requires a number as second argument")
  local ref
  local function cb() gate(fun)  _PI.cancelTimer(ref,"expired") end
  ref = _PI.addTimer(_emu:setTimeout(cb,delay,_PI),'timeout')
  return ref
end
function clearTimeout(ref) _emu:clearTimeout(_PI.cancelTimer(ref,"cancelled")) end
function clearInterval(ref) _emu:clearInterval(_PI.cancelTimer(ref,"cancelled")) end

-----------------------------------------------------------------
---
function __ternary(c, t,f) if c then return t else return f end end
function __fibaro_get_devices() return api.get("/devices/") end
function __fibaro_get_device(deviceId) return api.get("/devices/"..deviceId) end
function __fibaro_get_room(roomId) return api.get("/rooms/"..roomId) end
function __fibaro_get_scene(sceneId) return api.get("/scenes/"..sceneId) end
function __fibaro_get_global_variable(varName) return api.get("/globalVariables/"..varName) end
function __fibaro_get_device_property(deviceId, propertyName) return api.get("/devices/"..deviceId.."/properties/"..propertyName) end
function __fibaro_get_devices_by_type(type) return api.get("/devices?type="..type) end
function __fibaro_add_debug_message(tag, msg, typ) _emu:debugOutput(tag, msg, typ, os.time()) end

function __fibaro_get_partition(id) return api.get('/alarms/v1/partitions/' .. tostring(id)) end
function __fibaro_get_partitions() return api.get('/alarms/v1/partitions') end
function __fibaro_get_breached_partitions() return api.get("/alarms/v1/partitions/breached") end
function __fibaroSleep(ms) _emu:sleep(ms) end
function __fibaroUseAsyncHandler(_) return true end
function __assert_type(param, typ)
  if type(param) ~= typ then
    error(fmt("Wrong parameter type, %s required. Provided param '%s' is type of %s",typ, tostring(param), type(param)), 3)
  end
end

local function logStr(...) local b = {} for _,e in ipairs({...}) do b[#b+1]=tostring(e) end return table.concat(b," ") end

function fibaro.debug(tag,...) __fibaro_add_debug_message(tag,logStr(...),"DEBUG") end
function fibaro.trace(tag,...) __fibaro_add_debug_message(tag, logStr(...),"TRACE") end
function fibaro.warning(tag,...) __fibaro_add_debug_message(tag, logStr(...),"WARNING") end
function fibaro.error(tag,...) __fibaro_add_debug_message(tag, logStr(...),"ERROR") end

function fibaro.getPartitions() return __fibaro_get_partitions() end
function fibaro.alarm(arg1, action)
  if type(arg1) == "string" then return fibaro.__houseAlarm(arg1) end
  __assert_type(arg1, "number")
  __assert_type(action, "string")
  local url = "/alarms/v1/partitions/" .. arg1 .. "/actions/arm"
  if action == "arm" then api.post(url)
  elseif action == "disarm" then api.delete(url)
  else error(fmt("Wrong parameter: %s. Available parameters: arm, disarm",action),2) end
end

function fibaro.__houseAlarm(action)
  __assert_type(action, "string")
  local url = "/alarms/v1/partitions/actions/arm"
  if action == "arm" then api.post(url)
  elseif action == "disarm" then api.delete(url)
  else error("Wrong parameter: '" .. action .. "'. Available parameters: arm, disarm", 3) end
end

function fibaro.alert(alertType, ids, notification)
  __assert_type(alertType, "string")
  __assert_type(ids, "table")
  __assert_type(notification, "string")
  local action = ({
    email = "sendGlobalEmailNotifications",push = "sendGlobalPushNotifications",simplePush = "sendGlobalPushNotifications",
  })[alertType]
  if action == nil then
    error("Wrong parameter: '" .. alertType .. "'. Available parameters: email, push, simplePush", 2)
  end
  for _,id in ipairs(ids) do __assert_type(id, "number") end
  
  if alertType == 'push' then
    local mobileDevices = __fibaro_get_devices_by_type('iOS_device')
    assert(type(mobileDevices) == 'table', "Failed to get mobile devices")
    local usersId = ids
    ids = {}
    for _, userId in ipairs(usersId) do
      for _, device in ipairs(mobileDevices) do
        if device.properties.lastLoggedUser == userId then
          table.insert(ids, device.id)
        end
      end
    end
  end
  for _, id in ipairs(ids) do
    fibaro.call(id, 'sendGlobalPushNotifications', notification, "false")
  end
end

function fibaro.emitCustomEvent(name)
  __assert_type(name, "string")
  api.post("/customEvents/"..name)
end

function fibaro.call(deviceId, action, ...)
  __assert_type(action, "string")
  if type(deviceId) == "table" then
    for _,id in pairs(deviceId) do __assert_type(id, "number") end
    for _,id in pairs(deviceId) do fibaro.call(id, action, ...) end
  else
    __assert_type(deviceId, "number")
    local arg = {...}
    local arg2 = #arg>0 and arg or nil
    return api.post("/devices/"..deviceId.."/action/"..action, { args = arg2 })
  end
end

function fibaro.callhc3(deviceId, action, ...)
  __assert_type(action, "string")
  if type(deviceId) == "table" then
    for _,id in pairs(deviceId) do __assert_type(id, "number") end
    for _,id in pairs(deviceId) do fibaro.call(id, action, ...) end
  else
    __assert_type(deviceId, "number")
    local arg = {...}
    local arg2 = #arg>0 and arg or nil
    return api.hc3.post("/devices/"..deviceId.."/action/"..action, { args = arg2 })
  end
end

function fibaro.callGroupAction(actionName, actionData)
  __assert_type(actionName, "string")
  __assert_type(actionData, "table")
  local response, status = api.post("/devices/groupAction/"..actionName, actionData)
  if status ~= 202 then return nil end
  return response and response.devices
end

function fibaro.get(deviceId, prop)
  __assert_type(deviceId, "number")
  __assert_type(prop, "string")
  prop = __fibaro_get_device_property(deviceId, prop)
  if prop == nil then return end
  return prop.value, prop.modified
end

function fibaro.getValue(deviceId, propertyName)
  __assert_type(deviceId, "number")
  __assert_type(propertyName, "string")
  return (fibaro.get(deviceId, propertyName))
end

function fibaro.getType(deviceId)
  __assert_type(deviceId, "number")
  local dev = __fibaro_get_device(deviceId)
  return dev and dev.type or nil
end

function fibaro.getName(deviceId)
  __assert_type(deviceId, 'number')
  local dev = __fibaro_get_device(deviceId)
  return dev and dev.name or nil
end

function fibaro.getRoomID(deviceId)
  __assert_type(deviceId, 'number')
  local dev = __fibaro_get_device(deviceId)
  return dev and dev.roomID or nil
end

function fibaro.getSectionID(deviceId)
  __assert_type(deviceId, 'number')
  local dev = __fibaro_get_device(deviceId)
  if dev == nil then return end
  return __fibaro_get_room(dev.roomID).sectionID
end

function fibaro.getRoomName(roomId)
  __assert_type(roomId, 'number')
  local room = __fibaro_get_room(roomId)
  return room and room.name or nil
end

function fibaro.getRoomNameByDeviceID(deviceId, propertyName)
  __assert_type(deviceId, 'number')
  local dev = __fibaro_get_device(deviceId)
  if dev == nil then return end
  local room = __fibaro_get_room(dev.roomID)
  return room and room.name or nil
end

function fibaro.getDevicesID(filter)
  if not (type(filter) == 'table' and next(filter)) then
    return fibaro.getIds(__fibaro_get_devices())
  end
  
  local args = {}
  for key, val in pairs(filter) do
    if key == 'properties' and type(val) == 'table' then
      for n,p in pairs(val) do
        if p == "nil" then
          args[#args+1]='property='..tostring(n)
        else
          args[#args+1]='property=['..tostring(n)..','..tostring(p)..']'
        end
      end
    elseif key == 'interfaces' and type(val) == 'table' then
      for _,i in pairs(val) do
        args[#args+1]='interface='..tostring(i)
      end
    else
      args[#args+1]=tostring(key).."="..tostring(val)
    end
  end
  local argsStr = table.concat(args,"&")
  return fibaro.getIds(api.get('/devices/?'..argsStr))
end

function fibaro.getIds(devices)
  local res = {}
  for _,d in pairs(devices) do
    if type(d) == 'table' and d.id ~= nil and d.id > 3 then res[#res+1]=d.id end
  end
  return res
end

function fibaro.getGlobalVariable(name)
  __assert_type(name, 'string')
  local var = __fibaro_get_global_variable(name)
  if var == nil then return end
  return var.value, var.modified
end

function fibaro.setGlobalVariable(name, value)
  __assert_type(name, 'string')
  __assert_type(value, 'string')
  return api.put("/globalVariables/"..name, {value=tostring(value), invokeScenes=true})
end

function fibaro.scene(action, ids)
  __assert_type(action, "string")
  __assert_type(ids, "table")
  assert(action=='execute' or action =='kill',"Wrong parameter: "..action..". Available actions: execute, kill")
  for _, id in ipairs(ids) do __assert_type(id, "number") end
  for _, id in ipairs(ids) do api.post("/scenes/"..id.."/"..action) end
end

function fibaro.profile(action, id)
  __assert_type(id, "number")
  __assert_type(action, "string")
  if action ~= "activeProfile" then
    error("Wrong parameter: " .. action .. ". Available actions: activateProfile", 2)
  end
  return api.post("/profiles/activeProfile/"..id)
end

local FUNCTION = "func".."tion"
function fibaro.setTimeout(timeout, action, errorHandler)
  __assert_type(timeout, "number")
  __assert_type(action, FUNCTION)
  local fun = action
  if errorHandler then
    fun = function()
      local stat,err = pcall(action)
      if not stat then pcall(errorHandler,err) end
    end
  end
  return setTimeout(fun, timeout)
end

function fibaro.clearTimeout(ref)
  __assert_type(ref, "number")
  clearTimeout(ref)
end

function fibaro.wakeUpDeadDevice(deviceID)
  __assert_type(deviceID, 'number')
  fibaro.call(1,'wakeUpDeadDevice',deviceID)
end

function fibaro.sleep(ms)
  __assert_type(ms, "number")
  __fibaroSleep(ms)
end

local function concatStr(...)
  local args = {}
  for _,o in ipairs({...}) do args[#args+1]=tostring(o) end
  return table.concat(args," ")
end

function fibaro.debug(tag, ...)
  __assert_type(tag, "string")
  __fibaro_add_debug_message(tag, concatStr(...), "debug")
end

function fibaro.warning(tag, ...)
  __assert_type(tag, "string")
  __fibaro_add_debug_message(tag,  concatStr(...), "warning")
end

function fibaro.error(tag, ...)
  __assert_type(tag, "string")
  __fibaro_add_debug_message(tag,  concatStr(...), "error")
end

function fibaro.trace(tag, ...)
  __assert_type(tag, "string")
  __fibaro_add_debug_message(tag,  concatStr(...), "trace")
end

function fibaro.useAsyncHandler(value)
  __assert_type(value, "boolean")
  __fibaroUseAsyncHandler(value)
end

function fibaro.isHomeBreached()
  local ids = __fibaro_get_breached_partitions()
  assert(type(ids)=="table")
  return next(ids) ~= nil
end

function fibaro.isPartitionBreached(partitionId)
  __assert_type(partitionId, "number")
  local ids = __fibaro_get_breached_partitions()
  assert(type(ids)=="table")
  for _,id in pairs(ids) do
    if id == partitionId then return true end
  end
end

function fibaro.getPartitionArmState(partitionId)
  __assert_type(partitionId, "number")
  local partition = __fibaro_get_partition(partitionId)
  if partition ~= nil then
    return partition.armed and 'armed' or 'disarmed'
  end
end

function fibaro.getHomeArmState()
  local n,armed = 0,0
  local partitions = __fibaro_get_partitions()
  assert(type(partitions)=="table")
  for _,partition in pairs(partitions) do
    n = n + 1; armed = armed + (partition.armed and 1 or 0)
  end
  if armed == 0 then return 'disarmed'
  elseif armed == n then return 'armed'
  else return 'partially_armed' end
end

function fibaro.getSceneVariable(name)
  __assert_type(name, "string")
  --local scene = E:getRunner()
  --assert(scene.kind == "SceneRunner","fibaro.getSceneVariable must be called from a scene")
  --return scene:getVariable(name)
end

function fibaro.setSceneVariable(name,value)
  __assert_type(name, "string")
  --local scene = E:getRunner()
  --assert(scene.kind == "SceneRunner","fibaro.setSceneVariable must be called from a scene")
  --scene:setVariable(name,value) 
end

hub = fibaro