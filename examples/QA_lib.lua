--%%name=LibTest
--%%type=com.fibaro.binarySwitch
--%% debug=system:true
--%%save=encrypt.fqa
--%%interfaces={"battery"}
--%% file=$hc3emu2.lib.aeslua53:aes
--%%file=src/hc3emu2/lib/aeslua53.lua:aes

function QuickApp:onInit()
  self:debug(self.name,self.id)
  local code = fibaro.aes.encrypt("password","Hello world")
  self:debug("Encrypted:", code)
  local code2 = fibaro.aes.decrypt("password",code)
  self:debug("Decrypted:", code2)
end
