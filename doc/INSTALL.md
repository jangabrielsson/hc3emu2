# Installation Guide

## Table of Contents
- [Prerequisites](#prerequisites)
- [Installation](#installation)
  - [For Users](#for-users)
  - [For Developers](#for-developers)
- [Configuration](#configuration)
- [Verification](#verification)
  - [Using VSCode](#using-vscode-recommended)
  - [Using Command Line](#using-command-line)
  - [Using ZeroBrane Studio](#using-zerobrane-studio)
- [Troubleshooting](#troubleshooting)
  - [Common Issues](#common-issues)
  - [Getting Help](#getting-help)
- [Updating](#updating)
- [Uninstallation](#uninstallation)

## Prerequisites

- Lua 5.3 or later
- LuaRocks package manager

## Installation

### For Users

The recommended way to install HC3Emu2 is through LuaRocks:

```bash
# Install from LuaRocks
luarocks install hc3emu2
```

### For Developers

If you're developing the emulator itself, you'll need to install from source:

1. Clone the repository:
```bash
git clone https://github.com/yourusername/hc3emu2.git
cd hc3emu2
```

2. Install dependencies:
```bash
luarocks install --only-deps
```

3. Install the package:
```bash
luarocks make
```

For more information about development, see [DEVELOPMENT.md](DEVELOPMENT.md).

## Configuration

1. Create a `.hc3emu.lua` file in your project root:
```lua
return {
    url = "http://your-hc3-ip",
    user = "your-username",
    password = "your-password",
    pin = "your-pin"
}
```

2. Set environment variables (optional):
```bash
export HC3URL="http://your-hc3-ip"
export HC3USER="your-username"
export HC3PASSWORD="your-password"
export HC3PIN="your-pin"
export HC3EMUROOT="/path/to/your/project"
```

## Verification

To verify the installation, you can run code in three ways:

### Using VSCode (Recommended)

1. Install the "Hc3Emu Helper" extension in VSCode
2. Create a test script `test.lua`:
```lua
--%%name=MyQA
--%%type=com.fibaro.binarySwitch
function QuickApp:onInit()
   self:debug(self.name,self.id)
   setInterval(function() print("Ping!") end,2000)
end
```
3. Press F5 or use the Run menu to execute the script using the "hc3emu2: Current File" configuration

### Using Command Line

Run the test using the hc3emu2 command:
```bash
lua -e "require('hc3emu2')" run test.lua
```

### Using ZeroBrane Studio

1. Install ZeroBrane Studio from [https://studio.zerobrane.com/](https://studio.zerobrane.com/)

2. Configure Lua interpreter:
   - Go to Preferences → Settings: System
   - Set `path.lua54` to your system Lua installation (e.g., `/opt/homebrew/bin/lua`)
   - This ensures ZeroBrane uses the same Lua interpreter as your system

3. Install the HC3Emu plugin:
   - Copy the plugin file to `~/.zbstudio/packages/HC3EMUplugin.lua`
   - Restart ZeroBrane Studio

4. Create a new project:
   - Go to Project → Project Directory → Choose Directory
   - Select your project directory containing the QuickApp files

5. Set up the interpreter:
   - Go to Project → Lua Interpreter → Hc3Emu emulator
   - This will use the HC3Emu2 emulator to run your QuickApps

6. Create a test script `test.lua`:
```lua
--%%name=MyQA
--%%type=com.fibaro.binarySwitch
function QuickApp:onInit()
   self:debug(self.name,self.id)
   setInterval(function() print("Ping!") end,2000)
end
```

7. Run the script:
   - Open the test file
   - Press F5 or use the Run menu to execute
   - The emulator will start and run your QuickApp

Note: The HC3Emu plugin provides API completions for QuickApps and integrates with the emulator for running and debugging your code.

## Troubleshooting

### Common Issues

1. **Module not found**
   - Ensure LuaRocks is properly installed
   - Check if the package is installed: `luarocks list`
   - Verify Lua path: `lua -e "print(package.path)"`

2. **Connection errors**
   - Verify HC3 is reachable
   - Check credentials in `.hc3emu.lua`
   - Ensure network connectivity

3. **Permission issues**
   - Check file permissions
   - Run with appropriate user privileges

### Getting Help

- Check the [API Documentation](API.md)
- Review [Examples](../examples/)
- Open an issue on GitHub
- Check the [ToDo list](../ToDo.txt) for known issues

## Updating

To update an existing installation:

```bash
luarocks update hc3emu2
```

## Uninstallation

To remove the package:

```bash
luarocks remove hc3emu2
``` 