local fmt = string.format
Emulator = Emulator
Emu = Emu

function urlencode(str) -- very useful
  if str then
    str = str:gsub("\n", "\r\n")
    str = str:gsub("([^%w %-%_%.%~])", function(c)
      return ("%%%02X"):format(string.byte(c))
    end)
    str = str:gsub(" ", "%%20")
  end
  return str
end

function table.copy(obj)
  if type(obj) == 'table' then
    local res = {} for k,v in pairs(obj) do res[k] = table.copy(v) end
    return res
  else return obj end
end

local function equal(e1,e2)
  if e1==e2 then return true
  else
    if type(e1) ~= 'table' or type(e2) ~= 'table' then return false
    else
      for k1,v1 in pairs(e1) do if e2[k1] == nil or not equal(v1,e2[k1]) then return false end end
      for k2,_  in pairs(e2) do if e1[k2] == nil then return false end end
      return true
    end
  end
end
table.equal = equal

local function merge(a, b)
  if type(a) == 'table' and type(b) == 'table' then
    for k,v in pairs(b) do if type(v)=='table' and type(a[k] or false)=='table' then merge(a[k],v) else a[k]=v end end
  end
  return a
end

function table.merge(a,b) return merge(table.copy(a),b) end

function table.member(key,tab)
  for i,elm in ipairs(tab) do if key==elm then return i end end
end

