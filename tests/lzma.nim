import os, strutils

import nimterop/[build, cimport]

const
  FLAGS {.strdefine.} = ""

  baseDir = getProjectCacheDir("nimterop" / "tests" / "liblzma")
  tflags = "--prefix=___,__,_ --suffix=__,_ " & FLAGS

static:
  cSkipSymbol(@[
    "PRIX8", "PRIX16", "PRIX32",
    "PRIXLEAST8", "PRIXLEAST16", "PRIXLEAST32",
    "PRIXFAST8"
  ])

when defined(envTest):
  setDefines(@["lzmaStd"])
elif defined(envTestStatic):
  setDefines(@["lzmaStd", "lzmaStatic"])

getHeader(
  "lzma.h",
  giturl = "https://github.com/xz-mirror/xz",
  dlurl = "https://tukaani.org/xz/xz-$1.tar.gz",
  conanuri = "xz_utils",
  jbburi = "xz",
  outdir = baseDir,
  conFlags = "--disable-xz --disable-xzdec --disable-lzmadec --disable-lzmainfo"
)

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
  cImport(lzmaPath, recurse = true, dynlib = "lzmaLPath", flags = tflags)
else:
  cImport(lzmaPath, recurse = true, flags = tflags)

echo "liblzma version = " & $lzma_version_string()
