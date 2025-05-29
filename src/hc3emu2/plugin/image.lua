Emu = Emu
local fmt = string.format
local lfs = require("lfs")

--@D image=path,name - add image file to QA, ex. --%%image=examples/myImage.png,myImage
function Emu.headerKeys.image(v,h,k) -- Register a new directive
  h.images = h.images or {}
  local path,name = v:match("([^,]+),([^,]+)")
  assert(path and name,"Bad image directive: "..k)
  assert(lfs.attributes(path),"Image not found: "..path)
  h.images[path] = name
end

--@D iconImage=path,name - add image file to QA, ex. --%%iconImage=examples/myImage.png,myImage
function Emu.headerKeys.iconImage(v,h,k) -- Register a new directive
  h.iconImages = h.iconImages or {}
  local path,name = v:match("([^,]+),s%*([^,]+)")
  assert(path and name,"Bad iconImage directive: "..k)
  assert(lfs.attributes(path),"Icon image not found: "..path)
  h.iconImages[path] = name
end

local function base64encode(data)
  local bC = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  return ((data:gsub('.', function(x)
    local r, b = '', x:byte()
    for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
    return r;
  end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
    if (#x < 6) then return '' end
    local c = 0
    for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
    return bC:sub(c + 1, c + 1)
  end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function getSize(b)
  local buf = {}
  for i = 1, 8 do buf[i] = b:byte(16 + i) end
  local width = (buf[1] << 24) + (buf[2] << 16) + (buf[3] << 8) + (buf[4] << 0)
  local height = (buf[5] << 24) + (buf[6] << 16) + (buf[7] << 8) + (buf[8] << 0);
  return width, height
end

local charMap = {
  ['\"']="%22",
  ['!']="%21",
  ['#']="%23",
  ['$']="%24",
  ['%']="%25",
  ['&']="%26",
  ['\'']="%27",
  [',']="%2C",
  -- ['<']="%3C",
  -- ['>']="%3E",
  ['=']="%3D",
  ['?']="%3F",
  ['@']="%40",
  ['\n']=""
}

local function addImages(images,files)
  local imcont = { "_IMAGES=_IMAGES or {};\n" }
  for fname,name in pairs(images) do
    local file = io.open(fname, "rb")
    local typ = fname:match("%.(%w+)$")
    typ = typ and typ:lower() or "png"
    assert(file, "Image not found:" .. name, name)
    local img = file:read("*all")
    local w, h = 0,0
    if typ == 'png' then w,h = getSize(img) end
    local data
    if typ == "svg" then
      data = "data:image/svg+xml;utf8," .. img:gsub(".",charMap)
    else
      data = "data:image/png;base64," .. base64encode(img)
    end
    imcont[#imcont + 1] = string.format([[
          _IMAGES['%s']={data='%s',type='%s',w=%s,h=%s}
          ]], name, data, typ, w or 0, h or 0)
    file:close()
  end
  local content = table.concat(imcont, "\n")
  table.insert(files, 1, {
    name = "IMAGES",
    fname = "<images>",
    content = content,
    type = 'lua',
    isMain = false,
    isOpen = false
  })
end

local function addIconImages(images,files)
  local imcont = { "_ICONS=_ICONS or {};\n" }
  for fname,name in pairs(images) do
    local file = io.open(fname, "rb")
    assert(file, "Image not found:" .. name, name)
    local img = file:read("*all")
    file:close()
    local res = {}
    for i=1,#img do
      res[#res+1]=string.format("%02X",string.byte(img,i))
    end
    local iconData = table.concat(res,"")
    imcont[#imcont + 1] = string.format([[
_ICONS['%s']='%s'
]], name, iconData)
  end
  local content = table.concat(imcont, "\n")
  table.insert(files, 1, {
    name = "ICONS",
    fname = "<icons>",
    content = content,
    type = 'lua',
    isMain = false,
    isOpen = false
  })
end

function Emu.EVENT._device_created(event) -- Add image file to QA when loaded
  local dev = Emu.devices[event.id]
  if not dev then return end
  local images = dev.headers.images
  if images then addImages(images, dev.files) end
  local iconImages = dev.headers.iconImages
  if iconImages then addIconImages(iconImages, dev.files) end
end