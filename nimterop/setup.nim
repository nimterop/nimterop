import os, strutils

import "."/git

static:
  gitPull("https://github.com/tree-sitter/tree-sitter/", "inc/treesitter", """
include/*
src/runtime/*
""")

  gitPull("https://github.com/JuliaStrings/utf8proc", "inc/utf8proc", """
*.c
*.h
""")

  gitPull("https://github.com/tree-sitter/tree-sitter-c", "inc/treesitter_c", """
src/*.h
src/*.c
src/*.cc
""")

  gitPull("https://github.com/tree-sitter/tree-sitter-cpp", "inc/treesitter_cpp", """
src/*.h
src/*.c
src/*.cc
""")

  let
    stack = "inc/treesitter/src/runtime/stack.c"
    headerc = "inc/treesitter_c/src/parser.h"
    headercpp = "inc/treesitter_cpp/src/parser.h"

  stack.writeFile(stack.readFile().replace("inline Stack", "Stack"))

  headerc.writeFile("""
    typedef struct TSLanguage TSLanguage;
    const TSLanguage *tree_sitter_c();
  """)

  headercpp.writeFile("""
    typedef struct TSLanguage TSLanguage;
    const TSLanguage *tree_sitter_cpp();
  """)