# Package

version     = "0.1.0"
author      = "genotrance"
description = "C/C++ interop for Nim"
license     = "MIT"

installDirs = @["nimterop"]

# Dependencies

requires "nim >= 0.19.2", "regex >= 0.10.0", "cligen >= 0.9.17"

proc execCmd(cmd: string) =
  echo "execCmd:" & cmd
  exec cmd

proc tsoloud() =
  execCmd "nim c -r tests/tsoloud.nim"
  execCmd "nim cpp -r tests/tsoloud.nim"

task test, "Test":
  execCmd "nim c -r tests/tnimterop_c.nim"
  execCmd "nim cpp -r tests/tnimterop_c.nim"
  execCmd "nim cpp -r tests/tnimterop_cpp.nim"
  when defined(windows):
    execCmd "nim c -r tests/tmath.nim"
    execCmd "nim cpp -r tests/tmath.nim"
  when not defined(OSX):
    when defined(Windows):
      tsoloud()
    else:
      if not existsEnv("TRAVIS"):
        tsoloud()

task docs, "Generate docs":
  # Uses: pip install ghp-import
  execCmd "nim doc --project --index:on nimterop/cimport"
  execCmd "nim doc --project --index:on nimterop/git"
  execCmd "ghp-import --no-jekyll -fp nimterop/htmldocs"
