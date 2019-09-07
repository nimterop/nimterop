import strutils, os

import ".."/[setup, paths]

static:
  treesitterCSetup()

const srcDir = incDir() / "treesitter_c" / "src"

import "."/api

{.passC: "-I$1" % srcDir.}

{.compile: srcDir / "parser.c".}

proc treeSitterC*(): ptr TSLanguage {.importc: "tree_sitter_c", header: srcDir / "api.h".}
