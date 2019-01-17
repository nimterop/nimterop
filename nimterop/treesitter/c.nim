import strutils

import ".."/setup

static:
  treesitterCSetup()

import "."/runtime

{.compile: ("../../inc/treesitter_c/src/parser.c", "parserc.o").}

const sourcePath = currentSourcePath().split({'\\', '/'})[0..^4].join("/")
proc treeSitterC*(): ptr TSLanguage {.importc: "tree_sitter_c", header: sourcePath & "/inc/treesitter_c/src/parser.h".}
