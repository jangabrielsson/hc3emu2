--%%name=HeatDetector
--%%type=com.fibaro.heatDetector
--%%description="My description"
--%%webui=true

-- Heat detector type has no actions to handle
-- To update heat detector state, update property "value" with boolean
-- Eg. self:updateProperty("value", true) will indicate that heat was detected 

function QuickApp:onInit()
    self:debug(self.name,self.id)
end

function QuickApp:breached(state)
    self:debug("heat detector breached: " .. tostring(state))
    self:updateProperty("value", state)
end