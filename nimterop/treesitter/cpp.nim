import strutils, os

import ".."/[setup,paths]

static:
  treesitterCppSetup()

import "."/runtime

const srcDir = incDir() / "treesitter_cpp/src"
const srcDirRel = srcDir.relativePath(currentSourcePath.parentDir)

# pending https://github.com/nim-lang/Nim/issues/9370
# use simply: {.compile: srcDir / "parser.c".}
{.compile: (srcDirRel / "parser.c", "parser.c.cpp.o").}

{.compile: srcDir / "scanner.cc".}

proc treeSitterCpp*(): ptr TSLanguage {.importc: "tree_sitter_cpp", header: srcDir / "parser.h".}
