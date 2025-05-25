--%%name=SyncTest

local function httpRequest()
  local loc = api.get("/settings/location")
  local url = string.format("https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current_weather=true",loc.latitude,loc.longitude)
  net.HTTPClient():request(url,{
    options = {
      method = "GET",
      headers = { ["Accept"] = "application/json" },
    },
    success = function(response) 
      local weather = json.decode(response.data)
      print("Response",json.encode(weather.current_weather))
      print("Temperature: " .. weather.current_weather.temperature .. "°C")
    end,
    error = function(err) fibaro.error(__TAG,err) end
  })
end

print("main",plugin.mainDeviceId)
setTimeout(function() print("1. Hello from sync") end, 0)
api.get("/devices/"..46)
print("1. This is a test QuickApp for synchronous API calls")

function QuickApp:onInit()
  self:debug("onInit",self.name,self.id)
  setTimeout(function() print("2. Hello from sync2") end, 0)
  httpRequest()
  api.get("/devices/"..46)
  print("2. This is a test QuickApp for synchronous API calls")
end


