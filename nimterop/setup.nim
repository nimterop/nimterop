import os, strutils

import "."/[git, paths]

proc treesitterSetup*() =
  gitPull("https://github.com/tree-sitter/tree-sitter/", incDir() / "treesitter", """
lib/include/tree_sitter/api.h
lib/src/*
""")

  gitPull("https://github.com/JuliaStrings/utf8proc", incDir() / "utf8proc", """
*.c
*.h
""")

  # TODO: does this work on windows? if not use `os.unixToNativePath`
  let
    stack = incDir() / "treesitter/lib/src/stack.c"

  stack.writeFile(stack.readFile().replace("inline Stack", "Stack"))

proc treesitterCSetup*() =
  gitPull("https://github.com/tree-sitter/tree-sitter-c", incDir() / "treesitter_c", """
src/*.h
src/*.c
src/*.cc
src/tree_sitter/parser.h
""")

  let
    headerc = incDir() / "treesitter_c/src/api.h"

  headerc.writeFile("""
const TSLanguage *tree_sitter_c();
""")

proc treesitterCppSetup*() =
  gitPull("https://github.com/tree-sitter/tree-sitter-cpp", incDir() / "treesitter_cpp", """
src/*.h
src/*.c
src/*.cc
src/tree_sitter/parser.h
""")

  let
    headercpp = incDir() / "treesitter_cpp/src/api.h"

  headercpp.writeFile("""
const TSLanguage *tree_sitter_cpp();
""")
