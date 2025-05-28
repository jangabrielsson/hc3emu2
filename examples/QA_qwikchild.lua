--This is a QA testing the QwikAppChild library

--NOTE: This is a test for the QwikAppChild class you need to have --%%state set so internalStorage data is saved for children

--%%name=QwikChildTest
--%%type=com.fibaro.genericDevice
--%%proxy=true
--%%offline=true
--%%state=10
--%%webui=true
--%%file=$hc3emu2.lib.qwikchild:QwikAppChild

local function printf(...) print(string.format(...)) end

class 'MyChild'(QwikAppChild)
function MyChild:__init(dev)
  QwikAppChild.__init(self,dev)
  self:debug("MyChild initialized",self.name,self.id)
  local a = self:internalStorageGet("foo")
end
function MyChild:myButton1()
  self:debug("myButton1 pressed")
end
function MyChild:mySlider(event)
  self:debug("mySlider",event.values[1])
end
function MyChild:setValue(v)
  self:debug("setValue",v)
  self:updateProperty('value',v)
end
function MyChild:childFun(a,b)
  printf("childFun called %s+%s=%s",a,b,a+b)
end

local children = {
  bar134 = {
    name = "Bar1",
    type = "com.fibaro.multilevelSwitch",
    className = "MyChild",
    UI = {
      {button='b1',text='B1',onReleased='myButton1'},
      {button='b2',text='My new button',onReleased='myButton1'},
      {slider='s1',text='S1',onChanged='mySlider'}
    },
  },
  bar22 = {
    name = "Bar2",
    type = "com.fibaro.multilevelSwitch",
    className = "MyChild"
  },
  bar3 = {
    name = "Bar3",
    type = "com.fibaro.multilevelSwitch",
    className = "MyChild"
  },
}
function QuickApp:onInit()
  self:initChildren(children)
  fibaro.call(self.children.bar3.id,"childFun",5,7)
end

