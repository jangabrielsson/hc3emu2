--%%name=CEtest
--%% offline=true
--%%debug=refresh:true

--%%file=$hc3emu2.lib.eventmgr:eventmgr

function QuickApp:onInit()
  self:debug(self.name,self.id)
  
  local em = EventMgr()

  em:addHandler({type="custom-event"}, function(event)
    self:debug("Custom Event Triggered", event.name, event.description)
  end)

  api.post("/customEvents",{name='testCE',description="Hello"})
  api.post("/customEvents/testCE",{})

end