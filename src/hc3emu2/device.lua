local fmt = string.format

local embed = require("hc3emu2.embedui")

Device = Device
class 'Device'
function Device:__init(args)
  self.id = args.id
  self.device = args.device
  self.files = args.files or {}
  self.env = args.env
  self.vars = args.vars   -- internalStorageVars
  self.UI = args.UI or {}
  self.orgUI = table.copy(self.UI)
  self.watches = args.watches or {}
  self.headers = args.headers or {}
  self.pageName = args.pageName
  
  local embedElements = embed.embedUIs[self.device.type] -- Add embed/stock UI elements for device type
  for i,r in ipairs(embedElements or {}) do table.insert(self.UI,i,r) end
  if self.headers.webUI then
    if self.device.isChild then -- Decide html page name for QA
      local name = (self.device.name or "Child"):gsub("[^%w]","")
      self.pageName = fmt("%s_%s.html",name,self.id)
    else
      local name = self.device.name:gsub("[^%w]","")
      self.pageName = fmt("%s.html",name)
    end
  end

  local index = {}
  self:initializeUI(self.UI,index)
  setmetatable(self.UI,{
    __index=function(t,k) if index[k] then return index[k] else return rawget(t,k) end end,
  })
end

function Device:watching(prop,value) 
  --print("WATCH",args.id,prop)
  if self.watches[prop] then self.watches[prop](value) end
end

local compMap = {
  text = function(v) return v end, 
  value = function(v) if type(v)=='table' then return v[1] else return v end end,
  options = function(v) return v end,
  selectedItem = function(v) return v end,
  selectedItems = function(v) return v end
}

function Device:updateView(componentName,propertyName,value) 
  --print("UPDATEVIEW",args.id,componentName,propertyName,value)
  local UI = self.UI
  local elm = UI[componentName]
  if not elm then return end
  if compMap[propertyName] then value = compMap[propertyName](value) end
  if value ~= elm[propertyName] then 
    elm[propertyName] = value 
    Emu:post({type='quickApp_updateView',id=self.id})
  end
end

function Device:toArgs() 
  return {
    id=self.id, 
    device=self.device, 
    files=self.files,
    vars=self.vars, 
    UI=self.orgUI,
    headers=self.headers, 
    uiPage=self.uiPage
  }
end

function Device:initializeUI(UI,index)
  if type(UI) ~= 'table' then return end
  local typ = Emu.lib.ui.getElmType(UI)
  if not typ then for _,r in ipairs(UI) do self:initializeUI(r,index) end return end
  UI.type = typ
  local componentName = UI[typ]
  if index[componentName] then
    Emu:DEBUGF('warn',"Duplicate UI element %s in %s",componentName,self.device.name)
  end
  index[componentName] = UI
  if componentName then -- Also primes the UI element with default values, in particular from embedded UI elements
    local sval = embed.embedProps[componentName] and embed.embedProps[componentName](self) or nil
    if UI.label then UI.text = sval or UI.text end
    if UI.button then UI.text = UI.text end
    if UI.slider then 
      UI.value = sval or UI.value 
    end
    if UI.switch then UI.value = UI.value end
    if UI.select then 
      UI.value = UI.values 
      UI.options = UI.options or {}
    end
    if UI.multi then 
      UI.value = UI.values 
      UI.options = UI.options or {}
    end
  end
end

  function Emu.EVENT.device_created(event,emu)
    local dev = emu.devices[event.id]
    if dev.headers.webUI then -- setup for generating web page
      Emu.web.generateUIpage(dev.device.id,dev.device.name,dev.pageName,dev.UI)
    end
    emu:startQA(event.id) 
  end

  return {}