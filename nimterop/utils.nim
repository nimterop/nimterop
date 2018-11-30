import osproc
import strformat

proc execAction*(cmd: string): string =
  var
    ccmd = ""
    status = 0
  when defined(Windows):
    ccmd = "cmd /c " & cmd
  elif defined(posix):
    # TODO: addQuoted (safer)
    # TODO: is `bash -c` needed?
    ccmd = "bash -c '" & cmd & "'"
  else:
    static: doAssert false

  when nimvm:
    (result, status) = gorgeEx(ccmd)
  else:
    (result, status) = execCmdEx(ccmd)
  if status != 0:
    echo "Command failed; status: " & $status
    echo ccmd
    echo result
    doAssert false

proc existsFileStatic*(file: string): bool =
  # TODO: Nim PR
  when defined(posix):
    let (_, status) = gorgeEx fmt"test -e {file.quoteShell}"
    result = status == 0
  else:
    # TODO
    doAssert false

proc removeFileStatic*(file: string)=
  # TODO: Nim PR
  when defined(posix):
    discard execAction(fmt"/bin/rm {file.quoteShell}")
  else:
    # TODO
    discard
