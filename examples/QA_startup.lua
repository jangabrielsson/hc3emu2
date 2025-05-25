--%%name=Startup
--%%offline=true

print("Sunset",fibaro.getValue(1,"sunsetHour"))

function QuickApp:onInit()
  self:debug("QuickApp Initialized", self.name, self.id)
end