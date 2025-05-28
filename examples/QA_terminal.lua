--%%name=Terminal
--%%type=com.fibaro.binarySwitch
--%%plugin=$hc3emu2.plugin.terminal
--%%nodebug=true

local sys = fibaro.hc3emu.lua.require("system")
local io = fibaro.hc3emu.lua.io
local load = fibaro.hc3emu.lua.load
local term = fibaro.hc3emu.plugin
local pr = fibaro.hc3emu.lua.print

local VERSION = "v0.5"

function QuickApp:onInit()
  print("Hc3Emu Terminal",VERSION)
  setInterval(function() print("Ping") end,3000)
  term.setExitKey(27)
  local prompt = "hc3emu>"
  local inputLine = prompt -- initialize input line with prompt
  local function ioprint(str) io.write(str) io.flush() end
  local function ioprintln(str) io.write(str.."\n") io.flush() end
  function _emu.__printHook(str) 
    ioprintln("\r"..str) -- print the string with a newline
    ioprint(inputLine)
  end
  io.write(prompt) -- write prompt to terminal
  io.flush() -- flush output to terminal
  term.setKeyHandler(function(key, keytype)
    if keytype == "char" then
      -- just a key
      local b = key:byte()
      if b < 32 then
        key = tostring(b) -- replace control characters with a simple "." to not mess up the screen
      end

      if b == 10 then
        io.write('\n')
        local cmd = "return "..inputLine:sub(#prompt + 1) -- wrap input in a return to evaluate it
        local func, err = load(cmd, "input", "t", _G)
        if not func then
          ioprintln(err)
        else
          local ok, result,code = pcall(func)
          ioprintln(type(result)=='table' and json.encodeFormated(result) or tostring(result))
        end
        inputLine = prompt -- reset input line
      elseif b == 8 or b == 127 then
        -- backspace or delete
        if #inputLine > #prompt then
          inputLine = inputLine:sub(1, -2) -- remove last character
          io.write('\b ') -- move back, write space, move back again
        end
      else
        inputLine = inputLine .. key
      end
      io.write('\r')
      io.write(inputLine) -- write to terminal
      io.flush() -- flush output to terminal

    elseif keytype == "ansi" then
      -- we got an ANSI sequence
      local seq = { key:byte(1, #key) }
      print("ANSI sequence received: " .. key:sub(2,-1), "(bytes: " .. table.concat(seq, ", ")..")")
      
    else
      print("unknown key type received: " .. tostring(keytype))
    end
  end)
end
