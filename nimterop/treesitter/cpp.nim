import strutils

import "."/runtime

{.compile: ("../../inc/treesitter_cpp/src/parser.c", "parsercpp.o").}
{.compile: ("../../inc/treesitter_cpp/src/scanner.cc", "scannercpp.o").}

const sourcePath = currentSourcePath().split({'\\', '/'})[0..^4].join("/") & "/inc/treesitter_cpp/src/"
proc treeSitterCpp*(): ptr TSLanguage {.importc: "tree_sitter_cpp", header: sourcePath & "parser.h".}
