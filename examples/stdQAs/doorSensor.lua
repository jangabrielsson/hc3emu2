--%%name=DoorSensor
--%%type=com.fibaro.doorSensor
--%%description="My description"
--%%webui=true

-- Door sensor type have no actions to handle
-- To update door sensor state, update property "value" with boolean
-- Eg. self:updateProperty("value", true) will set sensor to breached state 

function QuickApp:onInit()
    self:debug(self.name,self.id)
end

function QuickApp:breached(state)
    self:debug("door sensor breached: " .. tostring(state))
    self:updateProperty("value", state)
end