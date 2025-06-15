# Development Guide

## Table of Contents
- [Project Structure](#project-structure)
- [Development Setup](#development-setup)
- [Coding Standards](#coding-standards)
  - [Lua Style Guide](#lua-style-guide)
  - [Documentation](#documentation)
  - [Testing](#testing)
- [Development Workflow](#development-workflow)
- [Building](#building)
  - [Creating a New Release](#creating-a-new-release)
- [Debugging](#debugging)
  - [Logging](#logging)
  - [Debug Mode](#debug-mode)
- [Contributing](#contributing)
  - [Pull Request Guidelines](#pull-request-guidelines)
- [Resources](#resources)

## Project Structure

```
hc3emu2/
├── doc/           # Documentation
├── emu/           # Emulator resources
├── examples/      # Example scripts
├── src/           # Source code
│   └── hc3emu2/   # Main module
├── test/          # Test files
├── tools/         # Development tools
└── rockspecs/     # LuaRocks specifications
```

## Development Setup

1. Clone the repository:
```bash
git clone https://github.com/yourusername/hc3emu2.git
cd hc3emu2
```

2. Install development dependencies:
```bash
luarocks install --only-deps
luarocks install busted    # Testing framework
luarocks install luacheck  # Linter
```

3. Set up your development environment:
```bash
# Create .hc3emu.lua for local development
cp .hc3emu.lua.example .hc3emu.lua
# Edit .hc3emu.lua with your settings
```

## Coding Standards

### Lua Style Guide

- Use 2 spaces for indentation
- Use snake_case for variables and functions
- Use PascalCase for classes
- Add type annotations using LuaLS format
- Document all public functions and classes

Example:
```lua
---@class Device
---@field id number Device ID
---@field name string Device name
local Device = {}

---Creates a new device
---@param id number Device ID
---@param name string Device name
---@return Device
function Device.new(id, name)
    local self = setmetatable({}, { __index = Device })
    self.id = id
    self.name = name
    return self
end
```

### Documentation

- Use LuaDoc-style comments for all public APIs
- Include examples in documentation
- Keep README.md up to date
- Document breaking changes

### Testing

- Write unit tests for all new features
- Maintain test coverage
- Run tests before committing:
```bash
busted
```

## Development Workflow

1. Create a new branch:
```bash
git checkout -b feature/your-feature
```

2. Make your changes

3. Run tests and linting:
```bash
luacheck src/
busted
```

4. Update documentation

5. Create a pull request

## Building

### Creating a New Release

1. Update version in:
   - `rockspecs/hc3emu2-*.rockspec`
   - `src/hc3emu2/emu.lua`
   - `src/hc3emu2/fibaro.lua`

2. Create new rockspec:
```bash
./create_rockspec.sh
```

3. Build package:
```bash
luarocks make
```

4. Test the build:
```bash
luarocks install
```

## Debugging

### Logging

Use the built-in logging functions:
```lua
fibaro.debug("tag", "message")
fibaro.warning("tag", "message")
fibaro.error("tag", "message")
```

### Debug Mode

Enable debug mode in `.hc3emu.lua`:
```lua
return {
    debug = true,
    -- other settings...
}
```

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a pull request

### Pull Request Guidelines

- Update documentation
- Add tests for new features
- Ensure all tests pass
- Follow the coding standards
- Describe your changes clearly

## Resources

- [Lua Documentation](https://www.lua.org/manual/5.3/)
- [LuaRocks Documentation](https://github.com/luarocks/luarocks/wiki)
- [Busted Testing Framework](http://olivinelabs.com/busted/)
- [Luacheck Documentation](https://github.com/mpeterv/luacheck) 