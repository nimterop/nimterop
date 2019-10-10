import strutils, os

import ".."/[build, setup, paths]

static:
  treesitterCppSetup()

const srcDir = cacheDir / "treesitter_cpp" / "src"

{.passC: "-I$1" % srcDir.}

import "."/api

static:
  cpFile(srcDir / "parser.c", srcDir / "parser_cpp.c")

{.compile: srcDir / "parser_cpp.c".}
{.compile: srcDir / "scanner.cc".}

proc treeSitterCpp*(): ptr TSLanguage {.importc: "tree_sitter_cpp", header: srcDir / "api.h".}
