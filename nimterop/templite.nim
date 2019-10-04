import os, strutils

import nimterop/[cimport, build, paths]

const
  baseDir = currentSourcePath.parentDir()/"build"

  srcDir = baseDir/"project"

static:
  cDebug()
  cDisableCaching()
  
  gitPull("https://github.com/user/project", outdir = srcDir, plist = """
include/*.h
src/*.c
""", checkout = "tag/branch/hash")

  downloadUrl("https://hostname.com/file.h", outdir = srcDir)

cIncludeDir(srcDir/"include")

cDefine("SYMBOL", "value")

{.passC: "flags".}
{.passL: "flags".}

cCompile(srcDir/"file.c")

cPlugin:
  import strutils

  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    sym.name = sym.name.strip(chars = {'_'})

cImport(srcDir/"include/file.h", recurse = true)
