# Package

version     = "0.1.0"
author      = "genotrance"
description = "C/C++ interop for Nim"
license     = "MIT"

bin = @["toast"]
installDirs = @["nimterop"]

# Dependencies

requires "nim >= 0.19.0", "treesitter >= 0.1.0", "treesitter_c >= 0.1.0", "treesitter_cpp >= 0.1.0", "regex >= 0.10.0"

task test, "Test":
  exec "nim c -r tests/tnimterop"

task testext, "Test":
  exec "nim c -r tests/tnimteropext"
