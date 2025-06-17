--%%name=MyQA
--%%type=com.fibaro.binarySensor
--%%description=My description
--%%webui=true

function QuickApp:onInit()
    self:debug(self.name,self.id)
end

-- Binary sensor type have no actions to handle
-- To update binary sensor state, update property "value" with boolean
-- Eg. self:updateProperty("value", true) will set sensor to breached state 