function string.starts(str, start) return str:sub(1,#start)==start end

function string.split(inputstr, sep)
  local t={}
  for str in string.gmatch(inputstr, "([^"..(sep or "%s").."]+)") do t[#t+1] = str end
  return t
end

local function readFile(fname,silent)
  local f = io.open(fname, "r")
  if not f and silent then return end
  assert(f, "Cannot open file: " .. fname)
  local code = f:read("*a")
  f:close()
  return code
end

local function eval(prefix,str,expr,typ,dflt,env)
  if str == nil then return dflt end
  local stat,res = pcall(load,"return "..str, "chunk", "t", env)
  if stat then stat,res = pcall(res) end
  if not stat then error(fmt("%s: Invalid value for %s (%s)",prefix,expr,str),2) end
  if typ~=nil and type(res) ~= typ then error(fmt("%s: Invalid type for %s, expected %s got %s (%s)",prefix,expr,typ,type(res),str),2) end
  return res
end

--------- json -----------------
json = require("json") -- Reasonable fast json parser, not to complicated to build...
do
  local copy
  
  local mt = { 
    __toJSON = function (t) 
      local isArray = nil
      if t[1]~=nil then isArray=true 
      elseif next(t)== nil and (getmetatable(t) or {}).__isARRAY then isArray=true end
      t = copy(t) 
      t.__array = isArray
      return t 
    end 
  }
  
  function copy(t)
    local r = {}
    for k, v in pairs(t) do 
      if type(v) == 'table' then
        local m = getmetatable(v) 
        if m then m.__toJSON = mt.__toJSON else setmetatable(v,mt) end
      end 
      r[k] = v
    end
    return r
  end
  
  local encode,decode = json.encode,json.decode
  function json.encode(obj,_)
    local stat,res = pcall(function()
      if obj == nil then return "null" end
      if type(obj) == 'number' then return tostring(obj) end
      if type(obj) == 'string' then return '"'..obj..'"' end
      local omt = getmetatable(obj)
      setmetatable(obj,mt)
      local r = encode(obj,'__toJSON')
      setmetatable(obj,omt)
      return r
    end)
    if not stat then error("json.encode error: "..tostring(res),2) end
    return res
  end
  local function handler(t) if t.__array then t.__array = nil end return t end
  function json.decode(str,_,_) 
    local stat,res = pcall(decode,str,nil,handler) 
    if not stat then 
      local reason = ""
      if str == "" then reason = "Empty string, " end
      if str == nil then reason = "Nil value, " end
      error("json.decode error: "..reason..tostring(res),2) 
    end
    return res
  end
  json.util = {}
  function json.util.InitArray(t) 
    local mt = getmetatable(t) or {}
    mt.__isARRAY=true 
    setmetatable(t,mt) 
    return t
  end
  
end

local escTab = {["\\"]="\\\\",['"']='\\"'}
do
  local sortKeys = {"type","device","deviceID","id","value","oldValue","val","key","arg","event","events","msg","res"}
  local sortOrder={}
  for i,s in ipairs(sortKeys) do sortOrder[s]="\n"..string.char(i+64).." "..s end
  local function keyCompare(a,b)
    local av,bv = sortOrder[a] or a, sortOrder[b] or b
    return av < bv
  end
  
  --gsub("[\\\"]",{["\\"]="\\\\",['"']='\\"'})
  -- our own json encode, as we don't have 'pure' json structs, and sorts keys in order (i.e. "stable" output)
  local function prettyJsonFlat(e0) 
    local res,seen = {},{}
    local function pretty(e)
      local t = type(e)
      if t == 'string' then res[#res+1] = '"' res[#res+1] = e:gsub("[\\\"]",escTab) res[#res+1] = '"'
      elseif t == 'number' then res[#res+1] = e
      elseif t == 'boolean' or t == 'function' or t=='thread' or t=='userdata' then
        if e == json.null then res[#res+1]='null'
        else res[#res+1] = tostring(e) end
      elseif t == 'table' then
        if next(e)==nil then res[#res+1]='{}'
        elseif seen[e] then res[#res+1]="..rec.."
        elseif e[1] or #e>0 then
          seen[e]=true
          res[#res+1] = "[" pretty(e[1])
          for i=2,#e do res[#res+1] = "," pretty(e[i]) end
          res[#res+1] = "]"
        else
          seen[e]=true
          if e._var_  then res[#res+1] = fmt('"%s"',e._str) return end
          local k = {} for key,_ in pairs(e) do k[#k+1] = tostring(key) end
          table.sort(k,keyCompare)
          if #k == 0 then res[#res+1] = "[]" return end
          res[#res+1] = '{'; res[#res+1] = '"' res[#res+1] = k[1]; res[#res+1] = '":' t = k[1] pretty(e[t])
          for i=2,#k do
            res[#res+1] = ',"' res[#res+1] = k[i]; res[#res+1] = '":' t = k[i] pretty(e[t])
          end
          res[#res+1] = '}'
        end
      elseif e == nil then res[#res+1]='null'
      else error("bad json expr:"..tostring(e)) end
    end
    pretty(e0)
    return table.concat(res)
  end
  json.encodeFast = prettyJsonFlat
end

do -- Used for print device table structs - sortorder for device structs
  local sortKeys = {
    'id','name','value','roomID','type','baseType','enabled','visible','isPlugin','parentId','viewXml','configXml',
    'interfaces','hasUIView','properties','view', 'actions','created','modified','sortOrder'
  }
  local sortOrder={}
  for i,s in ipairs(sortKeys) do sortOrder[s]="\n"..string.char(i+64).." "..s end
  local function keyCompare(a,b)
    local av,bv = sortOrder[a] or a, sortOrder[b] or b
    return av < bv
  end
  
  local function prettyJsonStruct(t0)
    local res = {}
    local function isArray(t) return type(t)=='table' and t[1] end
    local function isEmpty(t) return type(t)=='table' and next(t)==nil end
    local function printf(tab,fm,...) res[#res+1] = string.rep(' ',tab)..fmt(fm,...) end
    local function pretty(tab,t,key)
      if type(t)=='table' then
        if isEmpty(t) then printf(0,"[]") return end
        if isArray(t) then
          printf(key and tab or 0,"[\n")
          for i,k in ipairs(t) do
            local _ = pretty(tab+1,k,true)
            if i ~= #t then printf(0,',') end
            printf(tab+1,'\n')
          end
          printf(tab,"]")
          return true
        end
        local r = {}
        for k,_ in pairs(t) do r[#r+1]=k end
        table.sort(r,keyCompare)
        printf(key and tab or 0,"{\n")
        for i,k in ipairs(r) do
          printf(tab+1,'"%s":',k)
          local _ =  pretty(tab+1,t[k])
          if i ~= #r then printf(0,',') end
          printf(tab+1,'\n')
        end
        printf(tab,"}")
        return true
      elseif type(t)=='number' then
        printf(key and tab or 0,"%s",t)
      elseif type(t)=='boolean' then
        printf(key and tab or 0,"%s",t and 'true' or 'false')
      elseif type(t)=='string' then
        printf(key and tab or 0,'"%s"',t:gsub("[\\\"]",escTab))
      elseif type(t)=='userdata' then
        if t == json.null then printf(key and tab or 0,"null") end
      end
    end
    pretty(0,t0,true)
    return table.concat(res,"")
  end
  json.encodeFormated = prettyJsonStruct
end

local function formatArgs(...)
    local args = {...}
    for i,v in ipairs(args) do 
      if type(v)=='table' then
        if v[1]=='_EV' then args[i] = v[2](table.unpack(v,3))
        else args[i] = json.encodeFast(v) end
      end
    end
    return table.unpack(args)
end

------------------- sunCalc -------------------
local sunCalc
do
  ---@return number
  local function sunturnTime(date, rising, latitude, longitude, zenith, local_offset)
    local rad,deg,floor = math.rad,math.deg,math.floor
    local frac = function(n) return n - floor(n) end
    local cos = function(d) return math.cos(rad(d)) end
    local acos = function(d) return deg(math.acos(d)) end
    local sin = function(d) return math.sin(rad(d)) end
    local asin = function(d) return deg(math.asin(d)) end
    local tan = function(d) return math.tan(rad(d)) end
    local atan = function(d) return deg(math.atan(d)) end
    
    local function day_of_year(date2)
      local n1 = floor(275 * date2.month / 9)
      local n2 = floor((date2.month + 9) / 12)
      local n3 = (1 + floor((date2.year - 4 * floor(date2.year / 4) + 2) / 3))
      return n1 - (n2 * n3) + date2.day - 30
    end
    
    local function fit_into_range(val, min, max)
      local range,count = max - min,nil
      if val < min then count = floor((min - val) / range) + 1; return val + count * range
      elseif val >= max then count = floor((val - max) / range) + 1; return val - count * range
      else return val end
    end
    
    -- Convert the longitude to hour value and calculate an approximate time
    local n,lng_hour,t =  day_of_year(date), longitude / 15,nil
    if rising then t = n + ((6 - lng_hour) / 24) -- Rising time is desired
    else t = n + ((18 - lng_hour) / 24) end -- Setting time is desired
    local M = (0.9856 * t) - 3.289 -- Calculate the Sun^s mean anomaly
    -- Calculate the Sun^s true longitude
    local L = fit_into_range(M + (1.916 * sin(M)) + (0.020 * sin(2 * M)) + 282.634, 0, 360)
    -- Calculate the Sun^s right ascension
    local RA = fit_into_range(atan(0.91764 * tan(L)), 0, 360)
    -- Right ascension value needs to be in the same quadrant as L
    local Lquadrant = floor(L / 90) * 90
    local RAquadrant = floor(RA / 90) * 90
    RA = RA + Lquadrant - RAquadrant; RA = RA / 15 -- Right ascension value needs to be converted into hours
    local sinDec = 0.39782 * sin(L) -- Calculate the Sun's declination
    local cosDec = cos(asin(sinDec))
    local cosH = (cos(zenith) - (sinDec * sin(latitude))) / (cosDec * cos(latitude)) -- Calculate the Sun^s local hour angle
    if rising and cosH > 1 then return -1 --"N/R" -- The sun never rises on this location on the specified date
    elseif cosH < -1 then return -1 end --"N/S" end -- The sun never sets on this location on the specified date
    
    local H -- Finish calculating H and convert into hours
    if rising then H = 360 - acos(cosH)
    else H = acos(cosH) end
    H = H / 15
    local T = H + RA - (0.06571 * t) - 6.622 -- Calculate local mean time of rising/setting
    local UT = fit_into_range(T - lng_hour, 0, 24) -- Adjust back to UTC
    local LT = UT + local_offset -- Convert UT value to local time zone of latitude/longitude
    ---@diagnostic disable-next-line: missing-fields
    return os.time({day = date.day,month = date.month,year = date.year,hour = floor(LT),min = math.modf(frac(LT) * 60)})
  end
  
  ---@diagnostic disable-next-line: param-type-mismatch
  local function getTimezone(now) return os.difftime(now, os.time(os.date("!*t", now))) end
  
  function sunCalc(time,latitude,longitude)
    local loc = Emu.api.get("/settings/location")
    local lat = latitude or loc.latitude or 0
    local lon = longitude or loc.longitude or 0
    time = time or Emu.lib.userTime()
    local utc = getTimezone(time) / 3600
    local zenith,zenith_twilight = 90.83, 96.0 -- sunset/sunrise 90°50′, civil twilight 96°0′
    
    local date = os.date("*t",time or os.time())
    if date.isdst then utc = utc + 1 end
    local rise_time = os.date("*t", sunturnTime(date, true, lat, lon, zenith, utc))
    local set_time = os.date("*t", sunturnTime(date, false, lat, lon, zenith, utc))
    -- local rise_time_t = os.date("*t", sunturnTime(date, true, lat, lon, zenith_twilight, utc))
    -- local set_time_t = os.date("*t", sunturnTime(date, false, lat, lon, zenith_twilight, utc))
    local sunrise = fmt("%.2d:%.2d", rise_time.hour, rise_time.min)
    local sunset = fmt("%.2d:%.2d", set_time.hour, set_time.min)
    -- local sunrise_t = fmt("%.2d:%.2d", rise_time_t.hour, rise_time_t.min)
    -- local sunset_t = fmt("%.2d:%.2d", set_time_t.hour, set_time_t.min)
    return sunrise, sunset --, sunrise_t, sunset_t
  end
end 

---------------------------------------------
local copas = require("copas")
local socket = require("socket")
local fmt = string.format

---@class SocketServer
---@field name string
---@field btag string
---@field ip string
---@field port number
---@field started boolean
---@field handler fun(self:SocketServer, io:table)
SocketServer = {}
class'SocketServer'
function SocketServer:__init(ip,port,pi,name,debug)
  self.name = name or "socket server"
  self.btag = debug or "server"
  self.ip = ip
  self.port = port
  function self:start()
    self.started = true
    Emu:DEBUGF('server',"Opening %s socket at %s:%s",self.name,self.ip,self.port)
    Emu.stats.ports[self.port] = true
    local function handle(skt)
      local name = skt:getpeername() or "N/A"
      Emu:DEBUGF(self.btag,"%s connection from: %s",self.name,name)
      local function read(len) return copas.receive(skt,len) end
      local function write(str) return copas.send(skt,str) end
      local function close() return copas.close(skt) end
      self:handler({skt=skt,read=read,write=write,close=close})
      Emu:DEBUGF(self.btag,"Connection closed: %s",name)
    end
    local server,err = socket.bind('*', port)
    if not server then error(fmt("%s failed open socket %s: %s",self.name,self.port,tostring(err))) end
    copas.addserver(server, Emulator.wrapFun(handle,pi,name))
  end
end

---------------------------------------
return {
  sunCalc = sunCalc,
  readFile = readFile,
  eval = eval,
  formatArgs = formatArgs,
}