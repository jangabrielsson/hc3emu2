local fmt = string.format

API = API
class 'API'
API.HTTP = {
  OK=200, CREATED=201, ACCEPTED=202, NO_CONTENT=204,MOVED_PERMANENTLY=301, FOUND=302, NOT_MODIFIED=304,
  BAD_REQUEST=400, UNAUTHORIZED=401, FORBIDDEN=403, NOT_FOUND=404,METHOD_NOT_ALLOWED=405, NOT_ACCEPTABLE=406,
  PROXY_AUTHENTICATION_REQUIRED=407, REQUEST_TIMEOUT=408, CONFLICT=409, GONE=410, LENGTH_REQUIRED=411,
  INTERNAL_SERVER_ERROR=500, NOT_IMPLEMENTED=501
}

function API:__init(emu)
  self.emu = emu
  self.DIR = { GET={}, POST={}, PUT={}, DELETE={} }
end

local converts = {
  ['<id>'] = function(v) return tonumber(v) end,
  ['<name>'] = function(v) return v end,
}

function API:add(...)
  local args = {...}
  local method,path,handler,force = args[1],args[2],args[3],args[4]
  if type(path) == 'function' then -- shift args
    method,handler,force = args[1],args[2],args[3] 
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
  assert(force==true or d._handler == nil,fmt("Duplicate path: %s/%s",method,path))
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


EMUAPI = EMUAPI
class 'EMUAPI'(API)

function EMUAPI:__init(emu)
  API.__init(self,emu)
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
    return nil,self.HTTP.BAD_REQUEST
  end
  hc3.restricted = {}
  function hc3.restricted.get(path) return syncCall("GET",path) end
  function hc3.restricted.post(path,data) return syncCall("POST",path,data) end
  function hc3.restricted.put(path,data) return syncCall("PUT",path,data) end
  function hc3.restricted.delete(path) return syncCall("DELETE",path) end

  self:setupRoutes()
end

local function logError(method, path, code)
  local err = string.format("api Error %s %s: %s",method,path,code)
  Emu:WARNINGF('api',err)
end

function EMUAPI:call(method, path, data, silent) 
  local handler, vars, query = self:getRoute(method, path)
  local res,code,headers = nil,self.HTTP.NOT_IMPLEMENTED,nil
  if handler then
    res,code,headers = handler({method=method, path=path, data=data, vars=vars, query=query})
  elseif not self.emu.offline then
    res,code,headers = self.emu:HC3Call(method, path, data)
  end
  if not tonumber(code) or code > self.HTTP.NO_CONTENT and not silent then logError(method,path,code) end
  return res,code,headers
end

------------------- Routes --------------------- 

