-- ToDo offline module...
local function setup(Emu)
  local api = Emu.api

  api:add("GET/globalVariables", function(ctx)
  end)
  api:add("GET/globalVariables/<name>", function(ctx)
  end)
  api:add("POST/globalVariables", function(ctx)
  end)
  api:add("PUT/globalVariables/<name>", function(ctx)
  end)
  api:add("DELETE/globalVariables/<name>", function(ctx)
  end)
  api:add("GET/customEvents", function(ctx)
  end)

  api:add("GET/rooms", function(ctx)
  end)
  api:add("GET/rooms/<id>", function(ctx)
  end)
  api:add("POST/rooms", function(ctx)
  end)
  api:add("PUT/rooms/<id>", function(ctx)
  end)
  api:add("DELETE/rooms/<id>", function(ctx)
  end)

  api:add("GET/sections", function(ctx)
  end)
  api:add("GET/sections/<id>", function(ctx)
  end)
  api:add("POST/sections", function(ctx)
  end)
  api:add("PUT/sections/<id>", function(ctx)
  end)
  api:add("DELETE/sections/<id>", function(ctx)
  end)

  api:add("GET/customEvents/<name>", function(ctx)
  end)
  api:add("POST/customEvents", function(ctx)
  end)
  api:add("PUT/customEvents/<name>", function(ctx)
  end)
  api:add("DELETE/customEvents/<name>", function(ctx)
  end)


end







return setup