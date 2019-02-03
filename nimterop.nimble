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

proc execTest(test: string) =
  execCmd "nim c -r " & test
  execCmd "nim cpp -r " & test

proc tsoloud() =
  execTest "tests/tsoloud.nim"

proc buildToast() =
  execCmd(&"nim c -d:release nimterop/toast.nim")

task rebuildToast, "rebuild toast":
  # If need to manually rebuild (automatically built on 1st need)
  buildToast()

proc testAll() =
  execTest "tests/tnimterop_c.nim"
  execCmd "nim cpp -r tests/tnimterop_cpp.nim"

  ## platform specific tests
  when defined(Windows):
    execTest "tests/tmath.nim"
  if defined(OSX) or defined(Windows) or not existsEnv("TRAVIS"):
    tsoloud() # requires some libraries on linux, need them installed in TRAVIS

const htmldocsDir = "build/htmldocs"

when (NimMajor, NimMinor, NimPatch) >= (0, 19, 9):
  import os
  proc getNimRootDir(): string =
    #[
    hack, but works
    alternatively (but more complex), use (from a nim file, not nims otherwise
    you get Error: ambiguous call; both system.fileExists):
    import "$nim/testament/lib/stdtest/specialpaths.nim"
    nimRootDir
    ]#
    fmt"{currentSourcePath}".parentDir.parentDir.parentDir

proc runNimDoc() =
  execCmd &"nim doc -o:{htmldocsDir} --project --index:on nimterop/modules.nim"
  execCmd &"nim buildIndex -o:{htmldocsDir}/theindex.html {htmldocsDir}"
  when declared(getNimRootDir):
    execCmd &"nim js -o:{htmldocsDir}/dochack.js {getNimRootDir()}/tools/dochack/dochack.nim"

task test, "Test":
  buildToast()
  testAll()
  runNimDoc()

task docs, "Generate docs":
  runNimDoc()

task docsPublish, "Generate and publish docs":
  # Uses: pip install ghp-import
  runNimDoc()
  execCmd &"ghp-import --no-jekyll -fp {htmldocsDir}"
