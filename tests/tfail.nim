when defined(case_D20190123T230907): # bad test case
  import nimterop/cimport
  cCompile "nonexistant"
else:
  import os, osproc, strformat, strutils
  proc main() =
    when (NimMajor, NimMinor, NimPatch) < (0, 19, 9):
      const nim = "nim"
    else:
      const nim = getCurrentCompilerExe()
    const input = currentSourcePath()
    let cmd = fmt"{nim} c -r -d:case_D20190123T230907 {input}"
    var (output, exitCode) = execCmdEx(cmd)
    doAssert exitCode != 0
    doAssert output.string.contains "findPath", output
    doAssert output.string.contains "File or directory not found: nonexistant", output
  main()
