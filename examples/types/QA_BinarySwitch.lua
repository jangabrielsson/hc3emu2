--%%name=MyBinarySwitch
--%%type=com.fibaro.binarySwitch
--%%description=My description
--%%webui=true

function QuickApp:onInit()
    self:debug("Inited",self.name,self.id)
end

function QuickApp:turnOn()
    self:debug("binary switch turned on")
    self:updateProperty("value", true)
end

function QuickApp:turnOff()
    self:debug("binary switch turned off")
    self:updateProperty("value", false)    
end
