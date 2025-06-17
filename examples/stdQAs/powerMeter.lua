--%%name=MyQA
--%%type=com.fibaro.powerMeter
--%%description=My description
--%%webui=true

function QuickApp:onInit()
    self:debug(self.name,self.id)
end

-- Power meter type have no actions to handle
-- To update energy consumption, update property "value" with appropriate floating point number
-- Reported value must be in W
-- Eg. 
-- self:updateProperty("value", 226.137)
-- Power meter contains property rateType, which has two possible values:
-- - production - responsible for production power measurement
-- - consumption - responsible for consumption power measurement
-- Eg.
-- self:updateProperty("rateType", "production")
-- self:updateProperty("rateType", "consumption") 