# Architecture Overview

## Table of Contents
- [System Components](#system-components)
- [Core Components](#core-components)
  - [Emulator Engine](#emulator-engine-emulua)
  - [Fibaro API](#fibaro-api-fibarolua)
  - [QuickApp Runtime](#quickapp-runtime)
- [Data Flow](#data-flow)
- [Key Features](#key-features)
  - [Device Emulation](#device-emulation)
  - [API Proxying](#api-proxying)
  - [State Management](#state-management)
  - [Debugging](#debugging)
- [Integration Points](#integration-points)
  - [VSCode Integration](#vscode-integration)
  - [Command Line Interface](#command-line-interface)
- [Security Considerations](#security-considerations)
  - [Sandboxing](#sandboxing)
  - [Authentication](#authentication)
- [Performance](#performance)
  - [Caching](#caching)
  - [Resource Management](#resource-management)
- [Extension Points](#extension-points)
  - [Custom Device Types](#custom-device-types)
  - [API Extensions](#api-extensions)

## System Components

```
hc3emu2/
├── src/hc3emu2/           # Core emulator code
│   ├── emu.lua           # Main emulator engine
│   ├── fibaro.lua        # Fibaro API emulation
│   └── lib/              # Supporting libraries
├── emu/                  # Emulator resources
│   └── rsrcs/           # Device templates and resources
├── examples/             # Example QuickApps
└── test/                # Test files
```

## Core Components

### Emulator Engine (`emu.lua`)
The central component that:
- Manages the emulation environment
- Handles device lifecycle
- Coordinates between QuickApps and the Fibaro API
- Manages state persistence
- Provides debugging capabilities

### Fibaro API (`fibaro.lua`)
Emulates the Fibaro Home Center 3 API by:
- Providing the standard `fibaro` global object
- Implementing device management functions
- Handling scene and global variable operations
- Managing timers and intervals
- Providing logging functionality

### QuickApp Runtime
- Executes QuickApp code in a sandboxed environment
- Handles QuickApp lifecycle events
- Manages QuickApp state and persistence
- Provides access to the Fibaro API

## Data Flow

```
[QuickApp Code] → [QuickApp Runtime] → [Fibaro API] → [Emulator Engine]
       ↑                ↓                    ↑              ↓
       └────────────────┴────────────────────┘              │
                                                           ↓
                                                    [State Storage]
```

1. QuickApp code is loaded and executed by the runtime
2. API calls are intercepted and processed by the Fibaro API layer
3. The emulator engine manages the overall state and device interactions
4. State changes are persisted to storage

## Key Features

### Device Emulation
- Supports various device types (binary switches, sensors, etc.)
- Emulates device properties and actions
- Handles device state changes
- Provides device templates

### API Proxying
- Can proxy requests to a real HC3
- Caches responses for offline use
- Handles authentication and session management
- Manages API rate limiting

### State Management
- Persists device and QuickApp state
- Supports state snapshots
- Handles state restoration
- Manages global variables

### Debugging
- Provides detailed logging
- Supports breakpoints and step-through debugging
- Shows device and QuickApp state
- Tracks API calls and responses

## Integration Points

### VSCode Integration
- Debugging support via "Hc3Emu Helper" extension
- Launch configurations for running QuickApps
- Code completion and documentation
- State inspection

### Command Line Interface
- Direct execution of QuickApp files
- State management commands
- Configuration management
- Debug output control

## Security Considerations

### Sandboxing
- QuickApp code runs in a restricted environment
- API access is controlled and monitored
- Resource usage is limited
- State changes are validated

### Authentication
- Supports HC3 authentication
- Manages API keys and tokens
- Handles session management
- Protects sensitive data

## Performance

### Caching
- Device templates are cached
- API responses are cached
- State is persisted efficiently
- QuickApp code is optimized

### Resource Management
- Memory usage is monitored
- CPU usage is controlled
- Network requests are optimized
- State storage is efficient

## Extension Points

### Custom Device Types
- New device types can be added
- Custom properties and actions supported
- Device templates can be extended
- State handling can be customized

### API Extensions
- Additional API functions can be added
- Custom event handlers supported
- New logging capabilities
- Extended debugging features 