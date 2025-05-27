--This is QA testing the internalStorage API
--%%name=InternalStorageTest
--%%type=com.fibaro.multilevelSwitch
--%% proxy=MyProxy
--%%save=savestore.fqa
--%%offline=true
--%% debug=api:true
--%%var=debug:"main,wsc,child,color,battery,speaker,send,late"

-- This QA is not allowed to calll the HC3 at all. Other http calls are allowed.
-- It can be used to test the QA logic without access to the HC3.

local function printf(...) print(string.format(...)) end

function QuickApp:onInit()
  print("InternalStorage QA started",self.name,self.id)
  
  self:internalStorageSet("TestVar","42")
  self:check("Set/Get",self:internalStorageGet("TestVar"),"42")
end

function QuickApp:check(str,val1,val2)
  if val1 ~= val2 then
    self:error(str,val1,"!=",val2)
  else self:debug(str,"OK",val1,"=",val2) end
end
