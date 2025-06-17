--%%name=MyQA
--%%type=com.fibaro.genericDevice
--%%description=My description
--%%webui=true

-- Generic device type have no default actions to handle 

function QuickApp:onInit()
    self:debug(self.name,self.id)
end 