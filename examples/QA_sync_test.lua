--%%name=SyncTest

print("main",plugin.mainDeviceId)
setTimeout(function() print("1. Hello from sync") end, 0)
api.get("/devices/"..44)
print("1. This is a test QuickApp for synchronous API calls")

function QuickApp:onInit()
  self:debug("onInit",self.name,self.id)
  setTimeout(function() print("2. Hello from sync2") end, 0)
  api.get("/devices/"..44)
  print("2. This is a test QuickApp for synchronous API calls")
end


