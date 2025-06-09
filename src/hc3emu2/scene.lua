Emu = Emu
local fmt = string.format
local copas = require("copas")
local embed = require("hc3emu2.embedui")

---@class Scene
Scene = {}
class 'Scene'
function Scene:__init()
  self.id = 42
  self.cond = nil
end

function Scene:initialize(src)
  local cond = src:match("COND%s*=%b{}")
  if not cond then 
    Emu:WARNINGF(true,"Scene %s has no COND",self.id)
    return false 
  end

  local condTable = load("return "..cond)()
  self.cond = self:compile(condTable)

end

local function AND(ctx, ...)
  for _,f in ipairs({...}) do if not f(ctx) then return false end end
  return true
end
local function OR(ctx, ...)
  for _,f in ipairs({...}) do if f(ctx) then return true end end
  return false
end

local operator = {
  ['=='] = function(a,b) return a == b end,
  ['!='] = function(a,b) return a ~= b end,
  ['<'] = function(a,b) return a < b end,
  ['<='] = function(a,b) return a <= b end,
  ['>'] = function(a,b) return a > b end,
  ['>='] = function(a,b) return a >= b end,
  ['anyValue'] = function(a,b) end,
}

local match = {
  ['match'] = function(a,b) return a == b end,
  ['match=='] = function(a,b) return a ~= b end,
  ['match!='] = function(a,b) return a ~= b end,
  ['match<'] = function(a,b) return a < b end,
  ['match<='] = function(a,b) return a <= b end,
  ['match>'] = function(a,b) return a > b end,
  ['match>='] = function(a,b) return a >= b end,
}

local function isBool(v) return type(v) == 'boolean' end

local node = {}
-- {
--   type = "device",
--   id = 25,
--   property = "value",
--   operator = "==",
--   value = true,
--   isTrigger = true
-- },
function node.device(self,cond)
  local dev = Emu.devices[cond.deviceId]
  if not dev then 
    Emu:ERRORF("Device %s not found in scene %s",cond.deviceId,self.id)
    return function() return false end
  end
  local prop = cond.property
  if not dev.vars[prop] then 
    Emu:ERRORF("Property %s not found in device %s in scene %s",prop,dev.id,self.id)
    return function() return false end
  end
  local value = cond.value
  if type(value) == 'table' then value = value[1] end -- Handle single value in table
  return function(ctx) return dev.vars[prop] == value end, {dev}
end

-- {
--   type = "date",
--   property = "cron",
--   operator = "match",
--   value = {"30", "15", "*", "*", "*", "*"},
--   isTrigger = true
-- }
local dateCond = {}
function dateCond.cron(scene,cond)
  assert(match[cond.operator or ""],'Unknown operator for cron condition: '..tostring(cond.operator))
  assert(type(cond.value) == 'table' and #cond.value > 0,'Cron condition must have a table value with at least one element')
  assert(isBool(cond.isTrigger),'isTrigger must be boolean')
  if cond.isTrigger then
    local cron = table.concat(cond.value, " ")
    scene:addMinuteTest(cron)
  else
    scene:addCond({type = "cron", cron = cond.value})
  end
end
function dateCond.cronInterval(scene,cond)
end
function dateCond.sunset(scene,cond)
  assert(cond.operator == '==','Sunset condition must use == operator')
  assert(tonumber(cond.value),'Sunset condition must have number value')
  assert(isBool(cond.isTrigger),'isTrigger must be boolean')
  if cond.isTrigger then
    local offs = tostring(cond.value)
    local t =  "sunset"..(cond.value >= 0 and "+" or "")..offs
    scene:addTimer(t)
  else 
    scene:addCond({type = "sunset", time = cond.value})
  end
end
function dateCond.sunrise(scene,cond)
  assert(cond.operator == '==','Sunset condition must use == operator')
  assert(tonumber(cond.value),'Sunset condition must have number value')
  assert(isBool(cond.isTrigger),'isTrigger must be boolean')
  if cond.isTrigger then
    local offs = tostring(cond.value)
    local t =  "sunrise"..(cond.value >= 0 and "+" or "")..offs
    scene:addTimer(t)
  else 
    scene:addCond({type = "sunrise", time = cond.value})
  end
end
function dateCond.bad(scene,cond)
  error(fmt("Bad date condition in scene %s: %s", scene.id, cond))
end

function node.date(scene,cond) 
  local prop = cond.time
  if prop == 'cron' and operator == 'matchInterval' then prop = 'cronInterval' end
  return dateCond[prop or "bad"](scene,cond)
end

function node.bad(scene,cond)
  error(fmt("Bad condition in scene %s: %s", scene.id, cond))
end

function Scene:compile(cond)
  local op = cond.operator
  if not op then return node[cond.typ or "bad"](self,cond) end
  local args = {}
  assert(cond.conditions,"Scene condition must have 'conditions' field")
  for _,c in ipairs(cond.conditions) do
    local testFun, triggers = self:compile(c)
    args[#args+1] = testFun
  end
  if op == 'all' then return function(ctx) return AND(ctx, table.unpack(args)) end
  elseif op == 'any' then return function(ctx) return OR(ctx, table.unpack(args)) end
  else
    Emu:ERRORF("Unknown operator %s in scene %s",op,self.id)
    return function() return false end
  end
end
