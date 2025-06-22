package = "hc3emu2"
version = "2.0.31-1" -- updated version to match the new version number
source = {
   url = "git://github.com/jangabrielsson/hc3emu2",
   tag = "v2.0.31", -- updated tag to match version
}
description = {
   summary = "hc3emu is an emulator for developing Fibaro HC3 QuickApps offline.",
   detailed = [[
      hc3emu is an emulator for developing Fibaro HC3 QuickApps offline.
      It's based on copas for asynchronous network calls.
      It can automatically deploy a "QA proxy" on the HC3 funneling 
      onAction and uiEvents back to the QA running in the emulator, thus
      allowing the QA's UI to be tested.
   ]],
   homepage = "https://github.com/jangabrielsson/hc3emu2",
   license = "MIT/X11" 
}
dependencies = {
   "lua >= 5.3, <= 5.4",
   "copas >= 4.7.1-1",
   "luamqttt >= 1.0.2-1",
   "lua-json >= 1.0.0-1",
   "bit32 >= 5.3.5.1-1",
   "lua-websockets-bit32 >= 2.0.1-7",
   "timerwheel >= 1.0.2-1",
   "luafilesystem >= 1.8.0-1",
   "luasystem >=  0.6.2-1",
   "argparse >= 0.7.1-1",
   "dumbluaparser >= 2.3.0-1",
   "datafile >= 0.10-1",
   "luautf8 >= 0.1.6-1",
   "mobdebug >= 0.80-1",
}

build = {
   type = "builtin",
   modules = {
      hc3emu2 = "src/hc3emu2.lua", -- Proxy to load package or developer file
      ["hc3emu2.emu"] = "src/hc3emu2/emu.lua",
      ["hc3emu2.device"] = "src/hc3emu2/device.lua",
      ["hc3emu2.fibaro"] = "src/hc3emu2/fibaro.lua",
      ["hc3emu2.quickapp"] = "src/hc3emu2/quickapp.lua",
      ["hc3emu2.class"] = "src/hc3emu2/class.lua",
      ["hc3emu2.timers"] = "src/hc3emu2/timers.lua",
      ["hc3emu2.type"] = "src/hc3emu2/type.lua",
      ["hc3emu2.config"] = "src/hc3emu2/config.lua",
      ["hc3emu2.net"] = "src/hc3emu2/net.lua",
      ["hc3emu2.ui"] = "src/hc3emu2/ui.lua",
      ["hc3emu2.utilities"] = "src/hc3emu2/utilities.lua",
      ["hc3emu2.log"] = "src/hc3emu2/log.lua",
      ["hc3emu2.proxy"] = "src/hc3emu2/proxy.lua",
      ["hc3emu2.offline"] = "src/hc3emu2/offline.lua",
      ["hc3emu2.offline_data"] = "src/hc3emu2/offline_data.lua",
      ["hc3emu2.tools"] = "src/hc3emu2/tools.lua",
      ["hc3emu2.embedui"] = "src/hc3emu2/embedui.lua",
      --["hc3emu2.scene"] = "src/hc3emu2/scene.lua",
      --["hc3emu2.sceneengine"] = "src/hc3emu2/sceneengine.lua",
      ["hc3emu2.refreshstate"] = "src/hc3emu2/refreshstate.lua",
      ["hc3emu2.api"] = "src/hc3emu2/api.lua",
      ["hc3emu2.helper"] = "src/hc3emu2/helper.lua",
      ["hc3emu2.webserver"] = "src/hc3emu2/webserver.lua",
      ["hc3emu2.webui"] = "src/hc3emu2/webui.lua",
      ["hc3emu2.simdevices"] = "src/hc3emu2/simdevices.lua",
      ["hc3emu2.unittest"] = "src/hc3emu2/unittest.lua",

      ["hc3emu2.lib.sourcetrigger"] = "src/hc3emu2/lib/sourcetrigger.lua",
      ["hc3emu2.lib.qwikchild"] = "src/hc3emu2/lib/qwikchild.lua",
      ["hc3emu2.lib.eventlib"] = "src/hc3emu2/lib/eventlib.lua",
      ["hc3emu2.lib.eventmgr"] = "src/hc3emu2/lib/eventmgr.lua",
      ["hc3emu2.lib.sha2"] = "src/hc3emu2/lib/sha2.lua",
      ["hc3emu2.lib.aeslua53"] = "src/hc3emu2/lib/aeslua53.lua",
      ["hc3emu2.lib.markdown"] = "src/hc3emu2/lib/markdown.lua",

      ["hc3emu2.plugin.image"] = "src/hc3emu2/plugin/image.lua",
      ["hc3emu2.plugin.terminal"] = "src/hc3emu2/plugin/terminal.lua",
      ["hc3emu2.plugin.taskrunner"] = "src/hc3emu2/plugin/taskrunner.lua"
  },
  copy_directories = { "doc", "src/rsrcs" }
}
