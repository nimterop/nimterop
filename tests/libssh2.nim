import nimterop/[build, cimport]

const
  outdir = getProjectCacheDir("libssh2")
  libdir =
    when defined(libssh2JBB): "" else: getOutDir() / "libdir"

getHeader(
  header = "libssh2.h",
  conanuri = "libssh2/$1",
  jbburi = "libssh2/1.9.0",
  outdir = outdir,
  libdir = libdir
)

cOverride:
  type
    stat = object
    stat64 = object
    SOCKET = object

when not libssh2Static:
  cImport(libssh2Path, recurse = true, dynlib = libssh2LPath, flags = "-c -E_ -F_")

  when not defined(Windows) and not isDefined(libssh2JBB):
    proc zlibVersion(): cstring {.importc, dynlib: libssh2LPath.extractFilename().}
else:
  cPassL("-lpthread")

  cImport(libssh2Path, recurse = true, flags = "-c -E_ -F_")

  when not defined(Windows) and not isDefined(libssh2JBB):
    proc zlibVersion(): cstring {.importc.}

assert libssh2_init(0) == 0

let
  session = libssh2_session_init_ex(nil, nil, nil, nil)

if session == nil:
  quit(1)

libssh2_session_set_blocking(session, 0.cint)

echo "zlib version = " & (block:
  when not defined(Windows) and not isDefined(libssh2JBB):
    $zlibVersion()
  else:
    ""
)
