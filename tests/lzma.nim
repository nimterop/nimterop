import os, strutils

import nimterop/[build, cimport]

const
  baseDir = currentSourcePath.parentDir()/"build/liblzma"

static:
  cDebug()

when defined(envTest):
  setDefines(@["lzmaStd"])
elif defined(envTestStatic):
  setDefines(@["lzmaStd", "lzmaStatic"])

getHeader(
  "lzma.h",
  giturl = "https://github.com/xz-mirror/xz",
  dlurl = "https://tukaani.org/xz/xz-$1.tar.gz",
  outdir = baseDir,
  conFlags = "--disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo"
)

cPlugin:
  import strutils

  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    sym.name = sym.name.strip(chars = {'_'})

cOverride:
  type
    lzma_internal = object
    lzma_index = object
    lzma_index_hash = object

    lzma_options_lzma = object
    lzma_stream_flags = object
    lzma_block = object
    lzma_index_iter = object

when not lzmaStatic:
  cImport(lzmaPath, recurse = true, dynlib = "lzmaLPath")
else:
  cImport(lzmaPath, recurse = true)

echo "liblzma version = " & $lzma_version_string()
