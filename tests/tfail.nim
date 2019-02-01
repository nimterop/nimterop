when defined(case_D20190123T230907): # bad test case
  import nimterop/cimport
  cCompile "nonexistant"
else:
  import os, osproc, strformat, strutils
  proc main() =
    const nim = getCurrentCompilerExe()
    const input = currentSourcePath()
    let cmd = fmt"{nim} c -r -d:case_D20190123T230907 {input}"
    var (output, exitCode) = execCmdEx(cmd)
    # echo "{" & output & "}"
    doAssert exitCode != 0
    doAssert output.string.contains """`(not fail)` File or directory not found: nonexistant"""
  main()
