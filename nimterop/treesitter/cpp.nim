import strutils, os

import ".."/[setup, paths]
import ".."/build/shell

static:
  treesitterCppSetup()

const srcDir = cacheDir / "treesitter_cpp" / "src"

{.passC: ("-I" & quoteShell(srcDir)) .}

import "."/api

static:
  cpFile(srcDir / "parser.c", srcDir / "parser_cpp.c")

{.compile: srcDir / "parser_cpp.c".}
{.compile: srcDir / "scanner.cc".}

proc treeSitterCpp*(): ptr TSLanguage {.importc: "tree_sitter_cpp".}
