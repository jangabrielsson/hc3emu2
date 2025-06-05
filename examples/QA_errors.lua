if require and not QuickApp then require('hc3emu') end

--%%name=QA_errors
--%%type=com.fibaro.binarySwitch

function QuickApp:onInit()
  self:debug(self.name,self.id)
  --error("FOO")
  setTimeout(function() 
      print("PING")
      error("Test error")
      end,0)
end