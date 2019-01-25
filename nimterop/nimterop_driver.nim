import "."/nimteropfuns

import os
import strformat

proc main()=
  const dir = currentSourcePath.parentDir
  const plugin = dir / "nimterop_plugin_example.nim"
  const toast = dir / "nimterop_faketoast.nim"
  const outDir = "/tmp/D20190122T232058/"
  const pluginExe = outDir / "pluginExe"

  doAssert execShellCmd(fmt "nim c --app:lib -o:{pluginExe} {plugin}") == 0
  doAssert execShellCmd(fmt "nim c -r {toast} --pluginExe:{pluginExe}") == 0

main()
