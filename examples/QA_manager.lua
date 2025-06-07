--%%name=Manager
--%%type=com.fibaro.deviceController
--%%webui=true

--%%file=$hc3emu2.lib.selectable,selectable
--%%u={label='l1',text='QuickApp Manager'}
--%%u={select='qaSelect', text="QuickApp", onToggled="qaSelect"}
--%%u={select='varSelect', text="QuickApp", onToggled="varSelect"}

---@class QAList
QAList = {}
class "QAList"(Selectable)
function QAList:__init(qa) Selectable.__init(self,qa,"qaSelect") end
function QAList:text(item) return item.id..":"..item.name end
function QAList:value(item) return item.id end
function QAList:sort(a,b) 
  return a.name < b.name
end
function QAList:selected(item)
  local vars = item.properties.quickAppVariables or {}
  self.qa.variables:update(vars)
  self.qa:updateView("value","text","")
end

---@class QAVars
QAVars = {}
class "QAVars"(Selectable)
function QAVars:__init(qa) Selectable.__init(self,qa,"varSelect") end
function QAVars:text(item) return item.name end
function QAVars:value(item) return item.name end
function QAVars:sort(a,b) return a.name < b.name end
function QAVars:selected(item)
  self.qa:updateView("value","text",tostring(item.value))
end

function QuickApp:onInit()
    self:debug("onInit")
    self:updateView("l1","text","QuickApp Manager2")
    self.list = QAList(self)
    self.variables = QAVars(self)
    local qas = api.get("/devices?interface=quickApp")
    self.list:update(qas)
end