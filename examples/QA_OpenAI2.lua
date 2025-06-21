--%%name=QA_OpenAI
--%%type=com.fibaro.genericDevice
--%%webui=true

--%%var=OPENAI_API_KEY:config.OPENAI_API_KEY

--%%file=$hc3emu2.lib.eventmgr,event

local _VERSION = "0.3"
local function printf(fmt,...) print(string.format(fmt,...)) end
local function printfc(c,fmt,...) printf("<font color='%s'>%s</font>",c,string.format(fmt,...)) end

local fibaro2 = {} -- fake fibaro2 to avoid chaos :-) 
function fibaro2.call(id,method,...)
  print("fibaro.call",id,method,json.encode({...}))
end

---@class Chat
Chat = {}
class 'Chat'
function Chat:__init(llm,args)
  self.llm = llm
  self.showThink = args.showThink
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
   -- tools = next(toolList) and toolList or nil,
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
        local think,result = answer:match("<think>[%s%c]*(.-)%s*</think>[%s%c]*(.-)$")
        if think == nil then think = ""; result = answer end
        if self.showThink and think ~= "" then
          printfc("blue",think)
        end
        table.insert(self.data.messages,{role = "assistant", content = answer})
        self.result = result
        return ccb(self,status)
      end
    else return ccb(nil,status) end
  end)
end

function Chat:__tostring() return self.result or "" end

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

local pricing = {
  ["gpt-4.1-mini"] = {
    prompt = 0.40,
    completion = 1.60
  },
}

local function openai_api_calculate_cost(usage,model)
  local model_pricing = pricing[model] or {prompt = 0.0, completion = 0.0}
  
  local prompt_cost = usage['prompt_tokens'] * model_pricing['prompt'] / 1000000
  local completion_cost = usage['completion_tokens'] * model_pricing['completion'] / 1000000
  
  local total_cost = prompt_cost + completion_cost
  printf("\nTokens used:  %s prompt + %s completion = %s tokens",usage.prompt_tokens,usage.completion_tokens,usage.total_tokens)
  printf("Total cost for %s: %.8f US cents",model,total_cost*100)
  
  return total_cost
end

