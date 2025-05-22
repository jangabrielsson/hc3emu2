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

local embed = require("hc3emu.embedui")

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
function WebServer:__init(ip,port) SocketServer.__init(self,ip,port,Emu.IP) end
function WebServer:handler(io)
  local request = io.read()
  local headers = {}
  while true do
    local header = io.read()
    headers[#headers+1] = header
    if header == "" then
      local method,path = request:match("([^%s]+) ([^%s]+)")
      if method == 'GET' and handleGET(path,headers,io) then 
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

local function startServer()
  local ip = Emu.config.pip
  local port = Emu.config.wport
  local server = WebServer(ip,port)
  server:start()
end

local header = [[
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Device View</title>
  <link rel="stylesheet" href="pages/style.css"> <!-- Include external CSS -->
  <script>
    const SERVER_IP = "http://%s:%s"; // Define the server IP address
    const DEVICE_ID = "%s"; // Define the QA id
  </script>
  <script src="pages/script.js" defer></script> <!-- Include external JavaScript -->
</head>
<body>
]]

local footer = [[
</body>
</html>
]]

local function member(e,l) for _,k in ipairs(l) do if e == k then return true end end return false end

local pages = {}
local render = {}
function render.label(pr,item)
  pr:printf('<div style="width: 100%%;" class="label">%s</div>',item.text)
end
function render.button(pr,item)
  pr:printf([[<button id="%s" class="control-button" onclick="fetchAction('button', this.id)">%s</button>]],item.button,item.text)
end
function render.slider(pr,item)
  local indicator = item.slider.."Indicator"
  pr:printf([[<div>%s<input id="%s" type="range" value="%s" min="%s" max="%s" class="slider-container" oninput="handleSliderInput(this,'%s')"></div>
<span id="%s">%s</span>]],item.text or "",item.slider,item.value or 0,item.min or 0,item.max or 100,indicator,indicator,item.value or 0)
end
function render.switch(pr,item)
  -- Determine the initial state based on item.value
  local state = tostring(item.value) == "true" and "on" or "off"
  local color = state == "on" and "blue" or "#4272a8" -- Set color based on state #578ec9;
  pr:printf([[<button id="%s" class="control-button" data-state="%s" style="background-color: %s;" onclick="toggleButtonState(this)">%s</button>]],
  item.switch, state, color, item.text)
end
function render.select(pr,item)
  pr:printf('<select class="dropdown" name="cars" id="%s" onchange="handleDropdownChange(this)">',item.select)
  for _,opt in ipairs(item.options) do
    pr:printf('<option %s value="%s">%s</option>',item.value == opt.value and "selected" or "",opt.value,opt.text)
  end
  pr:print('</select>')
end
function render.multi(pr,item)
  pr:print('<div class="dropdown-container">')
  pr:printf([[<button onclick="toggleDropdown('%s')" class="dropbtn">Select Options</button>]],item.multi)
  pr:printf('<div id="%s" class="dropdown-content">',item.multi)
  for _,opt in ipairs(item.options) do
    local function isCheck(v) 
      return item.value and member(v,item.value) and "checked" or "" 
    end
    pr:printf('<label><input type="checkbox" %s value="%s" onchange="sendSelectedOptions(this)"> %s</label>',isCheck(opt.value),opt.value,opt.text)
  end
  pr:print('</div></div>')
end

local function prBuff(init)
  local self,buff = {},{}
  if init then buff[#buff+1] = init end
  function self:print(s) buff[#buff+1]=s end
  function self:printf(...) buff[#buff+1]=fmt(...) end
  function self:tostring() return table.concat(buff,"\n") end
  return self
end

local function generateUIpage(id,name,fname,UI)
  local format,t0 = string.format,os.clock()
  local device = Emu.devices[id].device
  local SIP = Emu.config.pip2
  --SIP="127.0.0.1"
  local pr = prBuff(format(header,SIP,Emu.config.wport,id))
  --print("Generating UI page")
  pr:printf('<div class="label">Device: %s %s (%s)</div>',id,name,device.type)
  
  for _,row in ipairs(UI) do
    if not row[1] then row = {row} end
    pr:print('<div class="device-card">')
    pr:printf('  <div class="device-controls%s">',#row)
    for _,item in ipairs(row) do
      render[item.type](pr,item)
    end
    pr:print('</div>')
    pr:print('</div>')
  end
  
  local qvars = device.properties.quickAppVariables or {}
  -- qvars={{name=<name>,value=<value>}} end
  if qvars and next(qvars) then 
    pr:print('<hr>')
    pr:print('<div class="quickapp-variables">')
    pr:print('  <div class="label">QuickApp Variables</div>')
    for _,item in ipairs(qvars) do
      local name = item.name
      local value = json.encode(item.value)
      pr:printf('  <div class="label">%s: %s</div>',name,value)
    end
    pr:print('</div>')
  end
  
  pr:print('<hr>')
  -- Add Device Structure toggle button
  pr:print('<div class="device-structure-container">')
  pr:print('  <button id="deviceStructureBtn" class="control-button-small" onclick="toggleDeviceStructure()">Show Device Structure</button>')
  pr:print('  <div id="deviceStructure" class="device-structure" style="display: none;"><pre id="deviceStructureContent"></pre></div>')
  pr:print('</div>')
  
  pr:print(footer)
  local f = io.open(Emu.config.EMU_DIR.."/"..fname,"w")
  if f then
    f:write(pr:tostring())
    f:close()
    pages[fname] = {name=name,link=fname}
  else
    Emu:ERRORF("Failed to open file for writing: %s",Emu.config.EMU_DIR.."/"..fname)
  end
  local elapsed = os.clock() - t0
  Emu:DEBUGF('web',"UI page generated in %.3f seconds",elapsed)
end

local ref = nil
local function updateView(id,name,fname,UI)
  if ref then return end
  ref = Emu:process{
    pi = Emu.PI,
    fun=function()
      copas.sleep(0.3)
      ref=nil
      generateUIpage(id,name,fname,UI)
    end
  }
end

function Emu.EVENT.quickApp_updateView(ev)
  local id = ev.id
  local dev = Emu.devices[id]
  if dev.pageName then
    updateView(dev.device.id,dev.device.name,dev.pageName,dev.UI)
  end
end

local function updateEmuPage()
  local p = {} 
  for _,e in pairs(pages) do p[#p+1]= e end
  table.sort(p,function(a,b) return a.name < b.name end)
  local po = {} 
  for p,_ in pairs(Emu.stats.ports) do po[#po+1] = tostring(p) end
  local emuInfo = {
    stats = {
      version = Emu.VERSION,
      memory = fmt("%.2f KB", collectgarbage("count")),
      numqas = json.util.InitArray(Emu.stats.qas),
      timers = json.util.InitArray(Emu.stats.timers),
      ports =  table.concat(po,","),
    },
    quickApps = p,
    rsrcLink = ("/"..Emu.config.rsrcsDir.."/"):gsub("\\","/"),
  }
  local f = io.open(Emu.config.EMUSUB_DIR.."/info.json","w")
  if f then f:write((json.encode(emuInfo))) f:close() end
end

local started = false
local function generateEmuPage()
  if started then return else started = true end
  Emu:process{
    pi=Emu.PI,
    fun=function()
      while true do
        updateEmuPage()
        copas.pause(2.0)
      end
    end
  }
end

exports.startServer = startServer
exports.generateUIpage = generateUIpage
exports.generateEmuPage = generateEmuPage
exports.updateEmuPage = updateEmuPage
exports.updateView = updateView

return exports