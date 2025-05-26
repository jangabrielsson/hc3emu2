local devices = {
  remote = "_remote.lua"
}

local function createSimDevice(type)
  local file,path = devices[type],"src/rsrcs"..Emu.config.fileSeparator.."simdevs"..Emu.config.fileSeparator
  local html = nil
  local pi = Emu:getPI()
  local callingDevice = pi.env.plugin.mainDeviceId
  local dev = Emu.devices[callingDevice]
  local headers = {webui = tostring(dev.headers.webUI==true),var="parent:"..callingDevice} 
  local qa = Emu.lib.loadQA(path..file,headers)
  return qa.id
end

return {
  createSimDevice = createSimDevice,
}

