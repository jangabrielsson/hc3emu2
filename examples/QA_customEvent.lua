--%%name=CEtest
--%% offline=true
--%%debug=refresh:true
--%% nocolor=true

--%%file=$hc3emu2.lib.eventmgr:eventmgr

fibaro.debug(__TAG,"TEST%YY")
fibaro.trace(__TAG,"TEST")
fibaro.warning(__TAG,"TEST")
fibaro.error(__TAG,"TEST")
function QuickApp:onInit()
  self:debug(self.name,self.id)
  
  local em = EventMgr()

  em:addHandler({type="custom-event"}, function(event)
    self:debug("Custom Event Triggered", event.name, event.description)
  end)

  api.post("/customEvents",{name='testCE',description="Hello"})
  api.post("/customEvents/testCE",{})

end