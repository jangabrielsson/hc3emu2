--%%name=MyQA
--%%type=com.fibaro.humiditySensor
--%%description=My description
--%%webui=true

function QuickApp:onInit()
    self:debug(self.name,self.id)
end

-- Humidity sensor type have no actions to handle
-- To update humidity, update property "value" with floating point number
-- Eg. self:updateProperty("value", 90.28) 