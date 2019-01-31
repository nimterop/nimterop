import os, nimterop/[cimport, git, paths]

const
  baseDir = nimteropBuildDir()/"soloud"
  incl = baseDir/"include"
  src = baseDir/"src"

static:
  gitPull("https://github.com/jarikomppa/soloud", baseDir, "include/*\nsrc/*\n")

cDisableCaching()

cOverride:
  type
    Soloud* = pointer
    AlignedFloatBuffer* = pointer

  proc Soloud_destroy*(aSoloud: ptr Soloud) {.importc: "Soloud_destroy", header: cSearchPath(incl/"soloud_c.h").}

# todo: factor common parts with tests/tsoloud.nim
cSkipSymbol("WavStream_stop", "WavStream_setFilter")

cIncludeDir(incl)

when defined(osx):
  cDefine("WITH_COREAUDIO")
  {.passL: "-framework CoreAudio -framework AudioToolbox".}
  cCompile(src/"backend/coreaudio/*.cpp")
elif defined(Linux):
  {.passL: "-lpthread".}
  cDefine("WITH_OSS")
  cCompile(src/"backend/oss/*.cpp")
elif defined(Windows):
  {.passC: "-msse".}
  {.passL: "-lwinmm".}
  cDefine("WITH_WINMM")
  cCompile(src/"backend/winmm/*.cpp")
else:
  static: doAssert false

cCompile(src/"c_api/soloud_c.cpp")
cCompile(src/"core/*.cpp")
cCompile(src/"audiosource", "cpp")
cCompile(src/"audiosource", "c")
cCompile(src/"filter/*.cpp")

cImport(incl/"soloud_c.h")

import httpclient

let urlDefault = "https://freewavesamples.com/files/Yamaha-V50-Rock-Beat-120bpm.wav"

proc main(file = "", url = urlDefault, volume = 10.0) =
  var file = file
  if file == "":
    var content = newHttpClient().getContent(url)
    file = nimteropBuildDir() / "D20190131T001105.wav"
    file.writeFile content

  var s = Soloud_create()
  defer: s.Soloud_destroy()

  doAssert s.Soloud_init() == 0
  defer: Soloud_deinit(s)

  Soloud_setGlobalVolume(s, volume)

  var sample = Wav_create()
  defer: sample.Wav_destroy()

  doAssert sample.Wav_load(file.cstring) == 0
  doAssert s.Soloud_play(sample) == 1 # check why this is 1
  while s.Soloud_getActiveVoiceCount() > 0.cuint:
    sleep(100)

when isMainModule:
  import cligen
  dispatch(main)
