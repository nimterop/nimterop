import os, nimterop/[cimport, git]

const
  incl = "soloud/include"
  src = "soloud/src"

gitPull("https://github.com/jarikomppa/soloud", "soloud", "include/*\nsrc/*\n")

cDebug()
cDisableCaching()

cOverride:
  type
    Soloud* = pointer
    AlignedFloatBuffer* = pointer

  proc Soloud_destroy*(aSoloud: ptr Soloud) {.importc: "Soloud_destroy", header: cSearchPath(incl/"soloud_c.h").}

cSkipSymbol("WavStream_stop", "WavStream_setFilter")

cIncludeDir(incl)

when defined(Linux):
  {.passL: "-lpthread".}
  cDefine("WITH_OSS")
  cCompile(src/"backend/oss/*.cpp")

when defined(Windows):
  {.passC: "-msse".}
  {.passL: "-lwinmm".}
  cDefine("WITH_WINMM")
  cCompile(src/"backend/winmm/*.cpp")

cCompile(src/"c_api/soloud_c.cpp")
cCompile(src/"core/*.cpp")
cCompile(src/"audiosource", "cpp")
cCompile(src/"audiosource", "c")
cCompile(src/"filter/*.cpp")

cImport(incl/"soloud_c.h")

var
  s = Soloud_create()

echo s.Soloud_init()

s.Soloud_destroy()

when declared(WavStream_stop):
  assert "WavStream_stop() not skipped"

when declared(WavStream_setFilter):
  assert "WavStream_setFilter not skipped"