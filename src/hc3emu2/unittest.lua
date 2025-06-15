
local testFuns = {}

function testFuns.equal(a,b) return table.equal(a,b) end

local function tablematch(a,b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= 'table' then return a==b end
  for k,v in pairs(b) do
    if a[k]~=nil then return tablematch(a[k],v)
    else return false end
  end
end
testFuns.tablematch = tablematch

local function checkWrap(f)
  return function(...)
    local stat,res = pcall(f,...)
    if not stat then 
      testFuns._fibaro.error("Test",testFuns.test,"Error",res)
    elseif not res then
      testFuns._fibaro.error("Test",testFuns.test,"Error",res)
    else
      testFuns._fibaro.trace("Test",testFuns.test,"OK")
    end
  end
end

for k,v in pairs(testFuns) do
  testFuns[k] = checkWrap(v)
end

local function runTest(test,fibaro)
  testFuns._fibaro = fibaro
  test(testFuns)
end

return {
  runTest = runTest,
}