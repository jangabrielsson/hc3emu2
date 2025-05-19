--%%name=SimpleQA
--%%type=com.fibaro.binarySwitch
--%%state=9
--%%condensedLog=true
--%%debug=refresh:false
--%%proxy=true
--%%logUI=true

fibaro.hc3emu.count = fibaro.hc3emu.count or 0

function QuickApp:onInit()
  self:debug(self.name,self.id)

  --self:intervalPing()
  self:childTest()
  self:httpTest()
  --self:restartTest()
  self:refreshTest()
  self:internalStorageTest()

  local devs = api.get("/devices?interface=quickApp")
  print("QAs,", #devs)

  -- self.childsInitialized = true
  -- local r = setInterval(function() print("PING") end, 5000)
  -- clearTimeout(r)
end

MyChild = MyChild
class 'MyChild'(QuickAppChild)
function MyChild:__init(dev)
  QuickAppChild.__init(self, dev)
  self:debug("Inited",self.name,self.id)
  local n,ref = 0,nil
  ref = setInterval(function()
    n = n+1
    self:updateProperty('value',not self.properties.value)
    print("Calling",self.parentId,n)
    fibaro.call(self.parentId,"test",1,2,3)
    if n > 4 then clearInterval(ref) end
  end,3000)
end
function MyChild:turnOn()
  self:debug("Child Turned on")
  self:updateProperty('value', true)
end
function MyChild:turnOff()
  self:debug("Child Turned off")
  self:updateProperty('value', false)
end

function QuickApp:test(a,b,c)
  self:debug("TEST",a,b,c)
end

function QuickApp:intervalPing()
  local n = 0
  setInterval(function() 
    n=n+1
    self:debug("PING",n) 
  end,5000)
end

function QuickApp:childTest()
  local children = api.get("/devices?parentId="..self.id)
  if not children or #children == 0 then
    self:debug("Creating child device")
    self:createChildDevice({
      name = "Child1",
      type = "com.fibaro.binarySwitch",      
    }, MyChild)
  else
    self:initChildDevices({['com.fibaro.binarySwitch']=MyChild})
    self:debug("#Children",#children)
    for _,child in ipairs(children) do
      self:debug("Child",child.name,child.id)
    end
  end
end

function QuickApp:restartTest()
  fibaro.hc3emu.count = fibaro.hc3emu.count + 1
  if fibaro.hc3emu.count < 4 then
    self:debug("Restarting")
    plugin.restart()
  end
end

function QuickApp:httpTest()
  local loc = api.get("/settings/location")
  local url = string.format("https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current_weather=true",loc.latitude,loc.longitude)
  net.HTTPClient():request(url,{
    options = {
      method = "GET",
      headers = { ["Accept"] = "application/json" },
    },
    success = function(response) 
      local weather = json.decode(response.data)
      self:debug("Response",json.encode(weather.current_weather))
      self:debug("Temperature: " .. weather.current_weather.temperature .. "°C")
    end,
    error = function(err) self:error(err) end
  })
end

function QuickApp:refreshTest()
local refresh = RefreshStateSubscriber()
  local handler = function(event)
    if event.type == "DevicePropertyUpdatedEvent" then
      print("QAsimp:",json.encode(event.data))
    end
  end
  refresh:subscribe(function() return true end,handler)
  refresh:run()
end

function QuickApp:internalStorageTest()
  local key = self:internalStorageGet("testKey")
  if key == nil then
    self:debug("Key not found, setting")
    self:internalStorageSet("testKey", 1)
    key = self:internalStorageGet("testKey")
  end
  self:debug("Key found, value:",key)
  self:internalStorageSet("testKey", key+1)
end
------------------------------------------------------------
function QuickApp:turnOn()
  self:debug("Turned on")
  self:updateProperty('value', true)
end
function QuickApp:turnOff()
  self:debug("Turned off")
  self:updateProperty('value', false)
end