--%%name=LibTest
--%%type=com.fibaro.binarySwitch
--%%debug=system:true
--%%file=$hc3emu2.lib.aeslua53:aes

local function foo()
  print("Hello from foo")
  setTimeout(foo,1000)
end
--setTimeout(foo,1000)

function QuickApp:onInit()
  self:debug(self.name,self.id)
  local code = fibaro.aes.encrypt("password","Hello world")
  self:debug("Encrypted:", code)
  local code2 = fibaro.aes.decrypt("password",code)
  self:debug("Decrypted:", code2)
end