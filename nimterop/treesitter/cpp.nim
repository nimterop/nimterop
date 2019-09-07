import strutils, os

import ".."/[setup, paths]

static:
  treesitterCppSetup()

const srcDir = incDir() / "treesitter_cpp" / "src"

{.passC: "-I$1" % srcDir.}

import "."/api

when (NimMajor, NimMinor, NimPatch) < (0, 19, 9):
  const srcDirRel = "../../build/inc/treesitter_cpp/src"
else:
  const srcDirRel = srcDir.relativePath(currentSourcePath.parentDir)

# pending https://github.com/nim-lang/Nim/issues/9370 we need srcDirRel instead
# of srcDir
{.compile: (srcDirRel / "parser.c", "nimtero_cpp_parser.c.o").}
{.compile: srcDir / "scanner.cc".}

proc treeSitterCpp*(): ptr TSLanguage {.importc: "tree_sitter_cpp", header: srcDir / "api.h".}
