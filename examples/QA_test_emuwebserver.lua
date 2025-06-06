--%%TestWebserver

local function request(method, path, data, cb)
  local client = net.HTTPClient()
  client:request("http://localhost:669"..path, {
    options = {
      method = method,
      headers = {
        ["Content-Type"] = "application/json",
        ["Accept"] = "application/json"
      },
      data = data and json.encode(data) or nil,
    },
    success = function(res) cb(res) end,
    error = function(err) fibaro.error(__TAG,err) end
  })
end

function QuickApp:onInit()

  request("GET","/api/devices",nil,function(res)
    self:debug("Init response:", json.encode(res))
  end)

  request("POST","/api/echo",{myData=42},function(res)
    self:debug("Echo response:", json.encode(res))
  end)

end