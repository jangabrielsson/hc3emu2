--%%name=MyMultilevelSwitch
--%%type=com.fibaro.multilevelSwitch
--%%description=My description
--%%webui=true

function QuickApp:onInit()
    self:debug("Inited",self.name,self.id)
end

function QuickApp:turnOn()
    self:debug("multilevel switch turned on")
    self:updateProperty("value", 99)
end

function QuickApp:turnOff()
    self:debug("multilevel switch turned off")
    self:updateProperty("value", 0)    
end

-- Value is type of integer (0-99)
function QuickApp:setValue(value)
    self:debug("multilevel switch set to: " .. tostring(value))
    self:updateProperty("value", value)    
end
