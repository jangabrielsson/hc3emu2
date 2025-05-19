local fmt = string.format

API = API
class 'API'
function API:__init(emu)
  self.emu = emu
  self.DIR = { GET={}, POST={}, PUT={}, DELETE={} }
  function self.get(path,silent) return self:call("GET",path,nil,silent) end
  function self.post(path,data,silent) return self:call("POST",path,data,silent) end
  function self.put(path,data,silent) return self:call("PUT",path,data,silent) end
  function self.delete(path,data,silent) return self:call("DELETE",path,data,silent) end

  self.hc3 = {}
  local hc3 = self.hc3
  function hc3.get(path,silent) return emu:HC3Call("GET",path,nil,silent) end
  function hc3.post(path,data,silent) return emu:HC3Call("POST",path,data,silent) end
  function hc3.put(path,data,silent) return emu:HC3Call("PUT",path,data,silent) end
  function hc3.delete(path,data,silent) return emu:HC3Call("DELETE",path,data,silent) end

  local seqID = 0
  local function syncCall(method,path,data)
    if not emu.helper then return nil,501 end
    local req = json.encode({method=method,path=path,data=data or {},seqID=seqID}).."\n"
    seqID = seqID + 1
    local resp = emu.helper.connection:send(req)
    if resp then
      local data = json.decode(resp)
      local res,code = table.unpack(data)
      if res == json.null then res = nil end
      Emu:DEBUGF('http',"HTTP %s %s %s",method,path,code)
      return res,code
    end
    return nil,404
  end
  hc3.restricted = {}
  function hc3.restricted.get(path) return syncCall("GET",path) end
  function hc3.restricted.post(path,data) return syncCall("POST",path,data) end
  function hc3.restricted.put(path,data) return syncCall("PUT",path,data) end
  function hc3.restricted.delete(path) return syncCall("DELETE",path) end

  self:setupRoutes()
end

local converts = {
  ['<id>'] = function(v) return tonumber(v) end,
  ['<name>'] = function(v) return v end,
}

function API:add(method, path, handler)
  if type(path) == 'function' then -- shift args
    handler = path 
    method,path = method:match("(.-)(/.+)") -- split method and path
  end
  local path = string.split(path,'/')
  local d = self.DIR[method:upper()]
  for _,p in ipairs(path) do
    local p0 = p
    p = ({['<id>']=true,['<name>']=true})[p] and '_match' or p
    local d0 = d[p]
    if d0 == nil then d[p] = {} end
    if p == '_match' then d._fun = converts[p0] d._var = p0:sub(2,-2) end
    d = d[p]
  end
  assert(d._handler == nil,fmt("Duplicate path: %s/%s",method,path))
  d._handler = handler
end

local urldecode = function(url)
  return (url:gsub("%%(%x%x)", function(x) return string.char(tonumber(x, 16)) end))
end

local function parseQuery(queryStr)
  local params = {}
  local query = urldecode(queryStr)
  local p = query:split("&")
  for _,v in ipairs(p) do
    local k,v = v:match("(.-)=(.*)")
    params[k] = tonumber(v) or v
  end
  return params
end

function API:getRoute(method,path)
  local pathStr,queryStr = path:match("(.-)%?(.*)") 
  path = pathStr or path
  local query = queryStr and parseQuery(queryStr) or {}
  local path = string.split(path,'/')
  local d,vars = self.DIR[method:upper()],{}
  for _,p in ipairs(path) do
    if d._match and not d[p] then 
      local v = d._fun(p)
      if v == nil then return nil,vars end
      vars[d._var] =v 
      p = '_match'
    end
    local d0 = d[p]
    if d0 == nil then return nil,vars end
    d = d0
  end
  return d._handler,vars,query
end

local function logError(silent, method, path, res, code, headers)
  if code > 206 and not silent then
    local err = string.format("api Error %s %s: %s",method,path,code)
    print(err)
  end
  return res,code,headers
end

