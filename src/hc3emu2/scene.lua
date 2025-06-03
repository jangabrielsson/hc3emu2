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

local node = {}
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

function node.time(self,cond)
  local time = cond.time
  if type(time) == 'string' then time = Emu.tools.parseTime(time) end
  return function(ctx) return Emu.orgTime() >= time end, {}
end


function Scene:compile(cond)
  local op = cond.operator
  if not op then return node[cond.typ](self,cond) end
  local args = {}
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
