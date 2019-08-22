import os, strutils

import "."/[build, paths]

proc treesitterSetup*() =
  gitPull("https://github.com/tree-sitter/tree-sitter", incDir() / "treesitter", """
lib/include/*
lib/src/*
""", "0.15.5")

  gitPull("https://github.com/JuliaStrings/utf8proc", incDir() / "utf8proc", """
*.c
*.h
""")

  let
    tbase = incDir() / "treesitter/lib"
    stack = tbase / "src/stack.c"
    parser = tbase / "include/tree_sitter/parser.h"
    tparser = parser.replace("parser", "tparser")
    language = tbase / "src/language.h"
    lexer = tbase / "src/lexer.h"
    subtree = tbase / "src/subtree.h"

  stack.writeFile(stack.readFile().replace("inline Stack", "Stack"))

  # parser.h
  mvFile(parser, tparser)
  language.writeFile(language.readFile().replace("parser.h", "tparser.h"))
  lexer.writeFile(lexer.readFile().replace("parser.h", "tparser.h"))
  subtree.writeFile(subtree.readFile().replace("parser.h", "tparser.h"))

proc treesitterCSetup*() =
  gitPull("https://github.com/tree-sitter/tree-sitter-c", incDir() / "treesitter_c", """
src/*.h
src/*.c
src/*.cc
src/tree_sitter/parser.h
""", "v0.15.0")

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
""", "v0.15.0")

  let
    headercpp = incDir() / "treesitter_cpp/src/api.h"

  headercpp.writeFile("""
const TSLanguage *tree_sitter_cpp();
""")
