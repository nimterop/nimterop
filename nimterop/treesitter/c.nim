import strutils, os

import ".."/[setup, paths]

static:
  treesitterCSetup()

const srcDir = cacheDir / "treesitter_c" / "src"

import "."/api

{.passC: "-I\"$1\"" % srcDir.}

{.compile: srcDir / "parser.c".}

proc treeSitterC*(): ptr TSLanguage {.importc: "tree_sitter_c".}
