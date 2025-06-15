# HC3Emu2 API Documentation

## Table of Contents
- [Core Modules](#core-modules)
  - [hc3emu2.emu](#hc3emu2emu)
  - [hc3emu2.fibaro](#hc3emu2fibaro)
- [Configuration](#configuration)
  - [Environment Variables](#environment-variables)
  - [Configuration File](#configuration-file-hc3emulua)
- [Error Handling](#error-handling)
  - [Common Errors](#common-errors)
  - [Error Recovery](#error-recovery)
- [Examples](#examples)
  - [Basic Device Control](#basic-device-control)
  - [Scene Management](#scene-management)
  - [Timer Usage](#timer-usage)

## Core Modules

### hc3emu2.emu
The core emulator module that provides the main functionality for emulating a Fibaro Home Center 3.

#### Key Functions
- `start(config)`: Starts the emulator with the given configuration
- `loadState(tag)`: Loads a saved state
- `saveState(tag)`: Saves the current state

### hc3emu2.fibaro
The Fibaro API emulation module that provides the standard Fibaro API functions.

#### Device Management
- `fibaro.get(deviceId, property)`: Get a device or its property
- `fibaro.call(deviceId, action, ...)`: Call a device action
- `fibaro.setGlobalVariable(name, value)`: Set a global variable

#### Scene Control
- `fibaro.scene(action, ids)`: Execute or kill scenes
- `fibaro.getSceneVariable(name)`: Get a scene variable
- `fibaro.setSceneVariable(name, value)`: Set a scene variable

#### Timer Functions
- `fibaro.setTimeout(fun, delay)`: Set a timeout
- `fibaro.setInterval(fun, delay)`: Set an interval
- `fibaro.clearTimeout(ref)`: Clear a timeout
- `fibaro.clearInterval(ref)`: Clear an interval

#### Logging
- `fibaro.debug(tag, ...)`: Log debug message
- `fibaro.warning(tag, ...)`: Log warning message
- `fibaro.error(tag, ...)`: Log error message

## Configuration

### Environment Variables
- `HC3URL`: URL of the Home Center 3
- `HC3USER`: Username for HC3
- `HC3PASSWORD`: Password for HC3
- `HC3PIN`: PIN for HC3
- `HC3EMUROOT`: Root directory for development

### Configuration File (.hc3emu.lua)
```lua
return {
  url = "http://hc3.local",
  user = "admin",
  password = "admin",
  pin = "1234"
}
```

## Error Handling

### Common Errors
- `"HC3 is not reachable"`: Connection to HC3 failed
- `"Invalid model specified"`: Invalid model name
- `"Wrong parameter type"`: Invalid parameter type

### Error Recovery
- Automatic fallback to offline mode if HC3 is unreachable
- Retry mechanism for API calls
- State preservation on errors

## Examples

### Basic Device Control
```lua
-- Get device
local device = fibaro.get(123)
print(device.name)

-- Turn on device
fibaro.call(123, "turnOn")

-- Set property
fibaro.setGlobalVariable("myVar", "value")
```

### Scene Management
```lua
-- Execute scene
fibaro.scene("execute", {123, 456})

-- Get scene variable
local value = fibaro.getSceneVariable("myVar")
```

### Timer Usage
```lua
-- Set timeout
local ref = fibaro.setTimeout(function()
  print("Timeout!")
end, 5000)

-- Set interval
local ref = fibaro.setInterval(function()
  print("Interval!")
end, 1000)
``` 