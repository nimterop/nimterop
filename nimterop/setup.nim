import os, strutils

import "."/[git,paths]

proc treesitterSetup*() =
  gitPull("https://github.com/tree-sitter/tree-sitter/", incDir() / "treesitter", """
include/*
src/runtime/*
""")

  gitPull("https://github.com/JuliaStrings/utf8proc", incDir() / "utf8proc", """
*.c
*.h
""")
  
  # TODO: does this work on windows? if not use `os.unixToNativePath`
  let
    stack = incDir() / "treesitter/src/runtime/stack.c"

  stack.writeFile(stack.readFile().replace("inline Stack", "Stack"))

proc treesitterCSetup*() =
  gitPull("https://github.com/tree-sitter/tree-sitter-c", incDir() / "treesitter_c", """
src/*.h
src/*.c
src/*.cc
""")

  let
    headerc = incDir() / "treesitter_c/src/parser.h"

  headerc.writeFile("""
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_c();
""")

proc treesitterCppSetup*() =
  gitPull("https://github.com/tree-sitter/tree-sitter-cpp", incDir() / "treesitter_cpp", """
src/*.h
src/*.c
src/*.cc
""")

  let
    headercpp = incDir() / "treesitter_cpp/src/parser.h"

  headercpp.writeFile("""
typedef struct TSLanguage TSLanguage;
const TSLanguage *tree_sitter_cpp();
""")
