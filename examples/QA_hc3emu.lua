local fmt = string.format

local buf = {}
for k,v in pairs(fibaro.hc3emu) do
  buf[#buf+1] = fmt("fibaro.hc3emu.%s = %s",k,tostring(v))
end
table.sort(buf)
print("\n"..table.concat(buf,"\n"))

local buf = {}
for k,v in pairs(fibaro.hc3emu.lua) do
  buf[#buf+1] = fmt("fibaro.hc3emu.lua.%s = %s",k,tostring(v))
end
table.sort(buf)
print("\n"..table.concat(buf,"\n"))