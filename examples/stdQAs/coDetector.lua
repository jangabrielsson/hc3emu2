--%%name=MyQA
--%%type=com.fibaro.coDetector
--%%description=My description
--%%webui=true

function QuickApp:onInit()
    self:debug(self.name,self.id)
end

-- Carbon monoxide detector type has no actions to handle
-- To update carbon monoxide detector state, update property "value" with boolean
-- Eg. self:updateProperty("value", true) will indicate that carbon monoxide was detected 