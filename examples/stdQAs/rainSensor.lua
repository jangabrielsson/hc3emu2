--%%name=RainSensor
--%%type=com.fibaro.rainSensor
--%%description="My description"
--%%webui=true

function QuickApp:onInit()
    self:debug(self.name,self.id)
end

function QuickApp:updateRainValue(value)
    self:setVariable("value",value)
end
