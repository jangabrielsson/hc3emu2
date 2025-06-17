--%%name=WindowSensor
--%%type=com.fibaro.windowSensor
--%%description="My description"
--%%webui=true

-- Window sensor type have no actions to handle
-- To update window sensor state, update property "value" with boolean
-- Eg. self:updateProperty("value", true) will set sensor to breached state 

function QuickApp:onInit()
    self:debug(self.name,self.id)
end

function QuickApp:breached(state)
    self:debug("window sensor breached: " .. tostring(state))
    self:updateProperty("value", state)
end