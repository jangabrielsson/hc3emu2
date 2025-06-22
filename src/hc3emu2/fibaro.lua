-- @module hc3emu2.fibaro
---@description Fibaro API emulation module for HC3Emu2
---@author Jan Gabrielsson
---@license MIT
---
---This module provides the Fibaro API emulation for HC3Emu2.
---It implements the core Fibaro API functions used by QuickApps and scenes.
---
---Key features:
---- Device management (get, set, call)
---- Scene control
---- Global variables
---- Alarm system
---- Timer functions
---- Logging functions
---
---@usage
---```lua
----- Get a device
---local device = fibaro.get(123)
---
----- Call a device action
---fibaro.call(123, "turnOn")
---
----- Set a global variable
---fibaro.setGlobalVariable("myVar", "value")
---```
---
---@dependencies
---- hc3emu2.emu - Core emulator functionality
---- hc3emu2.api - API handling
---
---@see hc3emu2.emu - Core emulator
---@see hc3emu2.api - API handling

fibaro = {}
_G._emu = _emu
local fmt = string.format

------------- Process info for running environment ---------------- 
_PI = { timers = {}, env = _G, dbg={} } -- Process info to keep track of

-- Cancels all active timers (setTimeout, setInterval) associated with the current QuickApp instance.
-- This is typically used during QA restarts to clean up pending timers.
function _PI.cancelTimers() -- Cancel all timer started by QA (for restarts)
  for ref,typ in pairs(_PI.timers) do 
    _emu:DEBUGF('timer',"Cancelling timer %s",tostring(ref)) 
    _emu:clearTimeout(ref)
    if typ == 'interval' then _emu:clearInterval(ref) else _emu:clearTimeout(ref) end
  end
  _PI.timers = {}
end

-- Adds a timer reference to the _PI.timers table.
-- @param ref - The timer reference returned by _emu:setTimeout or _emu:setInterval.
-- @param typ - The type of timer ('interval' or 'timeout').
-- @return The timer reference.
function _PI.addTimer(ref,typ) _PI.timers[ref] = typ return ref end

-- Cancels a specific timer and removes it from the _PI.timers table.
-- @param ref - The timer reference to cancel.
-- @param op - A string describing the operation (e.g., "expired", "cancelled").
-- @return The cancelled timer reference.
function _PI.cancelTimer(ref,op) 
  local typ = _PI.timers[ref]
  _PI.timers[ref] = nil 
  if typ == 'interval' then _emu:clearInterval(ref) else _emu:clearTimeout(ref) end
  _emu:DEBUGF('timer',"Timer %s %s",tostring(ref),op)
  if next(_PI.timers) == nil then
    _emu:DEBUGF('timer',"No timers left")
    if fibaro.noTimersLeft then fibaro.noTimersLeft() end
  end
  return ref 
end

if _emu.quitWhenDone then
  function fibaro.noTimersLeft()
    _emu:DEBUGF(true,"No timers left, quitting emulator")
    _emu.lua.os.exit(0)
  end
end
-- Handles errors by logging them using fibaro.error and printing a traceback if available.
-- @param err - The error message or object.
-- @param traceback - An optional traceback string.
function _PI.errorHandler(err,traceback)
  fibaro.error(__TAG,err)
  if traceback then _print(traceback) end
end

-- Handles warning messages, logging them if the specified flag is true or enabled in _PI.dbg.
-- @param flag - A boolean or string key to check in _PI.dbg for enabling the warning.
-- @param ... - Arguments to be formatted into the warning message.
function _PI.warningHandler(flag,...)
if flag==true or _PI.dbg[flag] then fibaro.warning(__TAG,fmt(_emu.lib.formatArgs(...))) end 
end

-- Handles debug messages, logging them if the specified flag is true or enabled in _PI.dbg.
-- @param flag - A boolean or string key to check in _PI.dbg for enabling the debug message.
-- @param ... - Arguments to be formatted into the debug message.
function _PI.debugHandler(flag,...) 
  if flag==true or _PI.dbg[flag] then fibaro.debug(__TAG,fmt(_emu.lib.formatArgs(...))) end 
end

-- Returns the tag (name) of the current QuickApp instance.
-- @return The QuickApp tag string.
function _PI.name() return __TAG end

local lock = _emu.createLock()