function EMUAPI:setupRoutes()
  local hc3 = self.hc3
  local emu = self.emu
  local devices = self.emu.devices
  local HTTP = self.HTTP

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
    local res = indexMap(devs,'id')
    for id,dev in pairs(devices) do
      res[id] = res[id] or dev.device
    end
    return filter(ctx.query, res),HTTP.OK
  end)
  self:add("GET/devices/<id>",function(ctx)
    if devices[ctx.vars.id] then
      return devices[ctx.vars.id].device,HTTP.OK
    elseif emu.offline then
      return nil,HTTP.NOT_FOUND
    else
      return hc3.get(ctx.path)
    end
  end)
  self:add("GET/devices/<id>/properties/<name>",function(ctx)
    local id,name = ctx.vars.id,ctx.vars.name
    if id == 1 and (name == "sunriseHour" or name == "sunsetHour") then
      return {value=emu[name],modified=0},HTTP.OK
    end
    local dev = devices[id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.get(ctx.path) end end
    return {value=dev.device.properties[name],modified=0},HTTP.OK
  end)

  self:add("POST/devices/<id>/action/<name>",function(ctx)
    local id = ctx.vars.id
    local dev = devices[id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.post(ctx.path,ctx.data) end
    else
      emu:process{
        pi=dev.env._PI,
        fun=function()
          dev.env.onAction(id,{ deviceId = id, actionName = ctx.vars.name, args = ctx.data.args })
        end
      }
      emu:sleep(0.01)
      return nil,HTTP.OK
    end
  end)

 self:add("GET/devices/<id>/action/<name>",function(ctx)
   local id = ctx.vars.id
    local dev = devices[id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.get(ctx.path,ctx.data) end
    else
      local action = ctx.vars.name
      local data,args = {},{}
      for k,v in pairs(ctx.query) do data[#data+1] = {k,v} end
      table.sort(data,function(a,b) return a[1] < b[1] end)
      for _,d in ipairs(data) do args[#args+1] = d[2] end
      emu:process{
        pi=dev.env._PI,
        fun=function()
          dev.env.onAction(id,{ deviceId = id, actionName = action, args =args})
        end
      }
      emu:sleep(0.01)
      return nil,HTTP.OK
    end
  end)

  self:add("PUT/devices/<id>",function(ctx)
  end)

  self:add("DELETE/devices/<id>",function(ctx) 
    local id = ctx.vars.id
    local dev = devices[id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.delete(ctx.path) end 
    elseif not dev.device.isChild then
      dev.env._PI:cancelTimers()
      devices[id] = nil                   -- Kill QA entry
      for cid,_ in pairs(devices) do
        if devices[cid].device.parentId == id then
          devices[cid] = nil              -- Kill child entry
        end
      end
      return nil,HTTP.OK
    else return nil,HTTP.NOT_IMPLEMENTED end
  end)

  self:add("POST/plugins/updateProperty",function(ctx)
    local id = ctx.data.deviceId
    local dev = devices[id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.post(ctx.path,ctx.data) end
    else
      local prop = ctx.data.propertyName
      local value = ctx.data.value
      if dev.device.properties[prop] ~= value then
        -- Generate refreshState event
        if not dev.device.isProxy then
          emu:refreshEvent('DevicePropertyUpdatedEvent',{
            deviceId = id,
            propertyName = prop,
            newValue = value,
          })
      end
        dev:watching(prop,value)
      end
      dev.device.properties[prop] = value
      if dev.device.isProxy then return hc3.post("/plugins/updateProperty",ctx.data) end
      return nil,HTTP.OK
    end
  end)

  self:add("POST/plugins/updateView",function(ctx)
    local dev = devices[ctx.data.deviceId]
    if not dev then return hc3.post(ctx.path,ctx.data) end
    local data = ctx.data
    dev:updateView(data.componentName,ctx.data.propertyName,ctx.data.newValue)
    if dev.device.isProxy then return hc3.post(ctx.path,ctx.data)
    else return nil,HTTP.OK end
  end)

  self:add("POST/plugins/interfaces",function(ctx)
  end)

  self:add("POST/plugins/restart",function(ctx)
    local id = tonumber(ctx.data.deviceId)
    local dev = devices[id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.post(ctx.path,ctx.data) end
    elseif not dev.device.isChild then
      dev.env._PI:cancelTimers()
      dev:startQA()
      return nil,HTTP.OK
    else return nil,HTTP.NOT_IMPLEMENTED end
  end)

  self:add("POST/plugins/createChildDevice",function(ctx)
    local data = ctx.data
    local parent = data.parentId
    local dev = devices[parent]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.post(ctx.path,data) end end
    if dev.device.isProxy then
      local res = hc3.post(ctx.path,ctx.data) -- create child on HC3
      res.isProxy = true
      data = res
    end
    data.isChild = true
    headers = { webUI = dev.headers.webUI }
    if data.initialProperties and data.initialProperties.uiView then
      local uiView = data.initialProperties.uiView
      local callbacks = data.initialProperties.uiCallbacks or {}
      headers.UI = Emu.lib.ui.uiView2UI(uiView,callbacks)
    end
    return emu:installDevice(data,{},headers),HTTP.OK
  end)

  self:add("DELETE/plugins/removeChildDevice/<id>",function(ctx)
    local id = ctx.vars.id
    local dev = devices[id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.delete(ctx.path) end
    elseif dev.device.isChild then
      devices[id] = nil
      return nil,HTTP.OK
    else return nil,HTTP.NOT_IMPLEMENTED end
  end)
  
  local function findFile(name,files)
    for i,f in ipairs(files) do if f.name == name then return f,i end end
  end

  self:add("GET/quickApp/<id>/files",function(ctx) 
    local dev = devices[ctx.vars.id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.get(ctx.path) end end
    local files = table.copy(dev.files)
    for _,f in ipairs(files) do
      f.fname,f.isOpen,f.type = nil,false,"lua"
      if f.isMain == nil then f.isMain = f.name == 'main' end
    end
    return files,HTTP.OK
  end)

  self:add("POST/quickApp/<id>/files",function(ctx) 
    local dev = devices[ctx.vars.id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.get(ctx.path) end end
    local files = dev.files
    if findFile(ctx.data.name,files) then return nil,HTTP.CONFLICT end
    files[#files+1] = ctx.data
    self.post("/plugins/restart", { deviceId = ctx.vars.id })
    return nil,HTTP.CREATED
  end)

  self:add("GET/quickApp/<id>/files/<name>",function(ctx) 
    local dev = devices[ctx.vars.id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.get(ctx.path) end end
    local files = dev.files
    local f =  findFile(ctx.data.name,files)
    if f then return f,HTTP.OK else return nil,HTTP.NOT_FOUND end
  end)

  self:add("PUT/quickApp/<id>/files/<name>",function(ctx)
    local dev = devices[ctx.vars.id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.get(ctx.path) end end
    local files = dev.files
    local f = findFile(ctx.data.name,files)
    if not f then return nil,HTTP.NOT_FOUND
    else
      f.content = ctx.data.content
      self.post("/plugins/restart", { deviceId = ctx.vars.id })
      return nil,HTTP.OK
    end
  end)

  self:add("PUT/quickApp/<id>/files",function(ctx)
    local dev = devices[ctx.vars.id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.get(ctx.path) end end
    local files = table.copy(dev.files)
    for _,f in ipairs(ctx.data) do
      local f0 = findFile(f.name,files)
      if not f0 then return nil,HTTP.NOT_FOUND end
      f0.content = f.content
    end
    devices[ctx.vars.id].files = files
    self.post("/plugins/restart", { deviceId = ctx.vars.id })
    return nil,HTTP.OK
  end)

  self:add("DELETE/quickApp/<id>/files/<name>",function(ctx) 
    local dev = devices[ctx.vars.id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.get(ctx.path) end end
    local files = dev.files
    local f,i =  findFile(ctx.data.name,files)
    if not f then return nil,HTTP.NOT_FOUND
    elseif f.name == 'main' then return nil,HTTP.FORBIDDEN
    else 
      table.remove(files,i)
      self.post("/plugins/restart", { deviceId = ctx.vars.id })
      return nil,HTTP.OK
    end
  end)

  self:add("GET/quickApp/export/<id>",function(ctx)
    local dev = devices[ctx.vars.id]
    if not dev then if emu.offline then return nil,HTTP.NOT_FOUND else return hc3.get(ctx.path) end end
    local initProps = {}
    local savedProps = {
      "uiCallbacks","quickAppVariables","uiView","viewLayout","apiVersion","useEmbededView",
      "manufacturer","useUiView","model","buildNumber","supportedDeviceRoles",
      "userDescription","typeTemplateInitialized","quickAppUuid","deviceRole"
    }
    for _,k in ipairs(savedProps) do initProps[k]=dev.device.properties[k] end
    local files = self.get("/quickApp/"..ctx.vars.id.."/files")
    local fqa = {
      apiVersion = "1.3",
      name = dev.device.name,
      type = dev.device.type,
      initialProperties = initProps,
      initialInterfaces = dev.device.interfaces,
      files = files,
    }
    return fqa,HTTP.OK
  end)

  self:add("POST/quickApp/",function(ctx) 
    local dev = emu:installFQA(ctx.data)
    if dev then return dev,HTTP.CREATED else return nil,HTTP.UNAUTHORIZED end
  end)

  local function isLocal(id)
    local dev = devices[id]
    if not dev then return false end
    return not dev.device.isProxy
  end
  
  -- These we run via emuHelper and hc3.restricted.* because they are not allowed remotely

  self:add("GET/plugins/<id>/variables",function(ctx) 
    if isLocal(ctx.vars.id) then
      local vars,res = devices[ctx.vars.id].vars or {},{}
      for k,v in pairs(vars) do res[#res+1] = { name=k, value=v } end
      return res,HTTP.OK
    end
    return hc3.restricted.get(ctx.path)
  end)
  self:add("GET/plugins/<id>/variables/<name>",function(ctx) 
    if isLocal(ctx.vars.id) then
      local value = (devices[ctx.vars.id].vars or {})[ctx.vars.name]
      if value~=nil then return { name=ctx.vars.name, value=value },HTTP.OK
      else return nil,HTTP.NOT_FOUND end
    end
    return hc3.restricted.get(ctx.path)
  end)
  self:add("POST/plugins/<id>/variables",function(ctx) 
    if isLocal(ctx.vars.id) then
      devices[ctx.vars.id].vars = devices[ctx.vars.id].vars or {}
      local var = devices[ctx.vars.id].vars[ctx.vars.name]
      if var then return nil,HTTP.CONFLICT
      else devices[ctx.vars.id].vars[ctx.data.name] = ctx.data.value emu:saveState() return nil,HTTP.CREATED end
    end
    return hc3.restricted.post(ctx.path,ctx.data)
  end)
  self:add("PUT/plugins/<id>/variables/<name>",function(ctx) 
    if isLocal(ctx.vars.id) then
      local value = (devices[ctx.vars.id].vars or {})[ctx.vars.name]
      if value~=nil then devices[ctx.vars.id].vars[ctx.vars.name] = ctx.data.value emu:saveState() return nil,HTTP.OK
      else return nil,HTTP.NOT_FOUND end
    end
    return hc3.restricted.put(ctx.path,ctx.data)
  end)
  self:add("DELETE/plugins/<id>/variables/<name>",function(ctx) 
    if isLocal(ctx.vars.id) then
      local var = (devices[ctx.vars.id].vars or {})[ctx.vars.name]
      if var~=nil then devices[ctx.vars.id].vars[ctx.vars.name] = nil emu:saveState() return nil,HTTP.OK
      else return nil,HTTP.NOT_FOUND end
    end
    return hc3.restricted.delete(ctx.path,ctx.data)
  end)
  self:add("DELETE/plugins/<id>/variables",function(ctx) 
    if isLocal(ctx.vars.id) then
      devices[ctx.vars.id].vars = {}
      emu:saveState()
      return nil,HTTP.OK
    end
    return hc3.restricted.delete(ctx.path,ctx.data)
  end)

end

return EMUAPI