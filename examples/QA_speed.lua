--%%name=SpeedQA
--%%type=com.fibaro.binarySwitch
--%%time=12/31 10:00:12
--%%speed=4

function QuickApp:onInit()
  self:debug(self.name,self.id)
  local a = setInterval(function() 
      print("PING")
      end,1000*60)

  print(fibaro.hc3emu.lib.timerInfo(a))
end