function API:call(method, path, data, silent) 
  local handler, vars, query = self:getRoute(method, path)
  if not handler then
    if self.emu.offline then 
      return nil,501
    end
    return logError(silent,method, path, self.emu:HC3Call(method, path, data))
  end
  return logError(silent, method, path, handler({method=method, path=path, data=data, vars=vars, query=query}))
end

------------------- Routes --------------------- 

function API:setupRoutes()
  local hc3 = self.hc3
  local emu = self.emu
  local qas = self.emu.qas

  local filterkeys = {
    parentId=function(d,v) return tonumber(d.parentId) == tonumber(v) end,
    name=function(d,v) return d.name == v end,
    type=function(d,v) return d.type == v end,
    enabled=function(d,v) return tostring(d.enabled) == tostring(v) end,
    visible=function(d,v) return tostring(d.visible) == tostring(v) end,
    roomID=function(d,v) return tonumber(d.roomID) == tonumber(v) end,
    interface=function(d,v)
      local ifs = d.interfaces
      for _,i in ipairs(ifs) do if i == v then return true end end
    end,
    property=function(d,v)
      local prop,val = v:match("%[([^,]+),(.+)%]")
      if not prop then return false end
      return tostring(d.properties[prop]) == tostring(val)
    end,
  }
  
  -- local var = api.get("/devices?property=[lastLoggedUser,"..val.."]") 
  local function filter1(q,d)
    for k,v in pairs(q) do 
      if not(filterkeys[k] and filterkeys[k](d,v)) then return false end 
    end
    return true
  end
  
  local function filter(q,ds)
    local r = {}
    for _,d in pairs(ds) do if filter1(q,d) then r[#r+1] = d end end
    return r
  end
  
  local function indexMap(t,key) local r = {} for _,v in ipairs(t) do r[v[key]] = v end return r end

  self:add("GET/devices",function(ctx)
    local devs = emu.offline and {} or hc3.get(ctx.path)
    local devices = indexMap(devs,'id')
    for id,dev in pairs(qas.devices) do
      devices[id] = devices[id] or dev
    end
    return filter(ctx.query, devices),200
  end)
  self:add("GET/devices/<id>",function(ctx)
    if qas.devices[ctx.vars.id] then
      return qas.devices[ctx.vars.id],200
    elseif emu.offline then
      return nil,404
    else
      return hc3.get(ctx.path)
    end
  end)
  self:add("GET/devices/<id>/properties/<name>",function(ctx)
    local dev = qas.devices[ctx.vars.id]
    if not dev then if emu.offline then return nil,404 else return hc3.get(ctx.path) end end
    return dev.properties[ctx.vars.name],200
  end)

  self:add("POST/devices/<id>/action/<name>",function(ctx)
    local id = ctx.vars.id
    local env = qas.envs[id]
    if not env then if emu.offline then return nil,404 else return hc3.post(ctx.path,ctx.data) end
    else
      emu:process{
        pi=env._PI,
        fun=function()
          env.onAction(id,{ deviceId = id, actionName = ctx.vars.name, args = ctx.data.args })
        end
      }
      return nil,200
    end
  end)

  self:add("GET/devices/<id>/action/<name>",function(ctx)
  end)

  self:add("PUT/devices/<id>",function(ctx)
  end)

  self:add("DELETE/devices/<id>",function(ctx) 
    local id = ctx.vars.id
    local env = qas.envs[id]
    local dev = qas.devices[id]
    if not dev then if emu.offline then return nil,404 else return hc3.delete(ctx.path) end 
    elseif not dev.isChild then
      env._PI:cancelTimers()
      qas.devices[id] = nil
      for cid,_ in pairs(qas.devices) do
        if qas.devices[cid].parentId == id then
          qas.devices[cid] = nil
        end
      end
      return nil,200
    else return nil,501 end
  end)

  self:add("POST/plugins/updateProperty",function(ctx)
    local id = ctx.data.deviceId
    local dev = qas.devices[id]
    if not dev then if emu.offline then return nil,404 else return hc3.post(ctx.path,ctx.data) end
    else
      local prop = ctx.data.propertyName
      local value = ctx.data.value
      if dev.properties[prop] ~= value then
        -- Generate refreshState event
      end
      dev.properties[prop] = value
      if dev.isProxy then return hc3.post("/plugins/updateProperty",ctx.data) end
      return nil,200
    end
  end)

  self:add("POST/plugins/updateView",function(ctx)
    local id = ctx.data.deviceId
    local dev = qas.devices[id]
    if not dev or dev.isProxy then return hc3.post(ctx.path,ctx.data) end
    return nil,200
  end)

  self:add("POST/plugins/interfaces",function(ctx)
  end)

  self:add("POST/plugins/restart",function(ctx)
    local id = tonumber(ctx.data.deviceId)
    local env = qas.envs[id]
    local dev = qas.devices[id]
    if not dev then if emu.offline then return nil,404 else return hc3.post(ctx.path,ctx.data) end
    elseif not dev.isChild then
      env._PI:cancelTimers()
      emu:startQA(id)
      return nil,200
    else return nil,501 end
  end)

  self:add("POST/plugins/createChildDevice",function(ctx)
    local data = ctx.data
    local parent = data.parentId
    local dev = qas.devices[parent]
    if not dev then if emu.offline then return nil,404 else return hc3.post(ctx.path,data) end end
    if dev.isProxy then
      local res = hc3.post(ctx.path,ctx.data) -- create child on HC3
      res.isProxy = true
      data = res
    end
    data.isChild = true
    return emu:installDevice(data),200
  end)

  self:add("DELETE/plugins/removeChildDevice/<id>",function(ctx)
    local id = ctx.vars.id
    local dev = qas.devices[id]
    if not dev then if emu.offline then return nil,404 else return hc3.delete(ctx.path) end
    elseif self.isChild then
      qas.devices[id] = nil
      return nil,200
    else return nil,501 end
  end)
  
  local function findFile(name,files)
    for i,f in ipairs(files) do if f.name == name then return f,i end end
  end

  self:add("GET/quickApp/<id>/files",function(ctx) 
    local files = table.copy(qas.files[ctx.vars.id])
    if not files then if emu.offline then return nil,404 else return hc3.get(ctx.path) end end
    for _,f in ipairs(files) do
      f.fname,f.isOpen,f.type = nil,false,"lua"
      if f.isMain == nil then f.isMain = f.name == 'main' end
    end
    return files,200
  end)

  self:add("POST/quickApp/<id>/files",function(ctx) 
    local files = qas.files[ctx.vars.id]
    if not files then if emu.offline then return nil,404 else return hc3.get(ctx.path) end end
    if findFile(ctx.data.name,files) then return nil,409 end
    files[#files+1] = ctx.data
    self.post("/plugins/restart", { deviceId = ctx.vars.id })
    return nil,201
  end)

  self:add("GET/quickApp/<id>/files/<name>",function(ctx) 
    local files = qas.files[ctx.vars.id]
    if not files then if emu.offline then return nil,404 else return hc3.get(ctx.path) end end
    local f =  findFile(ctx.data.name,files)
    if f then return f,200 else return nil,404 end
  end)

  self:add("PUT/quickApp/<id>/files/<name>",function(ctx)
    local files = qas.files[ctx.vars.id]
    if not files then if emu.offline then return nil,404 else return hc3.get(ctx.path) end end
    local f = findFile(ctx.data.name,files)
    if not f then return nil,404
    else
      f.content = ctx.data.content
      self.post("/plugins/restart", { deviceId = ctx.vars.id })
      return nil,200
    end
  end)

  self:add("PUT/quickApp/<id>/files",function(ctx)
    local files = table.copy(qas.files[ctx.vars.id])
    if not files then if emu.offline then return nil,404 else return hc3.get(ctx.path) end end
    for _,f in ipairs(ctx.data) do
      local f0 = findFile(f.name,files)
      if not f0 then return nil,404 end
      f0.content = f.content
    end
    qas.files[ctx.vars.id] = files
    self.post("/plugins/restart", { deviceId = ctx.vars.id })
    return nil,201
  end)

  self:add("DELETE/quickApp/<id>/files/<name>",function(ctx) 
    local files = qas.files[ctx.vars.id]
    if not files then if emu.offline then return nil,404 else return hc3.get(ctx.path) end end
    local f,i =  findFile(ctx.data.name,files)
    if not f then return nil,404 
    elseif f.name == 'main' then return nil,505
    else 
      table.remove(files,i)
      self.post("/plugins/restart", { deviceId = ctx.vars.id })
      return nil,200
    end
  end)

  self:add("GET/quickApp/export/<id>",function(ctx)
    local dev = qas.devices[ctx.vars.id]
    if not dev then if emu.offline then return nil,404 else return hc3.get(ctx.path) end end
    local initProps = {}
    local savedProps = {
      "uiCallbacks","quickAppVariables","uiView","viewLayout","apiVersion","useEmbededView",
      "manufacturer","useUiView","model","buildNumber","supportedDeviceRoles",
      "userDescription","typeTemplateInitialized","quickAppUuid","deviceRole"
    }
    for _,k in ipairs(savedProps) do initProps[k]=dev.properties[k] end
    local files = self.get("/quickApp/"..ctx.vars.id.."/files")
    local fqa = {
      apiVersion = "1.3",
      name = dev.name,
      type = dev.type,
      initialProperties = initProps,
      initialInterfaces = dev.interfaces,
      files = files,
    }
    return fqa,200
  end)

  self:add("POST/quickApp/",function(ctx) 
    local dev = emu:installFQA(ctx.data)
    if dev then return dev,201 else return nil,401 end
  end)
  
  local function isLocal(id)
    local dev = qas.devices[id]
    if not dev then return false end
    return not dev.isProxy
  end
  
  -- These we run via emuHelper and hc3.restricted.* because they are not allowed remotely

  self:add("GET/plugins/<id>/variables",function(ctx) 
    if isLocal(ctx.vars.id) then
      local vars,res = qas.vars[ctx.vars.id] or {},{}
      for k,v in pairs(vars) do res[#res+1] = { name=k, value=v } end
      return res,200
    end
    return hc3.restricted.get(ctx.path)
  end)
  self:add("GET/plugins/<id>/variables/<name>",function(ctx) 
    if isLocal(ctx.vars.id) then
      local value = (qas.vars[ctx.vars.id] or {})[ctx.vars.name]
      if value~=nil then return { name=ctx.vars.name, value=value },200
      else return nil,404 end
    end
    return hc3.restricted.get(ctx.path)
  end)
  self:add("POST/plugins/<id>/variables",function(ctx) 
    if isLocal(ctx.vars.id) then
      qas.vars[ctx.vars.id] = qas.vars[ctx.vars.id] or {}
      local var = qas.vars[ctx.vars.id][ctx.vars.name]
      if var then return nil,409
      else qas.vars[ctx.vars.id][ctx.data.name] = ctx.data.value emu:saveState() return nil,200 end
    end
    return hc3.restricted.post(ctx.path,ctx.data)
  end)
  self:add("PUT/plugins/<id>/variables/<name>",function(ctx) 
    if isLocal(ctx.vars.id) then
      local value = (qas.vars[ctx.vars.id] or {})[ctx.vars.name]
      if value~=nil then qas.vars[ctx.vars.id][ctx.vars.name] = ctx.data.value emu:saveState() return nil,200
      else return nil,404 end
    end
    return hc3.restricted.put(ctx.path,ctx.data)
  end)
  self:add("DELETE/plugins/<id>/variables/<name>",function(ctx) 
    if isLocal(ctx.vars.id) then
      local var = (qas.vars[ctx.vars.id] or {})[ctx.vars.name]
      if var~=nil then qas.vars[ctx.vars.id][ctx.vars.name] = nil emu:saveState() return nil,200
      else return nil,404 end
    end
    return hc3.restricted.delete(ctx.path,ctx.data)
  end)
  self:add("DELETE/plugins/<id>/variables",function(ctx) 
    if isLocal(ctx.vars.id) then
      qas.vars[ctx.vars.id] = {}
      emu:saveState()
      return nil,200
    end
    return hc3.restricted.delete(ctx.path,ctx.data)
  end)

end

return API