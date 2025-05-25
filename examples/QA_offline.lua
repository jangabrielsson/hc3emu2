--%%name=Offline
--%%type=com.fibaro.binarySwitch
--%%offline=true
--%%nodir=true
--%% install=admin,Admin1477!,http://192.168.1.57

local runTest

local function test1(t)
  t.test = "put/globalVariable non-exist"
  t.equal({api.put("/globalVariables/A",{value="V"})},{nil,404})
  t.test = "post/globalVariable non-exist"
  t.tablematch({api.post("/globalVariables",{name="A",value="V"})},{{name="A",value="V"},201})
  t.test = "fibaro.setGlobalVariable"
  t.equal(fibaro.setGlobalVariable("A","V1"),nil)
  t.test = "fibaro.getGlobalVariable"
  t.equal(fibaro.getGlobalVariable("A"),"V1")
end

function QuickApp:onInit()
  self:debug(self.name,self.id)
  
  fibaro.hc3emu.lib.runTest(test1,fibaro)
end


