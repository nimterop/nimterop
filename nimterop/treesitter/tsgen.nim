# nim c tsgen.nim > temp.nim
# Move temp.nim contents to api.nim below generated line + minor adjustments

import os

import nimterop/[cimport, paths]

cPlugin:
  import strutils

  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    if "_CRT" in sym.name:
      sym.name = sym.name.strip(chars={'_'})

static:
  cDebug()

cImport(cacheDir / "treesitter" /"lib" / "include" / "tree_sitter" / "api.h")