-- A gate function to ensure thread-safe execution of a given function.
-- It uses a lock to serialize calls and provides a custom error handler
-- that formats error messages and includes a traceback.
-- @param fun - The function to execute.
-- @param ... - Arguments to pass to the function.
-- @return The results of the function call, or throws an error if the call fails.
local function trimTB(tb)
  return tb:gsub("stack traceback:\n%s*[^\n]+fibaro%.lua.-\n", "")
end

-- Maybe create my own traceback function to show a more readable stack trace...
local function myTraceback()
  local index = 0
  while true do
    local info = _emu.lua.debug.getinfo(index)
    if not info then break end
    if info.what == "C" or info.what == "main" then
      index = index + 1
    else
      local file = info.short_src:match("([^/\\]+)$") or info.short_src
      local line = info.currentline > 0 and ":" .. info.currentline or ""
      _emu:DEBUGF(true,"%s%s%s",file,line,info.name or "")
      index = index + 1
    end
  end
end

local function gate(fun,...)
  lock:get() --_emu:DEBUGF(true,"Get lock")
  local function ef(err)
    if type(err) == "table" then return err end
    err = err:gsub("%[string \"","[file \"")
    local trace = trimTB(_emu.lua.debug.traceback())
    --local trace = copas.gettraceback()
    --myTraceback()
    return _emu:createErrorMsg{msg=err,trace=trace}
  end
  local res ={xpcall(fun,ef,...)}
  --_emu:DEBUGF(true,"Release lock")
  lock:release()
  if res[1] then return table.unpack(res,2) else error(res[2],2) end
end
_PI.gate = gate

-- Sets a function to be called repeatedly at a specified delay.
-- Uses the gate function for thread-safe execution.
-- @param fun - The function to call.
-- @param delay - The delay in milliseconds between calls.
-- @return A timer reference that can be used with clearInterval.
function setInterval(fun,delay) 
  assert(type(fun) == "function", "setInterval requires a function as first argument")
  assert(type(delay) == "number", "setInterval requires a number as second argument")
  local function cb() gate(fun) end
  return _PI.addTimer(_emu:setInterval(cb,delay,_PI),'interval') 
end

-- Sets a function to be called once after a specified delay.
-- Uses the gate function for thread-safe execution.
-- The timer is automatically cancelled after the function executes.
-- @param fun - The function to call.
-- @param delay - The delay in milliseconds.
-- @return A timer reference that can be used with clearTimeout.
function setTimeout(fun,delay) 
  assert(type(fun) == "function", "setTimeout requires a function as first argument")
  assert(type(delay) == "number", "setTimeout requires a number as second argument")
  local ref
  local function cb() gate(fun)  _PI.cancelTimer(ref,"expired") end
  ref = _PI.addTimer(_emu:setTimeout(cb,delay,_PI),'timeout')
  return ref
end

-- Clears a timeout previously set with setTimeout.
-- @param ref - The timer reference returned by setTimeout.
function clearTimeout(ref) _emu:clearTimeout(_PI.cancelTimer(ref,"cancelled")) end

-- Clears an interval previously set with setInterval.
-- @param ref - The timer reference returned by setInterval.
function clearInterval(ref) _emu:clearInterval(_PI.cancelTimer(ref,"cancelled")) end

local function lockSpeedScheduler(fun)
  return function(...)
    local f = _emu.lib.speedGate
    _emu.lib.speedGate[1] = true
    local res = {fun(...)}
    _emu.lib.speedGate[1] = false
    return table.unpack(res)
  end
end

api.get = lockSpeedScheduler(api.get)
api.post = lockSpeedScheduler(api.post)
api.put = lockSpeedScheduler(api.put)
api.delete = lockSpeedScheduler(api.delete)
-----------------------------------------------------------------
---

-- A simple ternary operator implementation.
-- @param c - The condition.
-- @param t - The value to return if the condition is true.
-- @param f - The value to return if the condition is false.
-- @return t or f based on the condition.
function __ternary(c, t,f) if c then return t else return f end end

-- Retrieves all devices from the system.
-- @return A table containing all device objects.
function __fibaro_get_devices() return api.get("/devices/") end

-- Retrieves a specific device by its ID.
-- @param deviceId - The ID of the device.
-- @return The device object, or nil if not found.
function __fibaro_get_device(deviceId) return api.get("/devices/"..deviceId) end

-- Retrieves a specific room by its ID.
-- @param roomId - The ID of the room.
-- @return The room object, or nil if not found.
function __fibaro_get_room(roomId) return api.get("/rooms/"..roomId) end

