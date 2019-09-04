import strutils

proc testCall(cmd, output: string, exitCode: int, delete = true) =
  if delete:
    rmDir("build/liblzma")
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
  rcmd = " -r lzma.nim"
  exp = "liblzma version = "

when defined(posix):
  testCall(cmd & rcmd, "No build files found", 1)

  # stdlib
  testCall(cmd & " -d:lzmaStd" & rcmd, exp, 0)
  testCall(cmd & " -d:lzmaStd -d:lzmaStatic" & rcmd, exp, 0)

  # git
  testCall(cmd & " -d:lzmaGit" & rcmd, exp, 0)
  testCall(cmd & " -d:lzmaGit -d:lzmaStatic" & rcmd, exp, 0, delete = false)

  # git tag
  testCall(cmd & " -d:lzmaGit -d:lzmaVersion=v5.2.0" & rcmd, exp & "5.2.0", 0)
  testCall(cmd & " -d:lzmaGit -d:lzmaStatic -d:lzmaVersion=v5.2.0" & rcmd, exp & "5.2.0", 0, delete = false)
  testCall("cd build/liblzma && git branch", "v5.2.0", 0, delete = false)

  # dl
  testCall(cmd & " -d:lzmaDL" & rcmd, "Need version", 1)
  testCall(cmd & " -d:lzmaDL -d:lzmaVersion=v5.2.4" & rcmd, exp & "5.2.4", 0)
  testCall(cmd & " -d:lzmaDL -d:lzmaStatic -d:lzmaVersion=v5.2.4" & rcmd, exp & "5.2.4", 0, delete = false)
