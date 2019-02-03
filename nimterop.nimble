# Package

version     = "0.1.1"
author      = "genotrance"
description = "C/C++ interop for Nim"
license     = "MIT"

# this gives Warning: Binary 'nimterop/toast' was already installed from source directory
# when running `nimble install --verbose -y`
bin = @["nimterop/toast"]
installDirs = @["nimterop"]
installFiles = @["config.nims"]

# Dependencies
requires "nim >= 0.19.4", "regex >= 0.10.0", "cligen >= 0.9.17"

import strformat

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc tsoloud() =
  execCmd "nim c -r tests/tsoloud.nim"
  execCmd "nim cpp -r tests/tsoloud.nim"

proc buildToast(options: string) =
  execCmd(&"nim c {options} nimterop/toast.nim")

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
  if defined(OSX) or defined(Windows) or not existsEnv("TRAVIS"):
    tsoloud() # requires some libraries on linux, need them installed in TRAVIS

const htmldocsDir = "build/htmldocs"

proc runNimDoc() =
  execCmd &"nim doc -o:{htmldocsDir} --project --index:on nimterop/api.nim"

task test, "Test":
  for options in ["", "-d:release"]:
    buildToast(options)
    testAll()
  runNimDoc()

task nimDoc, "run nim doc":
  runNimDoc()

task docs, "Generate docs":
  # Uses: pip install ghp-import
  runNimDoc()
  execCmd &"ghp-import --no-jekyll -fp {htmldocsDir}"
