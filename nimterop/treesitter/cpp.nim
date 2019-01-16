import "."/runtime

{.compile: ("../../inc/treesitter_cpp/src/parser.c", "parsercpp.o").}
{.compile: ("../../inc/treesitter_cpp/src/scanner.cc", "scannercpp.o").}

proc treeSitterCpp*(): ptr TSLanguage {.importc: "tree_sitter_cpp", header: "inc/treesitter_cpp/src/parser.h".}
