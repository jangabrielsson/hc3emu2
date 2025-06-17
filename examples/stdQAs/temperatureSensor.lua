--%%name=MyQA
--%%type=com.fibaro.temperatureSensor
--%%description=My description
--%%webui=true

function QuickApp:onInit()
    self:debug(self.name,self.id)
end

-- Temperature sensor type have no actions to handle
-- To update temperature, update property "value" with floating point number, supported units: "C" - Celsius, "F" - Fahrenheit
-- Eg. self:updateProperty("value", { value= 18.12, unit= "C" }) 