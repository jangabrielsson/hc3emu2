--%%name=GlobalVars
--%%offline=true

--%%file=$hc3emu2.lib.eventmgr,events

function QuickApp:onInit()

  local em = EventMgr()

  em:addHandler({type="global-variable"}, function(event)
    self:debug(print(json.encode(event)))
  end)

  api.post("/globalVariables",{name="testVar",value="testValue"})
  fibaro.setGlobalVariable("testVar","testValue2")
end