-- Retrieves a specific scene by its ID.
-- @param sceneId - The ID of the scene.
-- @return The scene object, or nil if not found.
function __fibaro_get_scene(sceneId) return api.get("/scenes/"..sceneId) end

-- Retrieves a global variable by its name.
-- @param varName - The name of the global variable.
-- @return The global variable object, or nil if not found.
function __fibaro_get_global_variable(varName) return api.get("/globalVariables/"..varName) end

-- Retrieves a specific property of a device.
-- @param deviceId - The ID of the device.
-- @param propertyName - The name of the property.
-- @return The property object, or nil if not found.
function __fibaro_get_device_property(deviceId, propertyName) return api.get("/devices/"..deviceId.."/properties/"..propertyName) end

-- Retrieves all devices of a specific type.
-- @param type - The type of devices to retrieve.
-- @return A table containing device objects of the specified type.
function __fibaro_get_devices_by_type(type) return api.get("/devices?type="..type) end

-- Adds a debug message to the emulator's debug output.
-- @param tag - The tag for the debug message.
-- @param msg - The message string.
-- @param typ - The type of message (e.g., "DEBUG", "ERROR").
function __fibaro_add_debug_message(tag, msg, typ) _emu:debugOutput(tag, msg, typ, os.time()) end

-- Retrieves a specific alarm partition by its ID.
-- @param id - The ID of the alarm partition.
-- @return The alarm partition object, or nil if not found.
function __fibaro_get_partition(id) return api.get('/alarms/v1/partitions/' .. tostring(id)) end

-- Retrieves all alarm partitions.
-- @return A table containing all alarm partition objects.
function __fibaro_get_partitions() return api.get('/alarms/v1/partitions') end

-- Retrieves all breached alarm partitions.
-- @return A table containing breached alarm partition objects.
function __fibaro_get_breached_partitions() return api.get("/alarms/v1/partitions/breached") end

-- Pauses execution for a specified number of milliseconds.
-- @param ms - The duration to sleep in milliseconds.
function __fibaroSleep(ms) _emu:sleep(ms) end

-- Placeholder function, seems to indicate async handler usage.
-- @param _ - Unused parameter.
-- @return Always true.
function __fibaroUseAsyncHandler(_) return true end

-- Asserts that a parameter is of a specific type.
-- Throws an error if the type does not match.
-- @param param - The parameter to check.
-- @param typ - The expected type string (e.g., "number", "string").
function __assert_type(param, typ)
  if type(param) ~= typ then
    error(fmt("Wrong parameter type, %s required. Provided param '%s' is type of %s",typ, tostring(param), type(param)), 3)
  end
end

