import strutils, os

import ".."/[setup, paths]

static:
  treesitterCppSetup()

const srcDir = incDir() / "treesitter_cpp/src"

{.passC: "-I$1" % srcDir.}

import "."/api

when (NimMajor, NimMinor, NimPatch) < (0, 19, 9):
  const srcDirRel = "../../build/inc/treesitter_cpp/src"
else:
  const srcDirRel = srcDir.relativePath(currentSourcePath.parentDir)

# pending https://github.com/nim-lang/Nim/issues/9370 we need srcDirRel instead
# of srcDir
{.compile: (srcDirRel / "parser.c", "nimtero_cpp_parser.c.o").}

#[
D20190127T231316:here note: this will be compiled as a C++ file even with
`nim c`, thanks to the extension (which clang/gcc understands);
however, in `nim c` mode this will fail in link phase
(which by default would use `clang/gcc`)
unless linker is overridden, see D20190127T231316.

cleaner alternative: compile `scanner.cc` into a shared library
that we link against, which avoids the linker hack.
]#

{.compile: srcDir / "scanner.cc".}

proc treeSitterCpp*(): ptr TSLanguage {.importc: "tree_sitter_cpp", header: srcDir / "api.h".}
