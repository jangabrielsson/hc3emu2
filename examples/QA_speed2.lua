--This is a QA rinning in local mode and speeding the timers...

--%%name=SpeedTest
--%%type=com.fibaro.multilevelSwitch
--%%debug=timer1:true,db:true
--%% offline=true
--%% speed=24*7 -- One week

function QuickApp:interval()
  setInterval(function() -- Ping every day
    self:debug("Hello from hc3emu",fibaro.getValue(1,"sunriseHour"))
  end,24*3600*1000)
end

function QuickApp:onInit()
  self:debug("onInit",self.name,self.id)
  setTimeout(function() 
    print("PING")
    fibaro.hc3emu.lib.speedFor(7*24,function(speed) -- Don't work with header speed!
      if speed then return end
      setTimeout(function() print("Ping after ~3s") end,3000)
    end)
  end,2000)

  self:interval()
end

function QuickApp:onInit2()
  self:debug("onInit",self.name,self.id)
  local n,speed = 0,false
  setInterval(function()
    n = n + 1
    if n % 5 == 0 then
      speed = not speed
      fibaro.hc3emu.lib.speedFor(speed and 24*7 or 0)
    end
    self:debug("Interval executed")
  end, 2000)
end
