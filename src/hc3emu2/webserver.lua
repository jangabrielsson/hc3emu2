local exports = {}
local copas = require("copas")
local socket = require("socket")
require("hc3emu2.class")
local fmt = string.format

local function urldecode(str) 
  return str and str:gsub('%%(%x%x)',function(x)
    return string.char(tonumber(x, 16)) 
  end)
end

local function renderPage(io, code, title, content)
  io.write(fmt("HTTP/1.1 %d OK\r\nContent-Type: text/html\r\n\r\n", code))
  io.write(fmt("<html><head><title>%s</title></head><body>", title))
  io.write(fmt("<h1>%s</h1>", title))
  io.write(content)
  io.write("</body></html>")
end

local function jsonData(io, code, data)
  io.write(fmt("HTTP/1.1 %d OK\r\nServer: HC3Emu\r\nContent-Type: application/json;charset=UTF-8\r\nDate: %s\r\nConnection: close\r\nCache-Control: no-cache\r\n\r\n", code, os.date("!%a, %d %b %Y %H:%M:%S GMT")))
  io.write(data)
end

local embed = require("hc3emu2.embedui")

local function handleUI(ctx,path)
  local params = ctx.query
  if path=="multi" then
    local selected = {}
    for k,v in pairs(params) do
      if k:match("^selectedOptions%d+$") then
        selected[#selected+1] = v
      end
    end
    params.selectedOptions = selected 
  end
  if params.qa then
    local device = Emu.devices[params.qa].device
    if device then
      local typ = ({button='onReleased',switch='onReleased',slider='onChanged',select='onToggled',multi='onToggled'})[path]
      if params.id:sub(1,2)=="__" then -- special embedded UI element
        if embed.embedHooks[params.id] then
          embed.embedHooks[params.id]({device=device},params)
        end
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

---@class WEBAPI : API
WEBAPI = {}
class 'WEBAPI'(API)

function WEBAPI:__init(emu)
  API.__init(self,emu)
  self:setupRoutes()
end

function WEBAPI:call(io, headers, method, path, data) 
  if path:match("^/api/") then
    local stat,res = pcall(function()
    local path = path:sub(5)
    local res,code = Emu.api[method:lower()](path,data)
    jsonData(io,code,json.encode(res))
    return {res,code,headers}
    end)
    if not stat then
      Emu:ERRORF("API call failed: %s", res)
      renderPage(io, 500, "Internal Server Error", fmt("<h1>500 Internal Server Error</h1><p>API call failed: %s</p>", res))
      return 500,nil
    else return table.unpack(res) end
  end
  local handler, vars, query = self:getRoute(method, path)
  local res,code,headers = nil,self.HTTP.NOT_IMPLEMENTED,nil
  if handler then
    res,code,headers = handler({io=io, method=method, path=path, data=data, vars=vars, query=query})
  else
    renderPage(io, 404, "Not Found", fmt("<h1>404 Not Found</h1><p>Method: %s, Path: %s</p>", method, path))
  end
  return res,code,headers
end

local helpPage = [[
HTTP Methods:
GET /help - Show this help page
GET /deviceStructure - Get the device structure
POST /deviceStructure - Update the device structure
]]

function WEBAPI:setupRoutes()

  self:add("GET/help", function(ctx)
    renderPage(ctx.io, 200, "Hc3Emu Web API", helpPage)
  end)

  self:add("GET/button",function(ctx) handleUI(ctx,"button") return true end)
  self:add("GET/slider",function(ctx) handleUI(ctx,"slider") return true end)
  self:add("GET/switch",function(ctx) handleUI(ctx,"switch") return true end)
  self:add("GET/select",function(ctx) handleUI(ctx,"select") return true end)
  self:add("GET/multi",function(ctx) handleUI(ctx,"multi") return true end)
  self:add("GET/getLocal", function(ctx)
    local path = urldecode(ctx.query.path)
    local typ = ctx.query.type or 'file'
    local content = nil
    if typ == 'rsrc' then content = Emu.lib.readRsrcsFile(path)
    else
      local f = io.open(path,"r")
      if f then content = f:read("*a") f:close() end
    end
    if content then
      ctx.io.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: "..(#content).."\r\n\r\n"..content)
    else
      Emu:ERRORF("Failed to open file for reading: %s",path)
      ctx.io.write("HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nAccess-Control-Allow-Origin: *\r\n\r\nFile not found")
    end
  end)

  self:add("GET/getDeviceStructure", function(ctx)
  local id = tonumber(ctx.query.id)
  if not id or not Emu.devices[id] then
    ctx.io.write("HTTP/1.1 400 Bad Request\r\nContent-Type: application/json\r\nContent-Length: 36\r\n\r\n{\"error\":\"Invalid device ID parameter\"}")
    return
  end
  local device = Emu.devices[id].device
  local structure = json.encodeFormated(device)
  ctx.io.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: "..(#structure).."\r\n\r\n"..structure)
  end)

end

-- CORS control from client - answer yes...
local function handleOPTIONS(path,headers,io)
  local date = os.date("!%a, %d %b %Y %H:%M:%S GMT")
  io.write(
  "HTTP/1.1 200 OK\r\nDate: " .. date .. "\r\nServer: Apache/2.0.61 (Unix)\r\nAccess-Control-Allow-Origin:*\r\nAccess-Control-Allow-Methods: POST, GET, OPTIONS\r\nAccess-Control-Allow-Headers:X-PINGOTHER, Content-Type\r\n\r\n")
  return true
end

WebServer2 = WebServer2
class 'WebServer2'(SocketServer) 
function WebServer2:__init(ip,port) 
  SocketServer.__init(self,ip,port,Emu.IP)
  self.api = WEBAPI(Emu)
end

function WebServer2:handler(io)
  local request = io.read()
  local headers = {}
  local contentLength,data = nil,nil
  while true do
    local header = io.read()
    headers[#headers+1] = header
    local clh = header:match("[Cc]ontent%-[Ll]ength: (%d+)")
    if clh then contentLength = tonumber(clh) end
    if header == "" then
      if contentLength and contentLength > 0  then
        data = io.read(contentLength)
      end
      local method,path = request:match("([^%s]+) ([^%s]+)")
      Emu:DEBUGF("server","Webrequest %s %s",method,path)
      if self.api:call(io,headers,method,path,data) == true then
        -- If the true, return 200 OK, if false the handler has already written the response
        io.write("HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nAccess-Control-Allow-Origin: *\r\n\r\n")
      end
      break
    end
  end
end

local function startServer()
  local ip = Emu.config.pip
  local port = Emu.config.wport
  local server = WebServer2(ip,port)
  server:start()
end

return {
  startServer = startServer,
}