-- Concatenates multiple arguments into a single space-separated string.
-- @param ... - Arguments to concatenate.
-- @return A string with all arguments converted to string and joined by spaces.
local function logStr(...) 
  local b = {} 
  for _,e in ipairs({...}) do 
    b[#b+1]=tostring(e) 
  end 
  return table.concat(b," ")
end

-- Logs a debug message.
-- @param tag - The tag for the message.
-- @param ... - Arguments to be included in the message.
function fibaro.debug(tag,...) 
  __assert_type(tag, "string")__fibaro_add_debug_message(tag,logStr(...),"DEBUG")
end

-- Logs a trace message.
-- @param tag - The tag for the message.
-- @param ... - Arguments to be included in the message.
function fibaro.trace(tag,...)
  __assert_type(tag, "string") __fibaro_add_debug_message(tag, logStr(...),"TRACE")
end

-- Logs a warning message.
-- @param tag - The tag for the message.
-- @param ... - Arguments to be included in the message.
function fibaro.warning(tag,...)
  __assert_type(tag, "string")
  __fibaro_add_debug_message(tag, logStr(...),"WARNING")
end

-- Logs an error message.
-- @param tag - The tag for the message.
-- @param ... - Arguments to be included in the message.
function fibaro.error(tag,...)
  __assert_type(tag, "string")
  __fibaro_add_debug_message(tag, logStr(...),"ERROR")
end

-- Retrieves all alarm partitions.
-- @return A table of alarm partition objects.
function fibaro.getPartitions() return __fibaro_get_partitions() end

-- Manages alarm partitions or the main house alarm.
-- If arg1 is a string, it controls the house alarm ("arm" or "disarm").
-- If arg1 is a number (partition ID), it controls that specific partition.
-- @param arg1 - Either a partition ID (number) or an action string ("arm", "disarm") for the house alarm.
-- @param action - The action to perform ("arm" or "disarm") if arg1 is a partition ID.
function fibaro.alarm(arg1, action)
  if type(arg1) == "string" then return fibaro.__houseAlarm(arg1) end
  __assert_type(arg1, "number")
  __assert_type(action, "string")
  local url = "/alarms/v1/partitions/" .. arg1 .. "/actions/arm"
  if action == "arm" then api.post(url,nil)
  elseif action == "disarm" then api.delete(url)
  else error(fmt("Wrong parameter: %s. Available parameters: arm, disarm",action),2) end
end

-- Controls the main house alarm.
-- @param action - The action to perform ("arm" or "disarm").
function fibaro.__houseAlarm(action)
  __assert_type(action, "string")
  local url = "/alarms/v1/partitions/actions/arm"
  if action == "arm" then api.post(url,nil)
  elseif action == "disarm" then api.delete(url)
  else error("Wrong parameter: '" .. action .. "'. Available parameters: arm, disarm", 3) end
end

-- Sends an alert notification.
-- @param alertType - The type of alert ("email", "push", "simplePush").
-- @param ids - A table of user IDs or device IDs (for push) to send the notification to.
-- @param notification - The notification message string.
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

-- Emits a custom event.
-- @param name - The name of the custom event.
function fibaro.emitCustomEvent(name)
  __assert_type(name, "string")
  api.post("/customEvents/"..name,nil)
end

-- Calls an action on a device or a table of devices.
-- @param deviceId - A device ID (number) or a table of device IDs.
-- @param action - The name of the action to call (string).
-- @param ... - Arguments to pass to the action.
-- @return The result of the API call for a single device, or nil for multiple devices.
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

-- Calls an action on a device or a table of devices using the hc3 API endpoint.
-- (Likely for direct HC3 communication if different from standard API)
-- @param deviceId - A device ID (number) or a table of device IDs.
-- @param action - The name of the action to call (string).
-- @param ... - Arguments to pass to the action.
-- @return The result of the API call for a single device, or nil for multiple devices.
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

-- Calls a group action.
-- @param actionName - The name of the group action.
-- @param actionData - A table containing data for the group action.
-- @return A table of devices affected by the action if successful (status 202), otherwise nil.
function fibaro.callGroupAction(actionName, actionData)
  __assert_type(actionName, "string")
  __assert_type(actionData, "table")
  local response, status = api.post("/devices/groupAction/"..actionName, actionData)
  if status ~= 202 then return nil end
  return response and response.devices
end

-- Gets a property value and its last modification time for a device.
-- @param deviceId - The ID of the device.
-- @param prop - The name of the property.
-- @return The property value and the last modified timestamp, or nil if not found.
function fibaro.get(deviceId, prop)
  __assert_type(deviceId, "number")
  __assert_type(prop, "string")
  prop = __fibaro_get_device_property(deviceId, prop)
  if prop == nil then return end
  return prop.value, prop.modified
end

-- Gets a property value for a device.
-- @param deviceId - The ID of the device.
-- @param propertyName - The name of the property.
-- @return The property value, or nil if not found.
function fibaro.getValue(deviceId, propertyName)
  __assert_type(deviceId, "number")
  __assert_type(propertyName, "string")
  return (fibaro.get(deviceId, propertyName))
end

-- Gets the type of a device.
-- @param deviceId - The ID of the device.
-- @return The device type string, or nil if not found.
function fibaro.getType(deviceId)
  __assert_type(deviceId, "number")
  local dev = __fibaro_get_device(deviceId)
  return dev and dev.type or nil
end

-- Gets the name of a device.
-- @param deviceId - The ID of the device.
-- @return The device name string, or nil if not found.
function fibaro.getName(deviceId)
  __assert_type(deviceId, 'number')
  local dev = __fibaro_get_device(deviceId)
  return dev and dev.name or nil
end

-- Gets the room ID for a device.
-- @param deviceId - The ID of the device.
-- @return The room ID (number), or nil if not found or device has no room.
function fibaro.getRoomID(deviceId)
  __assert_type(deviceId, 'number')
  local dev = __fibaro_get_device(deviceId)
  return dev and dev.roomID or nil
end

-- Gets the section ID for a device.
-- It first finds the device's room ID, then the section ID of that room.
-- @param deviceId - The ID of the device.
-- @return The section ID (number), or nil if device or room not found.
function fibaro.getSectionID(deviceId)
  __assert_type(deviceId, 'number')
  local dev = __fibaro_get_device(deviceId)
  if dev == nil then return end
  return nil --__fibaro_get_room(dev.roomID).sectionID
end

-- Gets the name of a room by its ID.
-- @param roomId - The ID of the room.
-- @return The room name string, or nil if not found.
function fibaro.getRoomName(roomId)
  __assert_type(roomId, 'number')
  local room = __fibaro_get_room(roomId)
  return room and room.name or nil
end

-- Gets the name of the room a device is in.
-- @param deviceId - The ID of the device.
-- @param propertyName - Unused parameter (likely a typo or leftover).
-- @return The room name string, or nil if device or room not found.
function fibaro.getRoomNameByDeviceID(deviceId, propertyName)
  __assert_type(deviceId, 'number')
  local dev = __fibaro_get_device(deviceId)
  if dev == nil then return end
  local room = __fibaro_get_room(dev.roomID)
  return room and room.name or nil
end

-- Gets IDs of devices based on a filter.
-- If no filter is provided, returns IDs of all devices.
-- The filter can specify properties, interfaces, and other device attributes.
-- @param filter - A table specifying filter criteria.
-- @return A table of device IDs matching the filter.
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

-- Extracts IDs from a table of device objects.
-- Filters out devices with ID <= 3.
-- @param devices - A table of device objects.
-- @return A table containing the IDs of the valid devices.
function fibaro.getIds(devices)
  local res = {}
  for _,d in pairs(devices) do
    if type(d) == 'table' and d.id ~= nil and d.id > 3 then res[#res+1]=d.id end
  end
  return res
end

-- Gets the value and last modification time of a global variable.
-- @param name - The name of the global variable.
-- @return The variable's value and its last modified timestamp, or nil if not found.
function fibaro.getGlobalVariable(name)
  __assert_type(name, 'string')
  local var = __fibaro_get_global_variable(name)
  if var == nil then return end
  return var.value, var.modified
end

-- Sets the value of a global variable.
-- This will also invoke scenes that depend on this variable.
-- @param name - The name of the global variable.
-- @param value - The new value for the variable (will be converted to string).
-- @return The result of the API call.
function fibaro.setGlobalVariable(name, value)
  __assert_type(name, 'string')
  __assert_type(value, 'string')
  return api.put("/globalVariables/"..name, {value=tostring(value), invokeScenes=true})
end

-- Executes or kills scenes.
-- @param action - The action to perform ("execute" or "kill").
-- @param ids - A table of scene IDs.
function fibaro.scene(action, ids)
  __assert_type(action, "string")
  __assert_type(ids, "table")
  assert(action=='execute' or action =='kill',"Wrong parameter: "..action..". Available actions: execute, kill")
  for _, id in ipairs(ids) do __assert_type(id, "number") end
  for _, id in ipairs(ids) do api.post("/scenes/"..id.."/"..action,nil) end
end

-- Activates a user profile.
-- @param action - Should be "activeProfile".
-- @param id - The ID of the profile to activate.
-- @return The result of the API call.
function fibaro.profile(action, id)
  __assert_type(id, "number")
  __assert_type(action, "string")
  if action ~= "activeProfile" then
    error("Wrong parameter: " .. action .. ". Available actions: activateProfile", 2)
  end
  return api.post("/profiles/activeProfile/"..id,nil)
end

local FUNCTION = "func".."tion" -- Obfuscation for "function" string

-- Sets a timeout to execute an action, with an optional error handler.
-- This is a wrapper around the global setTimeout, ensuring type checks.
-- @param timeout - The delay in milliseconds.
-- @param action - The function to execute after the timeout.
-- @param errorHandler - An optional function to call if the action errors.
-- @return A timer reference.
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

-- Clears a timeout previously set with fibaro.setTimeout or the global setTimeout.
-- @param ref - The timer reference.
function fibaro.clearTimeout(ref)
  __assert_type(ref, "number")
  clearTimeout(ref)
end

-- Wakes up a dead Z-Wave device.
-- This typically calls an action on the Z-Wave controller (device ID 1).
-- @param deviceID - The ID of the dead device to wake up.
function fibaro.wakeUpDeadDevice(deviceID)
  __assert_type(deviceID, 'number')
  fibaro.call(1,'wakeUpDeadDevice',deviceID)
end

-- Pauses execution for a specified number of milliseconds.
-- @param ms - The duration to sleep in milliseconds.
function fibaro.sleep(ms)
  __assert_type(ms, "number")
  __fibaroSleep(ms)
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