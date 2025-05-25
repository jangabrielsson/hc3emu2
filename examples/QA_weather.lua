--%%name=WeatherQA
--%%offline=true

function QuickApp:onInit()
  self:debug("onInit",self.name,self.id)
  local w = api.get("/weather")
  print("Temperature is", w.Temperature)
  api.put("/weather",{Temperature=w.Temperature+5})
  w = api.get("/weather")
  print("Temperature is", w.Temperature)
end

