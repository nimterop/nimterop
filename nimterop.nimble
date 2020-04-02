# Package

version = "0.4.4"
author      = "genotrance"
description = "C/C++ interop for Nim"
license     = "MIT"

bin = @["nimterop/toast"]
installDirs = @["nimterop"]
installFiles = @["config.nims"]

# Dependencies
requires "nim >= 0.20.2", "regex >= 0.13.1", "cligen >= 0.9.43"

import nimterop/docs

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc execTest(test: string, flags = "") =
  execCmd "nim c -f " & flags & " -r " & test
  execCmd "nim cpp " & flags & " -r " & test

task buildToast, "build toast":
  execCmd("nim c -f nimterop/toast.nim")

task bt, "build toast":
  execCmd("nim c -d:danger nimterop/toast.nim")

task docs, "Generate docs":
  buildDocs(@["nimterop/all.nim"], "build/htmldocs")

task test, "Test":
  buildToastTask()

  execTest "tests/tast2.nim"
  execTest "tests/tast2.nim", "-d:HEADER"

  execTest "tests/tnimterop_c.nim"
  execTest "tests/tnimterop_c.nim", "-d:AST2"
  execTest "tests/tnimterop_c.nim", "-d:HEADER -d:AST2"

  execCmd "nim cpp -f -r tests/tnimterop_cpp.nim"
  execCmd "./nimterop/toast -pnk -E=_ tests/include/toast.h"
  execCmd "./nimterop/toast -pnk -E=_ -f:ast2 tests/include/toast.h"
  execTest "tests/tpcre.nim"

  # Platform specific tests
  when defined(Windows):
    execTest "tests/tmath.nim"
  if defined(OSX) or defined(Windows) or not existsEnv("TRAVIS"):
    execTest "tests/tsoloud.nim"

  # getHeader tests
  withDir("tests"):
    execCmd("nim e getheader.nims")
    if not existsEnv("APPVEYOR"):
      execCmd("nim e wrappers.nims")

  docsTask()
