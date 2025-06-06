# HC3 QuickApp Emulator
![HC3 Emulator](./hc3emusmall.png)

## Overview

HC3Emu is a Lua-based emulator designed to simulate the Fibaro Home Center 3 QuickApp runtime environment. It allows developers to code and test QuickApps offline before deploying them to a physical HC3 controller.

Forum thread discussing the emulator (and questions) [here](https://forum.fibaro.com/topic/78728-quickapp-emulator-hc3emu/)

## Key Features

- Simulates most of the Fibaro SDK APIs
- Integrates with real HC3 controllers for testing
- Supports UI testing through proxy deployment
- Works with major Lua IDEs (Zerobrane, VSCode)
- Provides comprehensive debugging capabilities
- Supports file operations and state persistence
- Limited support for testing Scenes...

## Installation

```bash
# Install via LuaRocks
luarocks install hc3emu

# Install specific version
luarocks install hc3emu <version>

# Update to latest version
luarocks install hc3emu
```

- For Windows installation see [here](https://forum.fibaro.com/topic/78728-quickapp-emulator-hc3emu/page/2/#findComment-290650)
- For Windows WSL installation see [here](https://forum.fibaro.com/topic/78728-quickapp-emulator-hc3emu/page/2/#findComment-290649)
- For MacOS, it's pretty straight forward to install Lua and Luarocks with brew.
- For Visual Studio Code setup see [here](https://forum.fibaro.com/topic/78728-quickapp-emulator-hc3emu/#findComment-290587)
- For ZeroBrane Studio setup see [here](https://forum.fibaro.com/topic/78728-quickapp-emulator-hc3emu/page/2/#findComment-290595)

## Dependencies

- Lua 5.3 or higher
- Required packages (installed automatically by LuaRocks):
   lua >= 5.3, <= 5.4
   copas >= 4.7.1-1
   luamqttt >= 1.0.2-1
   lua-json >= 1.0.0-1
   bit32 >= 5.3.5.1-1
   lua-websockets-bit32 >= 2.0.1-7
   timerwheel >= 1.0.2-1
   luafilesystem >= 1.8.0-1
   luasystem >=  0.6.2-1
   argparse >= 0.7.1-1
   datafile >= 0.10-1
   mobdebug >= 0.80-1
- System requirement: openssl

## Configuration

### Global Configuration

The emulator can be configured through:
1. Settings in the QA file, using --%%directive=value
2. `hc3emu.lua` in the project directory
3. `.hc3emu.lua` in the user's home directory. Put credentials here so they don't polute project directory.
4. Credentials can also be specified with environment variables or an .env file
Settings in QA files overrides project settings that overrides home directory settings.

### QuickApp Configuration

QuickApps are configured using special directives in comments starting with `--%%`:
User credentials, lije HC3 user,url, and password can not be set here, but must be set in a configuration file or environment variabes/file.

```lua

--%%name=MyQuickApp               # Name of the QuickApp
--%%type=com.fibaro.binarySwitch  # Device type
--%%proxy=MyProxy                 # HC3 proxy name
--%%dark=true                     # Enable dark mode for logs
--%%var=foo:config.secret         # Set QuickApp variable (from config file)
--%%debug=warnings:true          # Configure a debug flag
--%%file=lib.lua:lib              # Include external file
--%%save=MyQA.fqa                 # Save as FQA file when running
```

### Configuration files ~./hc3emu.lua and ./.hc3emu.lua
The file should be a lua file that returns a table.
```lua
return {
  user = "admin",
  password = "Admin",
  url = "http://192.168.1.157/",
  secret = "My secret value"
}
```
The secret field can then be accessed in the QA, like above...

### Environment variables
There are a credentials that can be set with environment variables
HC3USER = \<username>
HC3PASSWORD = \<password>
HC3URL = http://\<ip>
HC3PIN = \<pin>

These can also be specifed in an .env file in the working directory and will be picked up that way. This is because for some platforms it can be difficult to set environemnt variables to be seen by applications MacOS)

## Setup

### VSCode
Add a launch option to .vscode/.launch.json, 
or add the launch option in your vscode User Settings to have the luanch option available in all projects
```json
    {
      "name": "hc3emu2: Current File",
      "type": "luaMobDebug",
      "request": "launch",
      "workingDirectory": "${workspaceFolder}",
      "sourceBasePath": "${workspaceFolder}",
      "listenPort": 8172,
      "stopOnEntry": false,
      "sourceEncoding": "UTF-8",
      "interpreter": "lua",
      "arguments": [
        "-e",
        "require('hc3emu2')",
        "run",
        "${relativeFile}"
      ],
      "env": {
        "HC3URL": "${config:hc3emu.url}",
        "HC3USER": "${config:hc3emu.user}",
        "HC3PASSWORD": "${config:hc3emu.password}"
      },
      "listenPublicly": true
    },
```
In this example, we also set the environment variables using values from our User Settings file. Remove if you provide credentials differently.

### ZeroBrane Studio
Install the zerobrane package file from the repo [here](https://raw.githubusercontent.com/jangabrielsson/hc3emu2/refs/heads/main/tools/HC3EMUplugin.lua) into .~/zbstudio/packages/HC3EMUplugin.lua
The file is a Zerobrane studio package file that provides API completions for QuickApps and an interpreter option in the 
Project -> Interpreter -> Hc3Emu emulator
to run your QuickApp files.

## CLI

It is also possible to run the emulator with a provided QA file using the command line.
Ex.
```bash
>lua -e "require('hc3emu2')" run MyQA.lua
```

### vscode.lua Tool

Located in `/tools/vscode.lua`, this tool provides VSCode tasks integration with commands:

- `downloadQA(id, path)`: Download QuickApp from HC3
- `uploadQA(fname)`: Upload QuickApp to HC3
- `updateFile(fname)`: Update single file in QuickApp

See .vscode/tasks.json for usage

To use the updateFile command the workspace needs a `.project` file.
It's auto generated with the --%%project=<quickapp_id> directive that allows the command/task to push the file to the right QA on the HC3

```json
{
  "files": {
    "main": "main.lua",
    "lib": "lib.lua"
  },
  "id": "<quickapp_id>"
}
```

## API Support

- api.delete(...)
- api.get(...)
- api.post(...)
- api.put(...)
- fibaro.HC3EMU_VERSION
- fibaro.PASSWORD
- fibaro.URL
- fibaro.USER
- fibaro.__houseAlarm(...)
- fibaro.alarm(...)
- fibaro.alert(...)
- fibaro.call(...)
- fibaro.callGroupAction(...)
- fibaro.clearTimeout(...)
- fibaro.debug(...)
- fibaro.emitCustomEvent(...)
- fibaro.error(...)
- fibaro.get(...)
- fibaro.getDevicesID(...)
- fibaro.getGlobalVariable(...)
- fibaro.getHomeArmState(...)
- fibaro.getIds(...)
- fibaro.getName(...)
- fibaro.getPartition(...)
- fibaro.getPartitionArmState(...)
- fibaro.getPartitions(...)
- fibaro.getRoomID(...)
- fibaro.getRoomName(...)
- fibaro.getRoomNameByDeviceID(...)
- fibaro.getSectionID(...)
- fibaro.getType(...)
- fibaro.getValue(...)
- fibaro.hc3emu
- fibaro.isHomeBreached(...)
- fibaro.isPartitionBreached(...)
- fibaro.profile(...)
- fibaro.scene(...)
- fibaro.setGlobalVariable(...)
- fibaro.setTimeout(...)
- fibaro.sleep(...)
- fibaro.trace(...)
- fibaro.useAsyncHandler(...)
- fibaro.wakeUpDeadDevice(...)
- fibaro.warning(...)
- net.HTTPClient(...)
- net.TCPSocket(...)
- net.UDPSocket(...)
- plugin._dev
- plugin._quickApp
- plugin.createChildDevice(...)
- plugin.deleteDevice(...)
- plugin.getChildDevices(...)
- plugin.getDevice(...)
- plugin.getProperty(...)
- plugin.mainDeviceId
- plugin.restart(...)
- json.encode(expr)
- json.decode(str)
- setTimeout(fun,ms)
- clearTimeout(ref)
- setInterval(fun,ms)
- clearInterval(ref)
- class <name>(<parent>)
- property(...)
- class QuickAppBase()
- class QuickApp()
- class QuickAppChild
- hub = fibaro

### Core APIs
- `api.*` - HTTP API operations
- `fibaro.*` - Core Fibaro functions
- `net.*` - Network operations
- `plugin.*` - Plugin management
- `json.*` - JSON handling

### Common Operations
```lua
-- HTTP Operations
api.get("/devices")
api.post("/quickApp/", fqa)

-- Device Operations
fibaro.call(deviceId, "turnOn")
fibaro.getValue(deviceId, "value")

-- Timer Operations
setTimeout(callback, milliseconds)
setInterval(callback, milliseconds)

-- Storage Operations
self:setVariable("name", value)
self:getVariable("name")
```
etc etc.

## Debugging

The emulator provides various debug flags that can be enabled:

```lua
--%%debug=info:true       # Log general info
--%%debug=api:true        # Log api.* calls
--%%debug=timer:true      # Log start/stop of timers (setTimeout)
--%%debug=http:true       # Log HTTP requests
--%%debug=onAction:true   # Log Action callbacks
--%%debug=onUIEvent:true  # Log UI events
```

## Best Practices


2. Use state persistence for development:
```lua
--%%state=myqa.state
```
Running in offline mode this file will be used for storing device and resource states between runs.
For QAs that use the QA internalStorage api, it's recommended to turn this on.

3. Organize code in multiple files:
```lua
--%%file=utils.lua:utils
--%%file=api.lua:api
```
First is the path to the lua file, second is the name the file will have in the QA.

4. Test UI interactions using proxy mode:
```lua
--%%proxy=MyTestProxy
```

## Common Issues

1. **Missing Credentials**: Ensure URL, USER, and PASSWORD are configured when not in offline mode. If the emulator fails calling the HC3 (unathorized), it will block further requests. This to prevent that the HC3 blocks to emulator IP due to too many failed login requests... Fix credentials, and restart the emulator.
2. **File Permissions**: Check write permissions for state and save files
3. **Proxy Conflicts**: Use unique proxy names or remove existing proxies

## Contributing

See the [Contributing Guide](docs/CONTRIBUTING.md) for details on:
- Setting up development environment
- Coding standards
- Pull request process

## License

Released under MIT License. See [LICENSE](LICENSE) for details.
