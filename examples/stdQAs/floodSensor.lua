--%%name=FloodSensor
--%%type=com.fibaro.floodSensor
--%%description=Flood sensor template
--%%webui=true

-- Flood sensor type have no actions to handle
-- To update flood sensor state, update property "value" with boolean
-- Eg. self:updateProperty("value", true) will indicate that flood was detected 

function QuickApp:onInit()
    self:debug("onInit")
end 