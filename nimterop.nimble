# Package

version = "0.3.1"
author      = "genotrance"
description = "C/C++ interop for Nim"
license     = "MIT"

# this gives Warning: Binary 'nimterop/toast' was already installed from source directory
# when running `nimble install --verbose -y`
bin = @["nimterop/toast"]
installDirs = @["nimterop"]
installFiles = @["config.nims"]

# Dependencies
requires "nim >= 0.19.2", "regex >= 0.10.0", "cligen >= 0.9.17"

import nimterop/docs

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc execTest(test: string) =
  execCmd "nim c -f -r " & test
  execCmd "nim cpp -r " & test

task buildToast, "build toast":
  execCmd("nim c -f -d:danger nimterop/toast.nim")

task bt, "build toast":
  execCmd("nim c -d:danger nimterop/toast.nim")

task docs, "Generate docs":
  buildDocs(@["nimterop/all.nim"], "build/htmldocs")

task test, "Test":
  buildToastTask()

  execTest "tests/tnimterop_c.nim"
  execCmd "nim cpp -f -r tests/tnimterop_cpp.nim"
  execTest "tests/tpcre.nim"

  # Platform specific tests
  when defined(Windows):
    execTest "tests/tmath.nim"
  if defined(OSX) or defined(Windows) or not existsEnv("TRAVIS"):
    execTest "tests/tsoloud.nim"

  # getHeader tests
  withDir("tests"):
    execCmd("nim e getheader.nims")

  docsTask()
