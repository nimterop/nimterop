# Package

version = "0.5.2"
author      = "genotrance"
description = "C/C++ interop for Nim"
license     = "MIT"

bin = @["nimterop/toast"]
installDirs = @["nimterop"]

# Dependencies
requires "nim >= 0.20.2", "regex >= 0.14.1", "cligen >= 0.9.45"

import nimterop/docs
import os

proc execCmd(cmd: string) =
  exec "tests/timeit " & cmd

proc execTest(test: string, flags = "", runDocs = true) =
  execCmd "nim c --hints:off -f -d:checkAbi " & flags & " -r " & test
  let
    # -d:checkAbi broken in cpp mode until post 1.2.0
    cppAbi = when (NimMajor, NimMinor) >= (1, 3): "-d:checkAbi " else: ""
  execCmd "nim cpp --hints:off " & cppAbi & flags & " -r " & test

  if runDocs:
    let docPath = "build/html_" & test.extractFileName.changeFileExt("") & "_docs"
    rmDir docPath
    mkDir docPath
    buildDocs(@[test], docPath, nimArgs = "--hints:off " & flags)

task buildToast, "build toast":
  execCmd("nim c --hints:off nimterop/toast.nim")

task buildTimeit, "build timer":
  exec "nim c --hints:off -d:danger tests/timeit"

task bt, "build toast":
  execCmd("nim c --hints:off -d:danger nimterop/toast.nim")

task btd, "build toast":
  execCmd("nim c -g nimterop/toast.nim")

task docs, "Generate docs":
  buildDocs(@["nimterop/all.nim"], "build/htmldocs")

task test, "Test":
  rmFile("tests/timeit.txt")

  buildTimeitTask()
  buildToastTask()

  execTest "tests/tast2.nim"
  execTest "tests/tast2.nim", "-d:NOHEADER"

  execTest "tests/tnimterop_c.nim"
  execTest "tests/tnimterop_c.nim", "-d:FLAGS=\"-f:ast2\""
  execTest "tests/tnimterop_c.nim", "-d:FLAGS=\"-f:ast2 -H\""

  execCmd "nim cpp --hints:off -f -r tests/tnimterop_cpp.nim"
  execCmd "./nimterop/toast -pnk -E=_ tests/include/toast.h"
  execCmd "./nimterop/toast -pnk -E=_ -f:ast2 tests/include/toast.h"

  execTest "tests/tpcre.nim"
  execTest "tests/tpcre.nim", "-d:FLAGS=\"-f:ast2\""

  when defined(Linux):
    execTest "tests/rsa.nim"
    execTest "tests/rsa.nim", "-d:FLAGS=\"-H\""

  # Platform specific tests
  when defined(Windows):
    execTest "tests/tmath.nim"
    execTest "tests/tmath.nim", "-d:FLAGS=\"-f:ast2\""
    execTest "tests/tmath.nim",  "-d:FLAGS=\"-f:ast2 -H\""
  if defined(OSX) or defined(Windows) or not existsEnv("TRAVIS"):
    execTest "tests/tsoloud.nim"
    execTest "tests/tsoloud.nim", "-d:FLAGS=\"-f:ast2\""
    execTest "tests/tsoloud.nim",  "-d:FLAGS=\"-f:ast2 -H\""

  # getHeader tests
  withDir("tests"):
    exec "nim e getheader.nims"
    if not existsEnv("APPVEYOR"):
      exec "nim e wrappers.nims"

  docsTask()

  echo readFile("tests/timeit.txt")
