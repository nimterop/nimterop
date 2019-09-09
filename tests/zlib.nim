import os, strutils

import nimterop/[build, cimport]

const
  baseDir = currentSourcePath.parentDir()/"build"/"zlib"

static:
  cDebug()

proc zlibPreBuild(outdir, path: string) =
  let
    mf = outdir / "Makefile"
  if mf.fileExists():
    # Delete default Makefile
    if mf.readFile().contains("configure first"):
      mf.rmFile()
      when defined(windows):
        # Fix static lib name on Windows
        setCmakeLibName(outdir, "zlibstatic", prefix = "lib", oname = "zlib", suffix = ".a")

getHeader(
  "zlib.h",
  giturl = "https://github.com/madler/zlib",
  dlurl = "http://zlib.net/zlib-$1.tar.gz",
  outdir = baseDir,
  altNames = "z"
)

cPlugin:
  import regex, strutils

  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    sym.name = sym.name.replace(re"_[_]+", "_").strip(chars = {'_'})

cOverride:
  type
    voidpf = ptr object
    voidpc = ptr object
    voidp = ptr object
    uLongf = culong
    z_size_t = culong
    z_crc_t = culong
    alloc_func* {.importc.} = proc(opaque: voidpf, items, size: uint) {.cdecl.}
    Bytef {.importc.} = object
  
  when defined(posix):
    type
      pthread_mutex_s = object
      pthread_cond_s = object
      pthread_rwlock_arch_t = object
      extension = object
      fd_set = object

when defined(posix):
  static:
    cSkipSymbol(@["u_int8_t", "u_int16_t", "u_int32_t", "u_int64_t"])

when defined(zlibGit) or defined(zlibDL):
  when dirExists(baseDir / "build"):
    cIncludeDir(baseDir / "build")

when not defined(zlibStatic):
  cImport(zlibPath, recurse = true, dynlib = "zlibLPath")
else:
  cImport(zlibPath, recurse = true)

echo "zlib version = " & $zlibVersion()
