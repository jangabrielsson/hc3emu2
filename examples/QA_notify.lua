--%%name=Notifier
--%%type=com.fibaro.binarySwitch
--%% proxy=true
--%%offline=true
--%%minify=true
--%%save=mini.fqa

do
  local refs = {}
  function QuickApp.INTERACTIVE_OK_BUTTON(_,ref) -- Must be proxy for action to find its way back to the emulator
    ref,refs[ref]=refs[ref],nil
    if ref then ref(true) end
  end

  function QuickApp:pushYesNo(mobileId,title,message,callback,timeout)
    local ref = tostring({}):match("%s(.*)")
    local res,err = api.post("/mobile/push", 
      {
        category = "YES_NO", 
        title = title, 
        message = message, 
        service = "Device", 
        data = {
          actionName = "INTERACTIVE_OK_BUTTON", 
          deviceId = self.id, 
          args = {ref}
        }, 
        action = "RunAction", 
        mobileDevices = { mobileId }, 
      })
    timeout = timeout or (20)
    local timer = setTimeout(function()
        local r
        r,refs[ref] = refs[ref],nil
        if r then r(false) end 
      end, 
      timeout*1000)
    refs[ref]=function(val) clearTimeout(timer) callback(val) end
  end
end

function QuickApp:onInit()
  self:debug("onInit",self.name,self.id)
  self:pushYesNo(923,"Test","Do you want to turn on the light?",function(val)
    if val then fibaro.call(self.id,"turnOn") end
  end)
end

function QuickApp:Test(...)
  self:debug("Test", ...)
end
