--%%name=MultilevelSensor
--%%type=com.fibaro.multilevelSensor
--%%description="My description"
--%%webui=true

-- Multilevel sensor type have no actions to handle
-- To update multilevel sensor state, update property "value" with integer
-- Eg. self:updateProperty("value", 37.21) 

-- To set unit of the sensor, update property "unit". You can set it on QuickApp initialization
-- Eg. 
-- function QuickApp:onInit()
--     self:updateProperty("unit", "KB")
-- end 

function QuickApp:onInit()
    self:debug(self.name,self.id)
end 