-- @module hc3emu2.type
---@description Type validation utilities for HC3Emu2
---@author Jan Gabrielsson
---@license MIT
---
---This module provides type validation and schema utilities:
---- Type checkers for string, number, boolean, array, table, identifier
---- Optional and either type combinators
---- Table schema validation
---- UI element schema definitions
---
---@usage
---```lua
---local Type = require("hc3emu2.type")
---local validator = Type:table{ name = Type:string(), age = Type:number():optional() }
---local ok, err = validator({ name = "John", age = 42 })
---```

local fmt = string.format

local Type = {}
local function TypeChecker(namer,f)
  local t = {f=f}
  return setmetatable(t,{
    __call = function(_, value)
      local valid, err, br = f(value)
      if not valid then
        return false, err, br
      end
      return true
    end,
    __index = function(t,k) if k=='t' then return t else return Type[k] end end,
    __tostring = type(namer)=='function' and namer or function() return namer end,
  })
end

function Type:key()
  self._key = true
  return self
end

function Type:either(validators)
  local function namer() local r={} for _,v in ipairs(validators) do r[#r+1]=tostring(v) end return fmt("(%s)",table.concat(r," | ")) end 
  return TypeChecker(namer,function(value)
    for _,validator in ipairs(validators) do
      local valid, err, br = validator(value)
      if valid then
        return true
      end
      if br then
        return false, err, br
      end
    end
    return false, "Value does not match any of the provided validators"
  end)
end

function Type:string(v) 
  return TypeChecker('<string>',function(value)
    if type(value) == "string" then
      if v ~= nil and v ~= value then
        return false, fmt("Expected string '%s', got '%s'", v, value)
      end
      return true
    else
      return false, "Expected string"
    end
  end)
end

function Type:identifier() 
  return TypeChecker('<identifier>',function(value)
    if type(value) == "string" and value:match("^[%a_][%w_]*$") then
      return true
    else
      return false, fmt("Expected identifier, got '%s'", tostring(value))
    end
  end)
end

function Type:number() 
  return TypeChecker('<number>',function(value)
    if type(value) == "number" then
      return true
    else
      return false, "Expected number"
    end
  end)
end

function Type:boolean() 
  return TypeChecker('<boolean>',function(value)
    if type(value) == "boolean" then
      return true
    else
      return false, "Expected boolean"
    end
  end)
end

function Type:optional() 
  local t = self.t
  local function namer() return "?"..tostring(t) end
  return TypeChecker(namer,function(value)
    if value ~= nil then 
      return t(value) 
    else return true end
  end)
end

function Type:array(typ) 
  local namer = function() return fmt("[%s,...]", tostring(typ)) end
  return TypeChecker(namer,function(value)
    if type(value) == "table" and not (value[1] == nil and next(value) ~= nil) then
      for i,v in ipairs(value) do
        local valid, err = typ(v)
        if not valid then
          return false, fmt("Array item %d: %s", i, err)
        end
      end
      return true
    else
      return false, "Expected array"
    end
  end)
end

function Type:table(values) 
  local fields = {}
  local keyIdx, keyValidator, hasKey = nil,nil,false
  for k,v in pairs(values) do
    if v._key then keyIdx,keyValidator,hasKey = k,v,true
    else fields[k]=v end
  end
  local function namer()
    local r = {}
    if keyIdx then
      r[#r+1] = fmt("Key:%s: %s", keyIdx, tostring(keyValidator))
    end
    for k,v in pairs(fields) do
      r[#r+1] = fmt("%s: %s", k, tostring(v))
    end
    return fmt("{%s}", table.concat(r, ", "))
  end
  return TypeChecker(namer,function(value)
    if type(value) == "table" then
      if keyValidator ~= nil then
         local valid, err = keyValidator(value[keyIdx])
          if not valid then
            return false, "Key '" .. keyIdx .. "' " .. err
          end
      end
      for k, v in pairs(fields) do
        local valid, err = v(value[k])
        if not valid then
          return false, "Key '" .. k .. "' " .. err, hasKey
        end
      end
      return true
    else
      return false, "Expected table"
    end
  end)
end

-- local validate = Type:either{
--   Type:string(),
--   Type:boolean():optional(),
--   Type:number(),
--   Type:array(Type:string()):optional(),
--   Type:table{
--     a = Type:string(),
--     b = Type:number(),
--     c = Type:boolean(),
--     d = Type:string():optional(),
--   }
-- }
-- print(tostring(validate))

-- print(validate("Hello"))  -- true
-- print(validate(42))      -- true
-- print(validate(true))    -- false
-- print(validate({a="",b=42,c=true,d="88"}))      -- true

-- print("----------------------------------")

local UIelement = Type:either{
    Type:table{
    label = Type:string():key(),
    text = Type:string(),
    visible = Type:boolean():optional(),
  },
  Type:table{
    button = Type:identifier():key(),
    text = Type:string(),
    onReleased = Type:identifier():optional(),
    onLongPressDown = Type:identifier():optional(),
    onLongPressReleased = Type:identifier():optional(),
    visible = Type:boolean():optional(),
  },
  Type:table{
    slider = Type:identifier():key(),
    text = Type:string():optional(),
    max = Type:number():optional(),
    min = Type:number():optional(),
    step = Type:number():optional(),
    value = Type:number():optional(),
    onChanged = Type:identifier(),
    visible = Type:boolean():optional(),
  },
  Type:table{
    switch = Type:identifier():key(),
    text = Type:string(),
    onReleased = Type:identifier(),
    visible = Type:boolean():optional(),
  },
  Type:table{
    select = Type:identifier():key(),
    text = Type:string(),
    options = Type:array(Type:table{text=Type:string(),type=Type:string('option'),value=Type:string()}):optional(),
    value = Type:string():optional(),
    onToggled = Type:identifier(),
    visible = Type:boolean():optional(),
  },
  Type:table{
    multi = Type:identifier():key(),
    text = Type:string():optional(),
    options = Type:array(Type:table{text=Type:string(),type=Type:string('option'),value=Type:string()}):optional(),
    values = Type:array(Type:string()):optional(),
    onToggled = Type:identifier(),
    visible = Type:boolean():optional(),
  }
}

Type.UIelement = UIelement

-- print(tostring(UIelement))

-- print(UIelement({button="b1",text="My button",onReleased='77'})) 
-- print(UIelement({slider="s1",onChanged="FOPP"}))  
-- print(UIelement({button="b1",text="My button"}))  
-- print(UIelement({select="b1",text="My button",onToggled="FOPP", options={{type='option',value='opt1',text='Option 1'}}}))  

return Type