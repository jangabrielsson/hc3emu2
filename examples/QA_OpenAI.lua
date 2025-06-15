--%%name=QA_OpenAI
--%%type=com.fibaro.genericDevice
--%%webui=true

--%%var=OPENAI_API_KEY:config.OPENAI_API_KEY

local function printf(fmt,...) print(string.format(fmt,...)) end

local fibaro2 = {}
function fibaro2.call(id,method,...)
  print("fibaro2.call",id,method,...)
end

---@class Chat
Chat = {}
class 'Chat'
function Chat:__init(llm,args)
  self.llm = llm
  self.stripThink = args.stripThink
  local _tools = {}
  self._tools = _tools
  local toolList = {}
  self.tools = setmetatable({},{
    __newindex = function(t,k,v) 
      if type(v) == 'table' then _tools[k] = v
      elseif type(v) == 'function' then
        local info = _tools[k]
        local func = {
          type = 'func'..'tion',
          ['func'..'tion'] = {
            name = k,
            description = info.description,
            parameters = info.params and next(info.params) and {
              type ='object',
              properties = info.params,
              required = info.required
            } or {}
          },
        }
        _tools[k] = v
        table.insert(toolList,func)
      end
    end
  })
  self.data = {
    model = args.model,
    messages = {},
    tools = toolList,
  }
  if args.system then table.insert(self.data.messages,{role = "system", content = args.system}) end
  if args.user then table.insert(self.data.messages,{role = "user", content = args.user}) end
end

local totalUsage = {prompt_tokens = 0, completion_tokens = 0, total_tokens = 0}
function Chat:send(message,ccb)
  if message then table.insert(self.data.messages,{role = "user", content = message}) end
  self.llm:request("POST","/chat/completions",self.data,function(result,status)
    if result ~= nil then
      if result.usage then 
        totalUsage.prompt_tokens = totalUsage.prompt_tokens + result.usage.prompt_tokens
        totalUsage.completion_tokens = totalUsage.completion_tokens + result.usage.completion_tokens
        totalUsage.total_tokens = totalUsage.total_tokens + result.usage.total_tokens
      end
      local choice = result.choices[1]
      local finish_reason = choice.finish_reason
      if finish_reason == 'tool_calls' then 
        local results = self.llm:handleToolCall(self,choice.message.tool_calls)
        local am = choice.message
        if type(am.content) == 'userdata' then am.content = nil end
        if type(am.refusal) == 'userdata' then am.refusal = nil end
        if type(am.annotations) == 'table' and next(am.annotations)==nil then am.annotations=nil end
        table.insert(self.data.messages,am)
        for _,r in ipairs(results) do table.insert(self.data.messages,r) end
        self:send(nil,ccb)
      else
        local answer = choice.message.content
        if self.stripThink then
          answer = answer:gsub("\n*<think>.-</think>\n*","")
        end
        table.insert(self.data.messages,{role = "assistant", content = answer})
        return ccb(self,status)
      end
    else return ccb(nil,status) end
  end)
end

function Chat:__tostring() return self.data.messages[#self.data.messages].content end

---@class LLM
LLM = {}
class 'LLM'
function LLM:__init(url,args)
  args = args or {}
  self.url = url
  self._debug = false
  self.key = args.api_key
end

function LLM:debug(message)
  if self._debug then print(message) end
end

function LLM:run(ccb)
  self:models(ccb)
end

function LLM:models(ccb)
  local function cb(result)
    if result ~= nil then
      local models = {}
      for _,model in ipairs(result) do models[model.id] = model end
      self.models = models
      ccb(models)
    else error("Failed to get models") end
  end
  self:request("GET","/models",nil,cb)
end

function LLM:request(method,path,body,cb)
  self:debug("Calling "..self.url..path)
  local key = self.key or "ABC123"
  net.HTTPClient():request(self.url..path,{
    options = {
      timeout = 5*60*1000,
      method = method,
      headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer "..key,
      },
      data = body and json.encode(body) or nil,
    },
    success = function(response)
      if response.status == 200 then
        self:debug("Response: "..response.data)
        local result = json.decode(response.data)
        if cb then cb(result,response.status) end
      else cb(nil,response.status) end
    end,
    error = function(err)
      cb(nil,err)
    end
  })
end

function LLM:startChat(args) return Chat(self,args) end

function LLM:handleToolCall(chat,tool_calls)
  local results = {}
  for _,call in ipairs(tool_calls) do
    local func = call['func'..'tion']
    self:debug("tool call: "..func.name)
    local id = call.id
    local stat,result = pcall(chat._tools[func.name],(json.decode(func.arguments)))
    table.insert(results,{role='tool',tool_call_id=id,content=(json.encode(result))})
  end
  return results
