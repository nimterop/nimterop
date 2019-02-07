import strutils, os

import ".."/[setup, paths]

static:
  treesitterCSetup()

import "."/api

{.compile: incDir() / "treesitter_c/src/parser.c".}

proc treeSitterC*(): ptr TSLanguage {.importc: "tree_sitter_c", header: incDir() / "treesitter_c/src/parser.h".}
