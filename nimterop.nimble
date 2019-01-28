# Package

version     = "0.1.0"
author      = "genotrance"
description = "C/C++ interop for Nim"
license     = "MIT"

installDirs = @["nimterop"]
installFiles = @["config.nims"]

# Dependencies
requires "nim >= 0.19.2", "regex >= 0.10.0", "cligen >= 0.9.17"

import os
let ExeExt2 = when defined(Windows): "." & ExeExt else: ""

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc tsoloud() =
  execCmd "nim c -r tests/tsoloud.nim"
  execCmd "nim cpp -r tests/tsoloud.nim"

proc buildToast(options: string) =
  # pending https://github.com/nim-lang/Nim/issues/9513
  execCmd("nim c -o:build/toast" & ExeExt2 & " " & options & " nimterop/toast.nim")

task rebuildToast, "rebuild toast":
  # If need to manually rebuild (automatically built on 1st need)
  buildToast("-d:release")

proc testAll() =
  execCmd "nim c -r tests/tnimterop_c.nim"
  execCmd "nim cpp -r tests/tnimterop_c.nim"
  execCmd "nim cpp -r tests/tnimterop_cpp.nim"

  ## platform specific tests
  when defined(Windows):
    execCmd "nim c -r tests/tmath.nim"
    execCmd "nim cpp -r tests/tmath.nim"
    tsoloud()
  elif defined(osx):
    discard
  elif existsEnv("TRAVIS"):
    discard
  else:
    tsoloud()

task test, "Test":
  for options in ["", "-d:release"]:
    buildToast(options)
    testAll()

task docs, "Generate docs":
  # Uses: pip install ghp-import
  execCmd "nim doc --project --index:on nimterop/cimport"
  execCmd "nim doc --project --index:on nimterop/git"
  execCmd "nim doc --project --index:on nimterop/plugin"
  execCmd "ghp-import --no-jekyll -fp nimterop/htmldocs"
