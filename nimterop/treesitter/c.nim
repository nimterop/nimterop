import "."/runtime

{.compile: ("../../inc/treesitter_c/src/parser.c", "parserc.o").}

proc treeSitterC*(): ptr TSLanguage {.importc: "tree_sitter_c", header: "inc/treesitter_c/src/parser.h".}
