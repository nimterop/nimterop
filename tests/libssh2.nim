import nimterop/[build, cimport]

const
  outdir = getProjectCacheDir("libssh2")

getHeader(
  header = "libssh2.h",
  conanuri = "libssh2/$1",
  outdir = outdir
)

cOverride:
  type
    stat = object
    stat64 = object
    SOCKET = object
  
when not libssh2Static:
  cImport(libssh2Path, recurse = true, dynlib = "libssh2LPath", flags = "-f:ast2 -c -E_ -F_")

  when not defined(Windows):
    proc zlibVersion(): cstring {.importc, dynlib: libssh2LPath.}
else:
  cImport(libssh2Path, recurse = true, flags = "-f:ast2 -c -E_ -F_")

  when not defined(Windows):
    proc zlibVersion(): cstring {.importc.}

  {.passL: "-lpthread".}

assert libssh2_init(0) == 0

let
  session = libssh2_session_init_ex(nil, nil, nil, nil)

if session == nil:
  quit(1)

libssh2_session_set_blocking(session, 0.cint)

echo "zlib version = " & (block:
  when not defined(Windows):
    $zlibVersion()
  else:
    ""
)