--%%name=MyQA
--%%type=com.fibaro.doorSensor
--%%description=My description
--%%webui=true

function QuickApp:onInit()
    self:debug(self.name,self.id)
end

-- Door sensor type have no actions to handle
-- To update door sensor state, update property "value" with boolean
-- Eg. self:updateProperty("value", true) will set sensor to breached state 