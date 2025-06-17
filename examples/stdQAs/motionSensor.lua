--%%name=MyQA
--%%type=com.fibaro.motionSensor
--%%description=My description
--%%webui=true

function QuickApp:onInit()
    self:debug(self.name,self.id)
end

-- Motion sensor type has no actions to handle
-- To update motion sensor state, update property "value" with boolean
-- Eg. self:updateProperty("value", true) will indicate that motion was detected 