--%%name=SimDevices
--%%type=com.fibaro.deviceController
--%%offline=true
--%%webui=true
--%%debug=refresh:true

function QuickApp:onInit()
  self:debug("onInit",self.name,self.id)
  local dev = fibaro.hc3emu.createSimDevice('remote')
end