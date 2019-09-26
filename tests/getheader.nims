import strutils

proc testCall(cmd, output: string, exitCode: int, delete = true) =
  if delete:
    rmDir("build/liblzma")
    rmDir("build/zlib")
  echo cmd
  var
    ccmd =
      when defined(windows):
        "cmd /c " & cmd
      else:
        cmd
    (outp, exitC) = gorgeEx(ccmd)
  echo outp
  doAssert exitC == exitCode, $exitC
  doAssert outp.contains(output), outp

var
  cmd = "nim c -f"
  lrcmd = " -r lzma.nim"
  zrcmd = " -r zlib.nim"
  lexp = "liblzma version = "
  zexp = "zlib version = "

testCall(cmd & lrcmd, "No build files found", 1)

when defined(posix):
  # stdlib
  testCall(cmd & " -d:envTest" & lrcmd, lexp, 0)
  testCall(cmd & " -d:envTestStatic" & lrcmd, lexp, 0)

  when not defined(osx):
    testCall(cmd & " -d:zlibStd" & zrcmd, zexp, 0)
    testCall(cmd & " -d:zlibStd -d:zlibStatic" & zrcmd, zexp, 0)

  # git
  testCall(cmd & " -d:lzmaGit" & lrcmd, lexp, 0)
  testCall(cmd & " -d:lzmaGit -d:lzmaStatic" & lrcmd, lexp, 0, delete = false)

  # git tag
  testCall(cmd & " -d:lzmaGit -d:lzmaSetVer=v5.2.0" & lrcmd, lexp & "5.2.0", 0)
  testCall(cmd & " -d:lzmaGit -d:lzmaStatic -d:lzmaSetVer=v5.2.0" & lrcmd, lexp & "5.2.0", 0, delete = false)
  testCall("cd build/liblzma && git branch", "v5.2.0", 0, delete = false)

# git
testCall(cmd & " -d:envTest" & zrcmd, zexp, 0)
testCall(cmd & " -d:envTestStatic" & zrcmd, zexp, 0, delete = false)

# git tag
testCall(cmd & " -d:zlibGit -d:zlibSetVer=v1.2.10" & zrcmd, zexp & "1.2.10", 0)
testCall(cmd & " -d:zlibGit -d:zlibStatic -d:zlibSetVer=v1.2.10" & zrcmd, zexp & "1.2.10", 0, delete = false)
testCall("cd build/zlib && git branch", "v1.2.10", 0, delete = false)

# dl
testCall(cmd & " -d:lzmaDL" & lrcmd, "Need version", 1)
testCall(cmd & " -d:lzmaDL -d:lzmaSetVer=5.2.4" & lrcmd, lexp & "5.2.4", 0)
testCall(cmd & " -d:lzmaDL -d:lzmaStatic -d:lzmaSetVer=5.2.4" & lrcmd, lexp & "5.2.4", 0, delete = false)

# dl
testCall(cmd & " -d:zlibDL -d:zlibSetVer=1.2.11" & zrcmd, zexp & "1.2.11", 0)
testCall(cmd & " -d:zlibDL -d:zlibStatic -d:zlibSetVer=1.2.11" & zrcmd, zexp & "1.2.11", 0, delete = false)
