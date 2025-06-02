local exports = {}
local copas = require("copas")
local socket = require("socket")
local fmt = string.format

local function urldecode(str) 
  return str and str:gsub('%%(%x%x)',function(x)
    return string.char(tonumber(x, 16)) 
  end)
end

local commands = {}
-- function commands.install(params,_)
--   if E.config[params.cmd] then E.config[params.cmd](params) end
-- end

function commands.getDeviceStructure(params,io)
  local id = tonumber(params.id)
  if not id then
    io.write("HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: 36\r\n\r\n{\"error\":\"Invalid device ID parameter\"}")
    return true
  end
  local device = Emu.devices[id].device
  if not device then
    io.write("HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nContent-Length: 30\r\n\r\n{\"error\":\"Device not found\"}")
    return true
  end
  local structure = json.encodeFormated(device)
  io.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: "..(#structure).."\r\n\r\n"..structure)
  return true
end

function commands.getLocal(params,io)
  local path = urldecode(params.path)
  local content = nil
  if params.type and params.type == 'rsrc' then
    content = Emu.config.readRsrcsFile(path)
  else
    local f = io.open(path,"r")
    if f then content = f:read("*a") f:close() end
  end
  if content then
    io.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: "..(#content).."\r\n\r\n"..content)
    return true
  else
    Emu:ERRORF("Failed to open file for reading: %s",params.path)
  end
end

local function parseUrl(url)
  local path,query = url:match("([^%?]+)%?(.*)")
  if path==nil then path = url query = "" end
  local qs = query:split("&")
  local params = {}
  for _,p in ipairs(qs) do
    local k,v = p:match("([^=]+)=(.*)")
    if k == 'selectedOptions' then 
      params[k] = params[k] or {}
      table.insert(params[k],v)
    else params[k] = tonumber(v) or v end
  end
  if path:sub(1,1) == '/' then path = path:sub(2) end
  return path,params
end

local embed = require("hc3emu2.embedui")

local function handleGET(url,headers,io)
  local path,params = parseUrl(url)
  if path=="multi" then params.selectedOptions = params.selectedOptions or {} end
  --print(path,json.encode(params))
  if commands[path] then
    return commands[path](params,io)
  end
  if params.qa then
    local device = Emu.devices[params.qa].device
    if device then
      local typ = ({button='onReleased',switch='onReleased',slider='onChanged',select='onToggled',multi='onToggled'})[path]
      if params.id:sub(1,2)=="__" then -- special embedded UI element
        if embed.embedHooks[params.id] then
          embed.embedHooks[params.id]({device=device},params)
        end
        --qa:embedPatch(params)
        local actionName = params.id:sub(3)
        local args = {
          deviceId=device.id,
          actionName=actionName,
          args={params.value or params.selectedOptions or params.state=='on' or nil}
        }
        if device.isChild then device = Emu.devices[device.parentId].device end
        local env = Emu.devices[device.id].env
        return env.onAction(device.id,args)
      end
      local args = {
        deviceId=device.id,
        elementName=params.id,
        eventType=typ,
        values={params.value or params.selectedOptions or params.state=='on'}
      }
      if device.isChild then device = Emu.devices[device.parentId].device end
      local env = Emu.devices[device.id].env
      env.onUIEvent(device.id,args)
    end
  end
end

local function handlePOST(url,headers,io)
  local path,params = parseUrl(url)
  local len = 0
  for _,header in ipairs(headers) do
    len = header:match("Content%-Length: (%d+)")
    if len then len = tonumber(len) or 0 break end
  end
  local data = io.read(len)
  if commands[path] then
    commands[path](data,params,io)
  end
  io.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\n\r\n")
  return true
end

-- CORS control from client - answer yes...
local function handleOPTIONS(path,headers,io)
  local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
  io.write(
  "HTTP/1.1 200 OK\r\nDate: " .. date .. "\r\nServer: Apache/2.0.61 (Unix)\r\nAccess-Control-Allow-Origin:*\r\nAccess-Control-Allow-Methods: POST, GET, OPTIONS\r\nAccess-Control-Allow-Headers:X-PINGOTHER, Content-Type\r\n\r\n")
  return true
end

WebServer = WebServer
class 'WebServer'(SocketServer) 
function WebServer:__init(ip,port) 
  SocketServer.__init(self,ip,port,Emu.IP)
  self.api = API(Emu)
end

function WebServer:handler(io)
  local request = io.read()
  local headers = {}
  while true do
    local header = io.read()
    headers[#headers+1] = header
    if header == "" then
      local method,path = request:match("([^%s]+) ([^%s]+)")

      if method == 'GET' and handleGET(path,headers,io) then
        self.api:call(method,path)
        break
      end
      if method == "OPTIONS" then 
        handleOPTIONS(path,headers,io) break 
      end
      if method == "POST" then 
        handlePOST(path,headers,io) break
      end
      io.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nAccess-Control-Allow-Origin: *\r\n\r\n")
      break
    end
  end
end

return exports