# nim c tsgen.nim > temp.nim
# Move temp.nim contents to api.nim below generated line + minor adjustments

import os

import nimterop/[cimport, paths]

static:
  cDebug()

cImport(cacheDir / "treesitter" / "lib" / "include" / "tree_sitter" / "api.h", flags = "-E_ -c")
