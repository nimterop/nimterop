import os

import nimterop/[cimport, build]

const
  baseDir = getProjectCacheDir("nimterop" / "tests" / "pcre")
  pcreH = baseDir/"pcre.h.in"

static:
  if not pcreH.fileExists():
    downloadUrl("https://github.com/svn2github/pcre/raw/master/pcre.h.in", baseDir)
  cDisableCaching()

const
  dynpcre =
    when defined(Windows):
      when defined(cpu64):
        "pcre64.dll"
      else:
        "pcre32.dll"
    elif hostOS == "macosx":
      "libpcre(.3|.1|).dylib"
    else:
      "libpcre.so(.3|.1|)"

cPlugin:
  import strutils

  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    sym.name = sym.name.replace("pcre_", "")
    if sym.name.startsWith("pcre16_") or sym.name.startsWith("pcre32_"):
      sym.name = ""

const FLAGS {.strdefine.} = ""
cImport(pcreH, dynlib="dynpcre", flags="--mode=c " & FLAGS)
echo version()

when FLAGS.len != 0:
  # Legacy algorithm is broken - does not convert void * return to pointer
  proc my_malloc(a1: uint): pointer {.cdecl.} =
    discard

  malloc = my_malloc
