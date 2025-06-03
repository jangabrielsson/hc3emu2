Emu = Emu
local exports = {}
local fmt = string.format
local copas = require("copas")

local sys = require("system")

local _term = {}
local exitKey = 0x1b  -- default to ESC key

local isSetup = false
local function setupTerm()
  if isSetup then return end
  isSetup = true
  sys.autotermrestore()  -- set up auto restore of terminal settings on exit 
  -- setup Windows console to handle ANSI processing
  _term.of_in = sys.getconsoleflags(io.stdin)
  _term.of_out = sys.getconsoleflags(io.stdout)
  sys.setconsoleflags(io.stdout, sys.getconsoleflags(io.stdout) + sys.COF_VIRTUAL_TERMINAL_PROCESSING)
  sys.setconsoleflags(io.stdin, sys.getconsoleflags(io.stdin) + sys.CIF_VIRTUAL_TERMINAL_INPUT)
  
  -- setup Posix terminal to use non-blocking mode, and disable line-mode
  _term.of_attr = sys.tcgetattr(io.stdin)
  _term.of_block = sys.getnonblock(io.stdin)
  sys.setnonblock(io.stdin, true)
  sys.tcsetattr(io.stdin, sys.TCSANOW, {
    lflag = _term.of_attr.lflag - sys.L_ICANON - sys.L_ECHO, -- disable canonical mode and echo
  })
end

local function shutdownTerm()
  -- Clean up afterwards
  sys.setnonblock(io.stdin, false)
  sys.setconsoleflags(io.stdout, _term.of_out)
  sys.setconsoleflags(io.stdin, _term.of_in)
  sys.tcsetattr(io.stdin, sys.TCSANOW, _term.of_attr)
  sys.setnonblock(io.stdin, _term.of_block)
end

local keyHandler
local isPoller = false
local function keyPoller()
  if isPoller then return end
  isPoller = true
  Emu:process{
    fun = function()
      while true do
        local key, keytype = sys.readansi(0.01)
        if keytype == 'char' and key:byte() == exitKey then
          io.write("Exit key pressed, exiting")
          io.flush()
          shutdownTerm()
          os.exit(0)
        end
        if key and keyHandler then keyHandler(key, keytype) end
        copas.pause(0.01)
      end
    end
  }
end

local VERSION = "v0.5"
local commands = {}

local function terminal()
  print("Hc3Emu Terminal",VERSION,"(Esc to quit)")
  exports.setExitKey(27) -- default to ESC key
  local prompt = "hc3emu>"
  local inputLine = prompt -- initialize input line with prompt
  local function ioprint(str) io.write(str) io.flush() end
  local function ioprintln(str) io.write(str.."\n") io.flush() end
  function Emu.__printHook(str) 
    ioprintln("\r"..str) -- print the string with a newline
    ioprint(inputLine)
  end
  io.write(prompt) -- write prompt to terminal
  io.flush() -- flush output to terminal
  exports.setKeyHandler(function(key, keytype)
    if keytype == "char" then
      -- just a key
      local b = key:byte()
      if b < 32 then
        key = tostring(b) -- replace control characters with a simple "." to not mess up the screen
      end

      if b == 10 or b == 13 then
        io.write('\n')
        local cmd = inputLine:sub(#prompt + 1) -- get command after prompt
        if cmd:sub(1, 1) == "!" then -- execute lua statement
          local luaCmd = cmd:sub(2) -- remove leading '!'
          local func, err = load( "return "..luaCmd, "input", "t", _G)
          if not func then
            ioprintln(err)
          else
            local ok, result,code = pcall(func)
            ioprintln(type(result)=='table' and json.encodeFormated(result) or tostring(result))
          end
        else
          local cmdFun = cmd:match("^[%w_]+") -- get command name
          if commands[cmdFun] then 
            ok, result = pcall(commands[cmdFun],cmd)
            ioprintln(type(result)=='table' and json.encodeFormated(result) or tostring(result))
          else
            ioprintln("Unknown command: " .. cmd)
          end
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

exports.setExitKey = function(b) setupTerm() exitKey = b end
exports.setKeyHandler = function(f) setupTerm() keyPoller() keyHandler = f end
exports.clear = function() print("\027[2J") end
exports.terminal = terminal
exports.terinalCommand = commands
return exports