local systemPrompt = [[
  You are an Home Automation Assistants being an expert in creating understanding users automation request and turning them into JSON tasks.
  
  The user will make a request and the assistant/AI answers with JSON.
  
  User requests can come in 3 categories
  # Immediate action
  Carry out a request to do something immediately.
  Ex. 
  User: Please turn on the lamp in the kitchen
  AI: { "type":"action","action","turnOn","device":"kitchen","summary":"Light in kitchen turned on"}
  
  Devices can be described with a place, name, type, and role, any of these can be used to identify the device.
  Every device has an id. Here is a list of devices:
  {{devices}}

  Always use the device id in the action response, and <unknown> if you can't resolve the id. Never use the name of the device.
  
  # Trigger tasks
  Tasks that should be carried out if some device in the home changes state
  Ex.
  User: When the sensor in the kitchen is breached turn on the light in the kitchen
  AI: { "type":"trigger","summary":"turn on kitchen lamp when kitchen sensor is breached"}
  User: The sensor in the kitchen is now breached
  AI: { "type":"action","action","turnOn","device":"kitchen","summary":"Light in kitchen turned on because sensor in kitchen is breached"}
  
  # Scheduled tasks
  Tasks that should be carried out in the future.
  Example:
  User: Turn on the light in the kitchen every morning except for weekends"
  AI: { "type":"schedule","time":"07:00","recurring":"daily","request":"Turn on the light in the kitchen except for weekends","summary":"Light in kitchen schedled for every morning except weekends"}
  Note that recurring can be "hourly", "daily", "weekly". If "weekly" is specified an extra parameter "days" with a comma separated list of the relevant days of the week is required.
  User: Turn on the light in the bedroom every Monday and Friday morning"
  AI: { "type":"schedule","time":"07:00","recurring":"weekly","days":["Monday,Friday"],"request":"Turn on the light in the bedroom","summary":"Light in bedroom scheduled for every Monday and Friday morning"}

  User: The sensor in the kitchen is now breached and it's Wednesday 07:00"
  AI: { "type":"action","action","turnOn","device":"kitchen","summary":"Light in kitchen turned on"}
  User: The sensor in the kitchen is now breached and it's Saturday 07:00"
  AI: { "type":"response","summary":"Light not turned on because it's a Saturday"}
  
  Time should be specified as 
  - HH:MM
  - sunset+MM
  - sunset-MM
  - sunrise+MM
  - sunrise+MM
  
  request should be a task in english that is asked to the assistant to carry out later.
  Example:
  User: Dim the kitchen light every evening
  AI: { "type":"schedule","time":"sunset-60","recurring":"daily,"request":"Dim kitchen light","summary":"Dim the kitchen light every evening"}

  Always use the device id in the task request, and <unknown> if you can't resolve the id. Never use the name.
  If user specifies time as afternoon, or night, or before sunset, make an good assumption what it means in the format above.
  Always include a summary of the task in the response.

  --------------
  Only respond in JSON
]]

---@class AI
AI = {}
class 'AI'
function AI:__init(args)
  self.model = args.model
  self.showThink = args.showThink
  local api = args.api
  local key = args.api_key
  self:debug("HC3AI",_VERSION)
  self:debug("API",api,"model",self.model)
  self.llm = LLM(api,{api_key=key})
  self.rules = args.rules or {}
  self.em = fibaro.EventMgr()
end

function AI:debug(...) fibaro.debug(__TAG,...) end

function AI:addDevices(devices)
  self.userDevices = {}
  if type(devices) == 'string' then devices = {devices} end
  for i=1,#devices do 
    local d = devices[i]
    local name,id = d:match("^(.-):(%d+)$")
    id = tonumber(id)
    assert(name and id,string.format("Invalid device: %s",d))
    self.userDevices[id] = name
    devices[id] = "- "..d
  end
  self.devices = table.concat(devices,"\n")
end

function AI:addRules(rules)
  if type(rules) == 'string' then rules = {rules} end
  for _,rule in ipairs(rules) do table.insert(self.rules,rule) end
end

function AI:send(message,ccb) return self.chat:send(message,ccb) end

function AI:runChat(ccb)
  local system = systemPrompt:gsub("{{devices}}",self.devices or "")
  local chat = self.llm:startChat({
    showThink = self.showThink,
    model = self.model,
    system = system,
  })
  self.chat = chat 
  self:taskRunner()
  if ccb then self:addTask(ccb) end
end

local taskQueue,runner = {},nil
function AI:taskRunner()
  local task = table.remove(taskQueue,1)
  if not task then runner=nil return end
  runner = setTimeout(function()
    self:runTask(task,function() self:taskRunner() end)
  end,0)
end
function AI:addTask(task)
  if type(task) ~= 'table' then task = {task} end
  for _,t in ipairs(task) do table.insert(taskQueue,t) end
  if self.chat and not runner then self:taskRunner() end
end

function AI:runTask(task,cb)
   if type(task) == 'function' then pcall(task) if cb then cb() end return end
  printfc('yellow',"User> %s",task)
  self.chat:send(task,function(_chat,status)
    if status == 200 then
      local stat,res = pcall(function()
        local txt = tostring(_chat)
        local res = json.decode(txt)
        printfc('green',"AI> %s",res.summary)
        res.summary = nil
        self:runCode(res)
      end)
      if not stat then printfc('red',"Error> %s",res) end
    else
      printfc('red',"Error> %s",status)
    end
    if cb then cb() end
  end)
end

local actions = {}
function actions.turnOn(args) fibaro2.call(tonumber(args.device),"turnOn") end
function actions.turnOff(args) fibaro2.call(tonumber(args.device),"turnOff") end
function actions.setValue(args) fibaro2.call(tonumber(args.device),"setValue",args.value) end

local _schedules = {}
local schedulerStarted = false
local function addSchedule(ai,time,schedule)
  table.insert(_schedules,{time=time,fun=schedule}) -- To be scheduled at midnight
  --print("Schedule",time)
  ai.em:post({type='schedule',time=time,fun=schedule},"t/"..time)
end


local function startScheduler(ai)
  schedulerStarted = true
  ai.em:addHandler({type='schedule'},function(e)
    pcall(e.fun)
  end)
  local nxt = fibaro.midnight() + 24*60*60 -- Next midnight
  local function midnight()
    for _,schedule in ipairs(_schedules) do
      --print("Schedule",schedule.time)
      ai.em:post({type='schedule',time=schedule.time,fun=schedule.fun},"t/"..schedule.time)
      pcall(schedule)
    end
    nxt = nxt + 24*60*60
    setTimeout(midnight,(nxt-os.time())*1000)
  end
  setTimeout(midnight,(nxt-os.time())*1000)
end

local function dateStr() return os.date("%A, %Y-%m-%d %H:%M:%S") end

function AI:runCode(code)
  if not schedulerStarted then startScheduler(self) end
  printfc('green',"Code> %s",json.encode(code))
  if code.type == "action" then
    local action = actions[code.action]
    if action then action(code) else printfc('red',"Unknown action> %s",code.action) end
  elseif code.type == "trigger" then
    -- TODO: Record trigger to filter refreshStateEvents
  elseif code.type == "schedule" then
    local time = code.time
    local recurring = code.recurring
    local days = {}
    for _,d in ipairs(code.days or {}) do days[d] = true end
    local request = code.request
    addSchedule(self,time,function()
      local day = os.date("%A")
      if next(days) and not days[day] then return end
      self:addTask(string.format("It's %s. and time is %s. %s.",day,time,request)) 
    end)
  end
end

-----------------------------------------------

function QuickApp:onInit()
  
  local ai = AI{ showThink = true, model = "qwen3:4b", api = "http://macmini:11434/v1" }
  --local ai = AI{ model = "gpt-4.1-mini", api = "https://api.openai.com/v1", api_key=self:getVariable("OPENAI_API_KEY") }
  
  -- Register devices
  ai:addDevices({
    "kitchen sensor:721",
    "kitchen roof lamp:878",
    "bedrom night lamp:432",
    "hall lamp:256",
  })
  
  ai:addTask({
    "turn on kitchen roof lamp on every Saturday morning",
    "turn on night lamp 1 hour after sunset",
    "turn on hall lamp if sensor is breached"
  })
  
  ai._debug = true
  
  ai.em:addHandler({type='device',property='value',value=true},function(e)
    if ai.userDevices[e.id] then -- Only trigger if device is registered
      ai:addTask(string.format("It is %s. Device %s is now breached",dateStr(),e.id))
    end
  end)

  local function start()
    ai.em:post({type='device',id=721,property="value",value=true}) -- Post fake sourcetrigger 
    _emu.lib.speedFor(48)
  end
  
  ai:runChat(start)
  
end