end

function QuickApp:addTools(chat)
  local Tools = chat.tools
  Tools.get_named_device = {
    description = "This is a function that returns a device object given its name",
    params = {name = {type = 'string', description = 'The device name'}}
  }
  function Tools.get_named_device(args)
    print("get_named_device",args.name)
    local devices = api.get("/devices?name="..args.name)
    return devices
  end
  
  Tools.device_name_to_id = {
    description = "This is a function that returns the id for a device given its name",
    params = {name = {type = 'string', description = 'The device name'}}
  }
  function Tools.device_name_to_id(args)
    print("device_name_to_id",args.name)
    local devices = api.get("/devices?name="..args.name)
    return (devices or {})[1] and (devices or {})[1].id or nil
  end

  Tools.get_devices = {
    description = "This is a function that returns all device objects",
    params = {}
  }
  function Tools.get_devices()
    print("get_devices")
    local devices = api.get("/devices")
    return devices
  end
  
  Tools.device_action = {
    description = "This is a function that turns on or off a device, given the action parameter",
    params = {
      id = {type = 'number', description = 'The device id. Must be a number.'},
      action = {type = 'string', description = 'The action to perform, on or off', enum = {'on', 'off'}},
    }
  }
  function Tools.device_action(args)
    local id = args.id
    local action = args.action
    fibaro2.call(id,action == 'on' and 'turnOn' or 'turnOff')
    return "OK"
  end

  Tools.schedule_task= {
    description = "Schedule a task to run at a later date and time. The task is a tool call, and the arguments are in plain json format.",
    params = {
      name = {type = 'string', description = 'Name of the tool to call'},
      arguments = {type = 'string', description = 'The arguments in plain json format to pass to the tool.'},
      time = {type = 'string', description = 'The time to schedule the tool call in the format YYYY-MM-DD HH:MM:SS'},
    }
  }
  function Tools.schedule_task(args)
    print("schedule_action",json.encode(args))
    return "OK"
  end

  Tools.get_current_date_and_time = {
    description = "Returns the current data and time in the format YYYY-MM-DD HH:MM:SS",
    params = {}
  }
  function Tools.get_current_date_and_time() print("get_current_date_and_time") return os.date("%Y-%m-%d %H:%M:%S") end 
end

local pricing = {
  ["gpt-4.1-mini"] = {
      prompt = 0.40,
      completion = 1.60
  },
}

local function openai_api_calculate_cost(usage,model)
    local model_pricing = pricing[model]

    local prompt_cost = usage['prompt_tokens'] * model_pricing['prompt'] / 1000000
    local completion_cost = usage['completion_tokens'] * model_pricing['completion'] / 1000000

    local total_cost = prompt_cost + completion_cost
    printf("\nTokens used:  %s prompt + %s completion = %s tokens",usage.prompt_tokens,usage.completion_tokens,usage.total_tokens)
    printf("Total cost for %s: %.8f US cents",model,total_cost*100)

    return total_cost
end

function QuickApp:onInit()
  local model = "gpt-4.1-mini"
  self:debug("OpenAI","model"..model)
  local key = self:getVariable("OPENAI_API_KEY")
  local llm
  local function start()
    local chat = llm:startChat({
      --stripThink = true,
      model = model,
      --model = "mistral",
      system = [[
      You are an actionable home automation assistant that carry out tasks you are asked about using tool calls. 
      There are 3 main tasks you can do:
      1. Get information about the home automation system. In this case use the appropriate tool call to get relevant information.
      2. Carry out tasks immediate if no specific time is given. In this case use the appropriate tool call to carry out the task.
      3. Schedule tasks for a specific time. In this case use the tool call schedule_task, and the system will carry out the task at the specified time.
      Always resolve device names to device ids using the tool called device_name_to_id before calling the device_action tool.
      You always carry out all tool calls you arrive at before returning to the user.
      You then return a short summary in plain english what tools you have used to solve the task.
      ]], 

    })
    self:addTools(chat)

    chat:send("Please turn off device named kkkk on Saturday afternoon",function(_chat,status)
      print(tostring(_chat),status)
      openai_api_calculate_cost(totalUsage,model)
    end)
  end
  
  --llm = LLM("http://macmini:11434/v1",{api_key=key})
  llm = LLM("https://api.openai.com/v1",{api_key=key})
  --llm._debug = true
  llm:run(start)
end
