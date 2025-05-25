--%%name=RPCtest
--%%file=$hc3emu2.lib.rpc:rpclib
--%%debug=files:true
------------ENDOFHEADERS------------


local function startClient()
local client = [[
--%%name=RPCclient
--%%file=$hc3emu2.lib.rpc:rpclib
--%% breakOnLoad=true

function QuickApp:onInit()
  local server = api.get("/devices?name=RPCtest")
  local serverId = server[1].id
  print("RPC server id",serverId)
  local Foo = fibaro.rpc(serverId,"Foo")
  print("Sum 4+6 =",Foo(4,6))
end

]]
  fibaro.hc3emu.lib.loadQAString(client)
end

function Foo(a,b) return a+b end

function QuickApp:onInit()
  self:debug("QuickApp Initialized", self.name, self.id)
  startClient()
end