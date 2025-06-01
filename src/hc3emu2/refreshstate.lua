local copas = require('copas')

local pollerRunning = false
local function refreshStatePoller(queue)
  require("mobdebug").on()
  local path = "/refreshStates"
  local last,events=1,nil
  local suffix = "&lang=en&rand=7784634785"
  while pollerRunning do
    local data, status = queue.emu:HC3Call("GET", (last and path..("?last="..last) or path) .. suffix, nil, true)
    if status ~= 200 then
      if status ~= 'timeout' then
         queue.emu:ERRORF("Failed to get refresh state (exiting): "..tostring(status))
         return
      end
    end
    data = type(data)=='table' and data or {}
    ---@diagnostic disable-next-line: undefined-field
    last = math.floor(data.last) or last
    ---@diagnostic disable-next-line: undefined-field
    events = data.events
    if events ~= nil then
      for _, event in pairs(events) do
         queue.emu:DEBUGF("rawrefresh","RRefresh %s:%s",event.type,{'_EV',json.encodeFast,event.data})
         queue:addEvent(event)
      end
    end
    --if next(data.changes) then print("CHANGE:",json.encode(data.changes)) end
    copas.pause(queue.emu._refreshInterval or 0.01)
  end
end

local filter = { 
  -- GlobalVariableAddedEvent = true, GlobalVariableChangedEvent = true, GlobalVariableRemovedEvent = true, RoomModifiedEvent = true, 
  -- RoomCreatedEvent = true, RoomRemovedEvent = true, 
  -- SectionModifiedEvent = true, SectionCreatedEvent = true, SectionRemovedEvent = true,
  -- CustomEventModifiedEvent = true, CustomEventCreatedEvent = true, CustomEventRemovedEvent = true,
  -- DeviceModifiedEvent = true, DevicePropertyUpdatedEvent = true,
  -- CentralSceneEvent = true
}

EventQueue = EventQueue
class('EventQueue')

function EventQueue:__init(emu)
  self.emu = emu
  self.queue = {}
  self.listeners = {}
  self.first = 0
  self.last = 1
end

function EventQueue:addEvent(event,exclListener)
  if not filter[event.type] then self.emu:DEBUGF("refresh","Refresh %s:%s",event.type,{'_EV',json.encodeFast,event.data}) end
  if not event.created then event.created = os.time() end
  self.first = self.first + 1
  self.queue[self.first] = event
  if self.first-self.last > 250 then
    self.queue[self.last] = nil
    self.last = self.last + 1
  end
  for l,_ in pairs(self.listeners) do 
    if l ~= exclListener then l(event) end 
  end
end
function EventQueue:addListener(listener) 
  self.listeners[listener] = true
  if not self.emu.offline then
    if not pollerRunning then
      pollerRunning = true
      self.emu:process({fun=refreshStatePoller,args={self}})
    end
  end
end
function EventQueue:removeListener(listener) 
  self.listeners[listener] = nil
  if next(self.listeners)==nil then
    pollerRunning = false
  end
end

return EventQueue