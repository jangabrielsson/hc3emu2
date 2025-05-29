if require and not QuickApp then require('hc3emu') end

--%%name=QA_errors
--%%type=com.fibaro.binarySwitch

function QuickApp:onInit()
  self:debug(self.name,self.id)
  error("FOO")
  setInterval(function() 
      print("PING")
      error("BAR")
      end,1000*3)
end
