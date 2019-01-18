import os, nimterop/[cimport, git]

gitPull("https://github.com/jarikomppa/soloud", "soloud", "include/*\nsrc & *\n")

cDebug()

const
  inc = "soloud/include"
  src = "soloud/src"

cIncludeDir(inc)

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

cImport(inc/"soloud_c.h")

var
  s = Soloud_create()

echo s.Soloud_init()

s.Soloud_destroy()