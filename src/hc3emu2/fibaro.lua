fibaro = {}
local fmt = string.format

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

function fibaro.call(deviceId,action,...)
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

function fibaro.getValue(id,prop) end