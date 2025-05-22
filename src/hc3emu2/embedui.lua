-- Extra UI declarations added first in QAs

local embedUIs = {
  ["com.fibaro.binarySwitch"] = {
    {{label='__binarysensorValue',text='0'}},
    {{button='__turnOn',text='Turn On',onReleased='turnOn'},{button='__turnOff',text='Turn Off',onReleased='turnOff'}}
  },
  ["com.fibaro.multilevelSwitch"] = {
    {{label='__multiswitchValue',text='0'}},
    {{button='__turnOn',text='Turn On',onReleased='turnOn'},{button='__turnOff',text='Turn Off',onReleased='turnOff'}},
    {{slider='__setValue',text='Set Value',onChanged='setValue'}}
  },
  ["com.fibaro.colorController"] = {
    {{label='__colorComponentValue',text='white'}},
    {{button='__turnOn',text='Turn On',onReleased='turnOn'},{button='__turnOff',text='Turn Off',onReleased='turnOff'}},
    {{slider='__setValue',text='',onChanged='setValue'}},
    {{slider='__setColorComponentR',text='Red:',max='255',onChanged='setValue'}},
    {{slider='__setColorComponentG',text='Green:',max='255',onChanged='setValue'}},
    {{slider='__setColorComponentB',text='Blue:',max='255',onChanged='setValue'}},
    {{slider='__setColorComponentW',text='WW:',max='255',onChanged='setValue'}}

  },
  ["com.fibaro.multilevelSensor"] = {
    {{label='__multisensorValue',text='0'}},
  },
  ["com.fibaro.binarySensor"] = {
    {{label='__binarysensorValue',text='0'}},
  },
  ["com.fibaro.doorSensor"] = {
    {{label='__doorSensor',text='0'}},
  },
  ["com.fibaro.windowSensor"] = {
    {{label='__windowSensor',text='0'}},
  },
  ["com.fibaro.temperatureSensor"] = {
    {{label='__temperatureSensor',text='0'}},
  },
  ["com.fibaro.humiditySensor"] = {
    {{label='__humiditySensor',text='0'}},
  },
}

local fmt = string.format
local function title(f,...) return fmt("<center><font size='5' color='blue'>%s</font></center>",fmt(f,...)) end
local function dflt(val,def) if val == nil then return def else return val end end

-- Special formatter. Maps an UI element to a property that should be updated when the property changes.
local embedProps  = {
  __binarysensorValue = function(dev)
    local function format(value) return title(value and "On" or "Off") end
    dev.watches['value'] = function(value) 
      dev:updateView('__binarysensorValue','text',format(value))
    end
    return format(dflt(dev.device.properties.value, 0))
  end,
  __multiswitchValue = function(dev)
    local format = function(value) return title("%.2f%%",tonumber(value) or 0) end
    dev.watches['value'] = function(value) 
      dev:updateView('__setValue','value',tostring(value)) 
      dev:updateView('__multiswitchValue','text',format(value))
    end
    return format(dflt(dev.device.properties.value, 0))
  end,
  __setValue = function(dev)
    return tostring(dflt(dev.device.properties.value, 0))
  end,
  __multisensorValue = function(dev)
    local format = function(value) return title("%.2f %s",tonumber(value) or 0,dev.device.properties.unit or "") end
    dev.watches['value'] = function(value) 
      dev:updateView('__multisensorValue','text',format(value))
    end
    return format(dflt(dev.device.properties.value, 0))
  end,
  __colorComponentValue = function(dev)
    local format = function(value)
      -- local r, g, b = value.red or 0, value.green or 0, value.blue or 0
      -- local w = value.warmWhite or 0
      
      -- -- Simple white blending algorithm (approximate how white light affects perception)
      -- if w > 0 then
      --   local wFactor = w / 255
      --   r = math.min(255, r + (w * 0.9))
      --   g = math.min(255, g + (w * 0.85))
      --   b = math.min(255, b + (w * 0.8))
      -- end

      local col = fmt('style="background-color:rgb(%s, %s, %s); font-size: 16px; color: black"',value.red,value.green,value.blue)  -- corrected 'font-color' to 'color'
      local str = fmt('R:%s,G:%s,B:%s,W:%s',value.red or "",value.green or "",value.blue or "",value.warmWhite or "")
      return title(fmt('<div %s>%s</div>',col,str)) end
    dev.watches['colorComponents'] = function(value) 
      dev:updateView('__colorComponentValue','text',format(value))
      dev:updateView('__setColorComponentR','value',tostring(value.red))
      dev:updateView('__setColorComponentG','value',tostring(value.green))
      dev:updateView('__setColorComponentB','value',tostring(value.blue))
      dev:updateView('__setColorComponentW','value',tostring(value.warmWhite))
    end
    dev.watches['value'] = function(value) 
      dev:updateView('__setValue','value',tostring(value))
    end
    return format(dflt(dev.device.properties.colorComponents, {red=0,green=0,blue=0}))
  end,
  __doorSensor = function(dev)
    local function format(value) return title(value and "Open" or "Closed") end
    dev.watches['value'] = function(value) 
      dev:updateView('__doorSensor','text',format(value))
    end
    return format(dflt(dev.device.properties.value,false))
  end,
  __windowSensor = function(dev)
    local function format(value) return title(value and "Open" or "Closed") end
    dev.watches['value'] = function(value) 
      dev:updateView('__windowSensor','text',format(value))
    end
    return format(dflt(dev.device.properties.value,false))
  end,
  __temperatureSensor = function(dev)
    local function format(value) return title("%.2f°",tonumber(value) or 0) end
    dev.watches['value'] = function(value) 
      dev:updateView('__temperatureSensor','text',format(value))
    end
    return format(dflt(dev.device.properties.value, 0))
  end,
  __humiditySensor = function(dev)
    local function format(value) return title("%.2f%%",tonumber(value) or 0) end
    dev.watches['value'] = function(value) 
      dev:updateView('__humiditySensor','text',format(value)) 
    end
    return format(dflt(dev.device.properties.value, 0))
  end,
}

-- Special hack for translating slider event from one color into a combined setColorComponents for all colors...
local function setColorComponents(dev,color,params)
  local cc = table.copy(dev.device.properties.colorComponents)
  cc[color] = params.value
  params.id = '__setColorComponents'
  params.value = cc
end

local embedHooks = { -- Split combined UI event into separate events
  __setColorComponentR = function(dev,params) setColorComponents(dev,'red', params) end,
  __setColorComponentG = function(dev,params) setColorComponents(dev,'green', params) end,
  __setColorComponentB = function(dev,params) setColorComponents(dev,'blue', params) end,
  __setColorComponentW = function(dev,params) setColorComponents(dev,'warmWhite', params) end,
}

return {
  embedUIs = embedUIs,
  embedProps = embedProps,
  embedHooks = embedHooks,
}


