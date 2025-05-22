local fmt = string.format

local start

local function deployProxy(name,devTempl)
  local code = [[
local fmt = string.format
local con = nil
local ip,port = nil,nil
  
function QuickApp:onInit()
  self:debug("Started", self.name, self.id)
  quickApp = self
  con = self:internalStorageGet("con") or {}
  ip = con.ip
  port = con.port
  local send
  
  local IGNORE={ MEMORYWATCH=true,APIFUN=true,CONNECT=true }
  
  function quickApp:CONNECT(con)
    con = con or {}
    self:internalStorageSet("con",con)
    ip = con.ip
    port = con.port
    self:debug("Connected")
  end
  
  function quickApp:actionHandler(action)
    if IGNORE[action.actionName] then
      print(action.actionName)
      return quickApp:callAction(action.actionName, table.unpack(action.args))
    end
    send({deviceId=self.id,type='action',value=action})
  end
  
  function quickApp:UIHandler(ev) send({type='ui',deviceId=self.id,value=ev}) end
  
  function quickApp:APIFUN(id,method,path,data)
    local stat,res,code = pcall(api[method:lower()],path,data)
    send({type='resp',deviceId=self.id,id=id,value={stat,res,code}})
  end
  
  function quickApp:initChildDevices(_) end
  
  local queue = {}
  local sender = nil
  local connected = false
  local sock = nil
  local runSender
  
  local function retry()
    if sock then sock:close() end
    connected = false
    queue = {}
    sender = setTimeout(runSender,1500)
  end
  
  function runSender()
    if connected then
      if #queue>0 then
        sock:write(queue[1],{
          success = function() print("Sent",table.remove(queue,1)) runSender() end,
        })
      else sender = nil print("Sleeping") end
    else
      if not (ip and sender) then sender = setTimeout(runSender,1500) return end
      print("Connecting...")
      sock = net.TCPSocket()
      sock:connect(ip,port,{
        success = function(message)
          sock:read({
            succcess = retry,
            error = retry
          })
          print("Connected") connected = true runSender()
        end,
        error = retry
      })
    end
  end
  
  function send(msg)
    msg = json.encode(msg).."\n"
    queue[#queue+1]=msg
    if not sender then print("Starting") sender=setTimeout(runSender,0) end
  end
  
end
]]
  local props = {
    apiVersion = "1.3",
    quickAppVariables = devTempl.properties.quickAppVariables or {},
    viewLayout = devTempl.properties.viewLayout,
    uiView = devTempl.properties.uiView,
    uiCallbacks = devTempl.properties.uiCallbacks,
    useUiView=false,
    typeTemplateInitialized = true,
  }
  local fqa = {
    apiVersion = "1.3",
    name = name,
    type = devTempl.type,
    initialProperties = props,
    initialInterfaces = devTempl.interfaces,
    files = {{name="main", isMain=true, isOpen=false, type='lua', content=code}},
  }
  local res,code2 = Emu.lib.uploadFQA(fqa)
  return res
end

local function createProxy(devTempl) 
  local device = deployProxy(devTempl.name,devTempl)
  if not device then return Emu:ERRORF("Can't create proxy on HC3") end
  device.id = math.floor(device.id)
  Emu:DEBUG("Proxy installed: %s %s",device.id,devTempl.name)
  device.isProxy = true
  Emu.proxyId = device.id -- Just save the last proxy to be used for restricted API calls
  start()
  Emu.api.hc3.post("/devices/"..device.id.."/action/CONNECT",{args={{ip=Emu.config.pip,port=Emu.config.pport}}})
  return device
end

local function existingProxy(d,headers)
  local proxies = Emu.api.hc3.get("/devices?name="..urlencode(d.name.."_Proxy")) or {}
  if #proxies == 0 then return end
  table.sort(proxies,function(a,b) return a.id >= b.id end)
  for i = 2,#proxies do                        -- More than 1 proxy, delete older ones
    Emu:DEBUG("Old Proxy deleted: %s %s",proxies[i].id,proxies[i].name)
    Emu.api.hc3.delete("/devices/"..proxies[i].id)
  end
  local device = proxies[1]
  if proxies[1].type ~= headers.type then      -- Wrong type, delete and create new
    Emu:DEBUG("Existing Proxy of wrong type, deleted: %s %s",device.id,device.name)
    Emu.api.hc3.delete("/devices/"..proxies[1].id)
  else
    device.isProxy = true
    Emu:DEBUG("Existing Proxy found: %s %s",device.id,device.name)
    local ui = Emu.lib.ui.viewLayout2UI(
      device.properties.viewLayout,
      device.properties.uiCallbacks or {}
    )
    Emu:registerDevice{ id=device.id, device=device, UI=ui, headers=headers }
    local children = Emu.api.hc3.get("/devices?parentId="..device.id) or {}
    for _,child in ipairs(children) do
      child.isProxy,child.isChild = true, true
      local ui = Emu.lib.ui.viewLayout2UI(
        child.properties.viewLayout,
        child.properties.uiCallbacks or {}
      )
      Emu:registerDevice{ id=child.id, device=child, UI=ui, headers=headers }
      Emu:DEBUG("Existing Child proxy found: %s %s",child.id,child.name)
    end
    Emu:saveState()
    Emu.proxyId = device.id -- Just save the last proxy to be used for restricted API calls
    start()
    Emu.api.hc3.post("/devices/"..device.id.."/action/CONNECT",{args={{ip=Emu.config.pip,port=Emu.config.pport}}})
    Emu:post({type='device_created',id=device.id})
    for _,c in ipairs(children) do Emu:post({type='device_created',id=c.id}) end
    return device
  end
end

ProxyServer = ProxyServer
class 'ProxyServer'(SocketServer)
function ProxyServer:__init(ip,port) SocketServer.__init(self,ip,port,Emu.PI,"server") end
function ProxyServer:handler(io)
  while true do
    ---print("Waiting for data")
    local reqdata = io.read()
    if not reqdata then break end
    local stat,msg = pcall(json.decode,reqdata)
    if stat then
      local deviceId = msg.deviceId
      local QA = Emu.devices[deviceId].env
      if QA and msg.type == 'action' then QA.onAction(msg.value.deviceId,msg.value)
      elseif QA and msg.type == 'ui' then QA.onUIEvent(msg.value.deviceId,msg.value) end
    end
  end
end

local _proxyServer = nil
function start() 
  if _proxyServer then return end
  _proxyServer = ProxyServer(Emu.config.phost,Emu.config.pport) 
  _proxyServer:start()
end

return {
  createProxy = createProxy,
  existingProxy = existingProxy,
}
