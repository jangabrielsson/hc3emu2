--%%name=Startup
--%% offline=true
--%%save=test.fqa

print("Sunset",fibaro.getValue(1,"sunsetHour"))

function QuickApp:onInit()
  self:debug("QuickApp Initialized", self.name, self.id)
end