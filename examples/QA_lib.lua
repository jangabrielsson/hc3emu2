--%%name=QALiib
--%%type=com.fibaro.binarySwitch

--%%file=$hc3emu2.lib.aeslua53:aes

function QuickApp:onInit()
  self:debug(self.name,self.id)
  local code = fibaro.aes.encrypt("password","Hello world")
  self:debug("Encrypted:", code)
  local code2 = fibaro.aes.decrypt("password",code)
  self:debug("Decrypted:", code2)
end