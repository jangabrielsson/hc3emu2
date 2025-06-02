local fmt = string.format
Emu = Emu
Device = Device
local start

-- Deploys a proxy QuickApp to the HC3 system 
-- @param name - The name for the proxy device
-- @param devTempl - The device template to use for creating the proxy
-- @return - The created device object from HC3
local function deployProxy(name,devTempl)
  -- The Lua code that will be installed on the HC3 proxy device
  -- This code creates a QuickApp that can communicate with the emulator
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
  
  -- Actions that are handled directly by the proxy rather than forwarded to the emulator
  local IGNORE={ MEMORYWATCH=true,APIFUN=true,CONNECT=true }
  
  -- Establishes connection settings for the proxy to communicate with the emulator
  -- @param con - Table containing connection parameters (ip, port)
  function quickApp:CONNECT(con)
    con = con or {}
    self:internalStorageSet("con",con)
    ip = con.ip
    port = con.port
    self:debug("Connected")
  end
  
  -- Handles actions called on the proxy device
  -- Either handles them locally (for special actions) or forwards them to the emulator
  -- @param action - Action data with actionName and args
  function quickApp:actionHandler(action)
    if IGNORE[action.actionName] then
      print(action.actionName)
      return quickApp:callAction(action.actionName, table.unpack(action.args))
    end
    send({deviceId=self.id,type='action',value=action})
  end
  
  -- Forwards UI events from HC3 to the emulator
  function quickApp:UIHandler(ev) send({type='ui',deviceId=self.id,value=ev}) end
  
  -- Executes API calls on the HC3 and sends back the results to the emulator
  -- @param id - Request ID for response correlation
  -- @param method - HTTP method (get, post, put, delete)
  -- @param path - API path to call
  -- @param data - Data payload for the API call
  function quickApp:APIFUN(id,method,path,data)
    local stat,res,code = pcall(api[method:lower()],path,data)
    send({type='resp',deviceId=self.id,id=id,value={stat,res,code}})
  end
  
  -- Override the initChildDevices function to prevent default behavior
  function quickApp:initChildDevices(_) end
  
  local queue = {}
  local sender = nil
  local connected = false
  local sock = nil
  local runSender
  
  -- Handles connection failures by resetting the connection and scheduling a retry
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

-- Creates a proxy device on the HC3 system
-- @param devTempl - The device template containing name, type and other properties
-- @return - The created proxy device or nil if creation failed
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

-- Finds and handles existing proxy devices on the HC3 system
-- If multiple proxies with the same name exist, it keeps only the newest one
-- @param d - The device object containing the name to search for
-- @param headers - Headers containing device type information
-- @return - The existing proxy device if found and valid, nil otherwise
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
    local dev = Device{ id=device.id, device=device, UI=ui, headers=headers }
    local children = Emu.api.hc3.get("/devices?parentId="..device.id) or {}
    for _,child in ipairs(children) do
      child.isProxy,child.isChild = true, true
      local ui = Emu.lib.ui.viewLayout2UI(
        child.properties.viewLayout,
        child.properties.uiCallbacks or {}
      )
      local cdev = Device{ id=child.id, device=child, UI=ui, headers=headers }
      Emu.devices[child.id] = cdev
      Emu:DEBUG("Existing Child proxy found: %s %s",child.id,child.name)
    end
    Emu:saveState()
    Emu.proxyId = device.id -- Just save the last proxy to be used for restricted API calls
    start()
    Emu.api.hc3.post("/devices/"..device.id.."/action/CONNECT",{args={{ip=Emu.config.pip,port=Emu.config.pport}}})
    return dev
  end
end

-- ProxyServer class for managing TCP socket communications between HC3 and the emulator
-- Extends the SocketServer class to handle incoming requests
SocketServer = SocketServer
ProxyServer = ProxyServer
class 'ProxyServer'(SocketServer)

-- Constructor initializes the TCP server with the specified IP and port
-- @param ip - IP address to bind to
-- @param port - Port number to listen on
function ProxyServer:__init(ip,port) SocketServer.__init(self,ip,port,Emu.PI,"server") end

-- Handles incoming connections and messages
-- @param io - I/O socket object for reading/writing data
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
-- Starts the proxy server if it's not already running
-- Uses the host and port configuration from the Emu config
function start() 
  if _proxyServer then return end
  _proxyServer = ProxyServer(Emu.config.phost,Emu.config.pport) 
  _proxyServer:start()
end

return {
  createProxy = createProxy,
  existingProxy = existingProxy,
}
