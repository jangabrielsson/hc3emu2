-- ToDo offline module...

local defaultValues = {}

local function Store(args)
  local store,data = {},{}
  local idx = args.idx
  local HTTP = API.HTTP
  defaultValues[args.name] = args.dflts
  return setmetatable(store, {
    __index = function(t,k)
      if k == '_data' then return {data,HTTP.OK}
      elseif data[k] then return {data[k],HTTP.OK}
      else return {nil,HTTP.NOT_FOUND} end
    end,
    __newindex = function(t,k,v)
      local method,value = table.unpack(v)
      if method == 'PUT' then
        if data[k] == nil then error({nil,HTTP.NOT_FOUND})
        else data[k] = value end
      elseif method == 'POST' then
        if data[k]~=nil then error({nil,HTTP.CONFLICT})
        else data[k] = value end
      elseif method == 'DELETE' then
        if data[k]~=nil then
          data[k] = nil
        else error({nil,HTTP.NOT_FOUND}) end
      else error("Bad method") end
    end,
  })
end


local function strip(store) 
  local result = {}
  for _,v in pairs(store._data) do result[#result+1] = v end
  return result
end

local function dflts(name,data)
  for k,v in pairs(defaultValues[name] or {}) do
    if data[k] == nil then data[k] = type(v)=='function' and v() or v end
  end
  return data
end

local store = {
  globalVariables = Store{
    name="globalVariables",idx='name',
    dflts = { 
      readOnly = false,
      isEnum = false,
      enumValues = {},
      created = Emu.lib.userTime,
      modified = Emu.lib.userTime
    },
  },
  rooms = Store{
    name="rooms",idx='id',
    dflts = {
      sectionID = 219,
      isDefault = true,
      visible = true,
      icon = "room_boy",
      iconExtension = "png",
      iconColor = "purple",
      defaultSensors = {},
      meters = {
        energy = 0
      },
      defaultThermostat = nil,
      sortOrder = 1,
      category = "pantry"
    },
  },
  sections = Store{
    name="sections",idx='id',
  },
  customEvents = Store{
    name="customEvents",idx='name',
  },
}

local function setup(Emu)
  local api = Emu.api
  local HTTP = API.HTTP
  
  local function add(path,method)
    local function fun(...)
      local args = {...}
      local _,data = pcall(method,...)
      local res,code = table.unpack(data or {nil,200})
      return res,code
    end
    api:add(path,fun,true)
  end
  
  add("GET/globalVariables", function(ctx)
    return {strip(store.globalVariables),HTTP.OK}
  end)
  add("GET/globalVariables/<name>", function(ctx)
    return store.globalVariables[ctx.vars.name]
  end)
  add("POST/globalVariables", function(ctx)
    local data = dflts('globalVariables',ctx.data)
    store.globalVariables[ctx.data.name or ".."] = {'POST',data}
    return {data,HTTP.CREATED}
  end)
  add("PUT/globalVariables/<name>", function(ctx)
    store.globalVariables[ctx.vars.name] = {'PUT',ctx.data}
  end)
  add("DELETE/globalVariables/<name>", function(ctx)
    store.globalVariables[ctx.vars.name] = {'DELETE'}
  end)
  
  add("GET/rooms", function(ctx)
    return {strip(store.rooms),HTTP.OK}
  end)
  add("GET/rooms/<id>", function(ctx)
    return store.rooms[ctx.vars.id]
  end)
  add("POST/rooms", function(ctx)
    local data = dflts('rooms',ctx.data)
    store.rooms[ctx.vars.id] = {'POST',data}
    return {data,HTTP.CREATED}
  end)
  add("PUT/rooms/<id>", function(ctx)
    store.rooms[ctx.vars.id] = {'PUT',ctx.data}
  end)
  add("DELETE/rooms/<id>", function(ctx)
    store.rooms[ctx.vars.id] = {'DELETE'}
  end)
  
  add("GET/sections", function(ctx)
    return {strip(store.sections),HTTP.OK}
  end)
  add("GET/sections/<id>", function(ctx)
    return store.sections[ctx.vars.id]
  end)
  add("POST/sections", function(ctx)
    local data = dflts('sections',ctx.data)
    store.sections[ctx.vars.id] = {'POST',data}
    return {data,HTTP.CREATED}
  end)
  add("PUT/sections/<id>", function(ctx)
    store.sections[ctx.vars.id] = {'PUT',ctx.data}
  end)
  add("DELETE/sections/<id>", function(ctx)
    store.sections[ctx.vars.id] = {'DELETE'}
  end)
  
  add("GET/customEvents", function(ctx)
    return {strip(store.customEvents),HTTP.OK}
  end)
  add("GET/customEvents/<name>", function(ctx)
    return store.customEvents[ctx.vars.name]
  end)
  add("POST/customEvents", function(ctx)
    local data = dflts('customEvents',ctx.data)
    store.customEvents[ctx.vars.name] = {'POST',data}
    return {data,HTTP.CREATED}
  end)
  add("POST/customEvents", function(ctx)
    store.customEvents[ctx.vars.name] = {'POST',ctx.data}
  end)
  add("PUT/customEvents/<name>", function(ctx)
    store.customEvents[ctx.vars.name] = {'PUT',ctx.data}
  end)
  add("DELETE/customEvents/<name>", function(ctx)
    store.customEvents[ctx.vars.name] = {'DELETE'}
  end)
  
end







return setup