--%%name=ColorTest
--%% offline=true

local colors = fibaro.hc3emu.colors
colors.COLORMAP.fopp = colors.EXTRA.pink3

function QuickApp:onInit()
  self:debug(self.name,self.id)
  
  print("<font color='red'>This is a test message in red</font>")
  print("<font color='chartreuse2'>This is a test message in chartreuse2</font>")
  print("<font color='fopp'>This is a test message in fopp</font>")

end