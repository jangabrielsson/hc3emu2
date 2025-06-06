--%%name=MyQA
--%%type=com.fibaro.binarySwitch
--------ENDOFHEADERS------------

function QuickApp:onInit()
  self:debug("welcome")
  local refresh = RefreshStateSubscriber()
  local handler = function(event)
    if event.type == "DevicePropertyUpdatedEvent" then
      print(json.encode(event.data))
    end
  end
  refresh:subscribe(function() return true end,handler)
  refresh:run()

  fibaro.hc3emu.loadQAString([[
    --%%name=Switch
    --%%type=com.fibaro.binarySwitch
    function QuickApp:onInit()
      setInterval(function()
        local value = fibaro.getValue(self.id,'value')
        self:updateProperty('value',not value)
    end,2000)
    end
  ]])

  self:createChildDevice({
    name = "MyChild",
    type = "com.fibaro.binarySwitch",
  }, MyChild)
end

class 'MyChild'(QuickAppChild)
function MyChild:__init(dev)
  QuickAppChild.__init(self,dev)
  self:updateProperty('value',true)
  self:debug("MyChild:onInit",self.name,self.id)
  setInterval(function()
    local value = fibaro.getValue(self.id,'value')
    self:updateProperty('value',not value)
  end,2000)
end