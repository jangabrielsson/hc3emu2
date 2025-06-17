--%%name=FireDetector
--%%type=com.fibaro.fireDetector
--%%description="My description"
--%%webui=true

-- Fire detector type has no actions to handle
-- To update fire detector state, update property "value" with boolean
-- Eg. self:updateProperty("value", true) will indicate that fire was detected 

function QuickApp:onInit()
    self:debug(self.name,self.id)
end

function QuickApp:breached(state)
    self:debug("fire detector breached: " .. tostring(state))
    self:updateProperty("value", state)
end