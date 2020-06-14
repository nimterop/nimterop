import strutils

proc testCall(cmd, output: string, exitCode: int, delete = true) =
  var
    ccmd = "../tests/timeit " & cmd

  if not delete:
    ccmd = ccmd.replace(" -f ", " ")

  var
    (outp, exitC) = gorgeEx(ccmd)
  echo outp
  doAssert exitC == exitCode, $exitC
  doAssert outp.contains(output), outp

var
  cmd = "nim c -f --hints:off -d:FLAGS=\"-f:ast2\" -d:checkAbi"
  lrcmd = " -r lzma.nim"
  zrcmd = " -r zlib.nim"
  sshcmd = " -r libssh2.nim"
  lexp = "liblzma version = "
  zexp = "zlib version = "

testCall(cmd & lrcmd, "No build files found", 1)
testCall(cmd & " -d:libssh2Conan" & sshcmd, "Need version for Conan uri", 1)

when defined(posix):
  # stdlib
  testCall(cmd & " -d:envTest" & lrcmd, lexp, 0)
  testCall(cmd & " -d:envTestStatic" & lrcmd, lexp, 0)

  when not defined(osx):
    testCall(cmd & " -d:zlibStd" & zrcmd, zexp, 0)
    testCall(cmd & " -d:zlibStd -d:zlibStatic" & zrcmd, zexp, 0)

  # git tag
  testCall(cmd & " -d:lzmaGit -d:lzmaSetVer=v5.2.0" & lrcmd, lexp & "5.2.0", 0)
  testCall(cmd & " -d:lzmaGit -d:lzmaStatic -d:lzmaSetVer=v5.2.0" & lrcmd, lexp & "5.2.0", 0, delete = false)

  # conan static
  testCall(cmd & " -d:libssh2Conan -d:libssh2SetVer=1.9.0 -d:libssh2Static" & sshcmd, zexp, 0)
else:
  # conan static for Windows
  testCall(cmd & " -d:zlibConan -d:zlibSetVer=1.2.11 -d:zlibStatic" & zrcmd, zexp, 0)

# git
testCall(cmd & " -d:envTest" & zrcmd, zexp, 0)
testCall(cmd & " -d:envTestStatic" & zrcmd, zexp, 0, delete = false)

# git tag
testCall(cmd & " -d:zlibGit -d:zlibSetVer=v1.2.10" & zrcmd, zexp & "1.2.10", 0)
testCall(cmd & " -d:zlibGit -d:zlibStatic -d:zlibSetVer=v1.2.10" & zrcmd, zexp & "1.2.10", 0, delete = false)

# dl
testCall(cmd & " -d:lzmaDL" & lrcmd, "Need version", 1)
testCall(cmd & " -d:lzmaDL -d:lzmaSetVer=5.2.4" & lrcmd, lexp & "5.2.4", 0)
testCall(cmd & " -d:lzmaDL -d:lzmaStatic -d:lzmaSetVer=5.2.4" & lrcmd, lexp & "5.2.4", 0, delete = false)

# dl
testCall(cmd & " -d:zlibDL -d:zlibSetVer=1.2.11" & zrcmd, zexp & "1.2.11", 0)
testCall(cmd & " -d:zlibDL -d:zlibStatic -d:zlibSetVer=1.2.11" & zrcmd, zexp & "1.2.11", 0, delete = false)

# conan
testCall(cmd & " -d:libssh2Conan -d:libssh2SetVer=1.9.0" & sshcmd, zexp, 0)
