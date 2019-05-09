import os

import nimterop/[cimport, git, paths]

const
  baseDir = nimteropBuildDir()/"pcre"
  pcreH = baseDir/"pcre.h.in"

static:
  if not pcreH.fileExists():
    downloadUrl("https://github.com/svn2github/pcre/raw/master/pcre.h.in", baseDir)
  cDebug()
  cDisableCaching()

const
  dynpcre =
    when defined(windows):
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

cImport(pcreH, dynlib="dynpcre")

echo version()