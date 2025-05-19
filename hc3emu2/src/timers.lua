local fmt = string.format
local copas = require("copas")
local socket = require("socket")
local mobdebug = require("mobdebug")

---------- Time functions --------------------------
--- User has own time that can be an offset to real time
local orgTime,orgDate,timeOffset = os.time,os.date,0

local function round(x) return math.floor(x+0.5) end
local function userTime(a) 
  return a == nil and round(socket.gettime() + timeOffset) or orgTime(a) 
end
local function userMilli() return socket.gettime() + timeOffset end
local function userDate(a, b) 
  return b == nil and orgDate(a, userTime()) or orgDate(a, round(b)) 
end
local function milliClock() return socket.gettime() end

local function getTimeOffset() return timeOffset end
local function setTimeOffset(offs) timeOffset = offs end

-----------------------------------
local scheduler

local function midnightLoop()
  local d = userDate("*t")
  d.hour,d.min,d.sec = 24,0,0
  local midnxt = userTime(d)
  local function loop()
    Emu:post({type="midnight"})
    local d = userDate("*t")
    d.hour,d.min,d.sec = 24,0,0
    midnxt = userTime(d)
    scheduler:setTimeout(loop,(midnxt-userTime())*1000)
  end
  scheduler:setTimeout(loop,(midnxt-userTime())*1000)
end

local function parseTime(str)
  local D,h = str:match("^(.*) ([%d:]*)$")
  if D == nil and str:match("^[%d/]+$") then D,h = str,os.date("%H:%M:%S")
  elseif D == nil and str:match("^[%d:]+$") then D,h = os.date("%Y/%m/%d"),str
  elseif D == nil then error("Bad time value: "..str) end
  local y,m,d = D:match("(%d+)/(%d+)/?(%d*)")
  if d == "" then y,m,d = os.date("%Y"),y,m end
  local H,M,S = h:match("(%d+):(%d+):?(%d*)")
  if S == "" then H,M,S = H,M,0 end
  assert(y and m and d and H and M and S,"Bad time value: "..str)
  return os.time({year=y,month=m,day=d,hour=H,min=M,sec=S})
end

local function setTime(t,update)
  if type(t) == 'string' then t = parseTime(t) end
  timeOffset = t - orgTime() 
  if update ~= false then Emu:post({type='time_changed'}) end
  Emu:DEBUGF('info',"Time set to %s",userDate("%c"))
end

local function createQueue()
  local self = {}
  local times = nil -- linked list of sorted timers
  
  function self:add(t,fun,id)
    local v = nil
    v = {time=t,fun=fun,id=id}
    if not times then times = v return v end
    if t < times.time then
      times.prev = v
      v.next = times
      times = v
      return v
    end
    local p = times
    while p.next and p.next.time < t do p = p.next end
    v.next = p.next
    if p.next then p.next.prev = v end
    p.next = v
    v.prev = p
    return v
  end
  
  function self:remove(v)
    if v and not v.dead then
      v.dead = true
      if v.prev == nil then
        times = v.next
        if times then times.prev = nil end
      elseif v.next == nil then
        v.prev.next = nil
      else
        v.prev.next = v.next
        v.next.prev = v.prev
      end
    end
  end
  
  function self:pop() local t = times; if times then times.dead=true  times = times.next end return t end
  function self:peek() return times end
  return self
end

local timers = {}
local timerId = 0

Master = Master
class 'Master'
function Master:__init()
  self.queue = createQueue()
end
function Master:add(t,fun,id) 
  local ref = self.queue:add(t,fun) 
  copas.wakeup(self.co) 
  return ref
end
function Master:remove(t) 
  self.queue:remove(t) 
end
function Master:pop()
  local v = self.queue:pop()
  if v then
    timers[tostring(v.id)] = nil
  end
  return v
end
function Master:peek() return self.queue:peek() end
function Master:speed(flag)
  self._speed = flag
  copas.wakeup(self.co)
end
function Master:speedFor(hours,cb)
  self._speed = true
  self:setTimeout(function() 
    if cb then pcall(cb) end self:speed(false)
  end, 1000*60*60*hours)
  copas.wakeup(self.co)
end
function Master:normalTick()
  local now = userMilli()
  local v = self:peek()
  if not v then copas.pauseforever(self.co)
  elseif v.time > now then
    copas.pause(v.time-now)
  else
    self:pop()
    local stat,err = pcall(v.fun)
    v.dead=true
  end
end
function Master:speedTick()
  local v = self:pop()
  if not v then copas.pauseforever(self.co)
  else
    timeOffset = v.time - copas.gettime()
    pcall(v.fun)
    v.dead=true
    copas.pause(0.001)
  end
end
function Master:run()
  local function loop()
    mobdebug.on()
    while true do
      if self._speed then 
        self:speedTick()
      else
        self:normalTick()
      end
    end
  end
  self.co = copas.addthread(loop)
end

function Master:setTimeout(fun,ms)
  local id = timerId; timerId = timerId + 1
  local ref = self:add(userMilli()+ms/1000,fun,id)
  timers[tostring(id)] = ref
  return id
end

function Master:clearTimeout(ref)
  local v = timers[tostring(ref)]
  if v and not v.interval then
    self:remove(v)
    timers[tostring(ref)] = nil
  end
end

function Master:setInterval(fun,ms)
  local ref
  local function loop()
    if ref.cancelled then return end
    fun()
    if ref.cancelled then return end
    ref.ref = self:setTimeout(loop,ms)
  end
  ref = {ref=self:setTimeout(loop,ms),interval=true}
  local id = timerId; timerId = timerId + 1
  timers[tostring(id)] = ref
  return id
end

function Master:clearInterval(ref)
  local v = timers[tostring(ref)]
  if v and v.interval then
    v.cancelled = true
    self:clearTimeout(v.ref)
    timers[tostring(ref)] = nil
  end
end

scheduler = Master()
------------------------------------------------------
local function proc(fun,pi,name)
  return function(...)
    return Emu:process({fun=fun,pi=pi,typ=name,args={...}})
  end
end

function Emu:setTimeout(fun, delay, pi) 
  local f = proc(fun,pi,"setTimeout")
  return scheduler:setTimeout(f,delay)
end
function Emu:clearTimeout(ref) scheduler:clearTimeout(ref) end
function Emu:setInterval(fun, delay, pi) 
  local f = proc(fun,pi,"setInterval")
  return scheduler:setInterval(f,delay)
end
function Emu:clearInterval(ref) scheduler:clearInterval(ref) end

return {
  setTime = setTime,
  userTime = userTime,
  userMilli = userMilli,
  userDate = userDate,
  milliClock = milliClock,
  getTimeOffset = getTimeOffset,
  setTimeOffset = setTimeOffset,
  midnightLoop = midnightLoop,
  parseTime = parseTime,
  startScheduler = function() scheduler:run() end,
  speedFor = function(hours,cb) scheduler:speedFor(hours,cb) end,
  speed = function(flag) scheduler:speed(flag) end,
}
