--%%name=Restart
--%%type=com.fibaro.binarySwitch
--%%debug=system:true

fibaro.hc3emu.count = fibaro.hc3emu.count or 0

function QuickApp:onInit()
  local n = 0
  local r = setInterval(function() print("OK",n) n=n+1 end,1000)
  print(tostring(r))
  fibaro.hc3emu.count = fibaro.hc3emu.count + 1
  if fibaro.hc3emu.count < 3 then
    self:debug("Restarting")
    plugin.restart()
  end
end

