import macros, os, osproc, regex, strformat, strutils

import "."/paths

proc execAction*(cmd: string, nostderr=false): string =
  var
    ccmd = ""
    ret = 0
  when defined(Windows):
    ccmd = "cmd /c " & cmd
  when defined(Linux) or defined(MacOSX):
    ccmd = "bash -c \"" & cmd & "\""

  when nimvm:
    (result, ret) = gorgeEx(ccmd)
  else:
    if nostderr:
      (result, ret) = execCmdEx(ccmd, {poUsePath})
    else:
      (result, ret) = execCmdEx(ccmd)
  if ret != 0:
    let msg = "Command failed: " & $ret & "\nccmd: " & ccmd & "\nresult:\n" & result
    doAssert false, msg

proc mkDir*(dir: string) =
  if not dirExists(dir):
    let
      flag = when not defined(Windows): "-p" else: ""
    discard execAction(&"mkdir {flag} {dir.quoteShell}")

proc cpFile*(source, dest: string, move=false) =
  let
    source = source.replace("/", $DirSep)
    dest = dest.replace("/", $DirSep)
    cmd =
      when defined(Windows):
        if move:
          "move /y"
        else:
          "copy /y"
      else:
        if move:
          "mv -f"
        else:
          "cp -f"

  discard execAction(&"{cmd} {source.quoteShell} {dest.quoteShell}")

proc mvFile*(source, dest: string) =
  cpFile(source, dest, move=true)

when (NimMajor, NimMinor, NimPatch) < (0, 19, 9):
  proc relativePath*(path, base: string; sep = DirSep): string =
    ## Copied from `os.relativePath` ; remove after nim >= 0.19.9
    if path.len == 0: return ""
    var f, b: PathIter
    var ff = (0, -1)
    var bb = (0, -1) # (int, int)
    result = newStringOfCap(path.len)
    while f.hasNext(path) and b.hasNext(base):
      ff = next(f, path)
      bb = next(b, base)
      let diff = ff[1] - ff[0]
      if diff != bb[1] - bb[0]: break
      var same = true
      for i in 0..diff:
        if path[i + ff[0]] !=? base[i + bb[0]]:
          same = false
          break
      if not same: break
      ff = (0, -1)
      bb = (0, -1)

    while true:
      if bb[1] >= bb[0]:
        if result.len > 0 and result[^1] != sep:
          result.add sep
        result.add ".."
      if not b.hasNext(base): break
      bb = b.next(base)

    while true:
      if ff[1] >= ff[0]:
        if result.len > 0 and result[^1] != sep:
          result.add sep
        for i in 0..ff[1] - ff[0]:
          result.add path[i + ff[0]]
      if not f.hasNext(path): break
      ff = f.next(path)

proc extractZip*(zipfile, outdir: string) =
  var cmd = "unzip -o $#"
  if defined(Windows):
    cmd = "powershell -nologo -noprofile -command \"& { Add-Type -A " &
          "'System.IO.Compression.FileSystem'; " &
          "[IO.Compression.ZipFile]::ExtractToDirectory('$#', '.'); }\""

  echo "Extracting " & zipfile
  discard execAction(&"cd {outdir.quoteShell} && {cmd % zipfile}")

proc downloadUrl*(url, outdir: string) =
  let
    file = url.extractFilename()
    ext = file.splitFile().ext.toLowerAscii()

  if not (ext == ".zip" and fileExists(outdir/file)):
    echo "Downloading " & file
    mkDir(outdir)
    var cmd = if defined(Windows):
      "powershell wget $# -OutFile $#"
    else:
      "curl $# -o $#"
    discard execAction(cmd % [url, outdir/file])

    if ext == ".zip":
      extractZip(file, outdir)

proc gitReset*(outdir: string) =
  echo "Resetting " & outdir

  let cmd = &"cd {outdir.quoteShell} && git reset --hard"
  while execAction(cmd).contains("Permission denied"):
    sleep(1000)
    echo "  Retrying ..."

proc gitCheckout*(file, outdir: string) =
  echo "Resetting " & file
  let file2 = file.relativePath outdir
  let cmd = &"cd {outdir.quoteShell} && git checkout {file2.quoteShell}"
  while execAction(cmd).contains("Permission denied"):
    sleep(500)
    echo "  Retrying ..."

proc gitPull*(url: string, outdir = "", plist = "", checkout = "") =
  if dirExists(outdir/".git"):
    gitReset(outdir)
    return

  let
    outdir2 = outdir.quoteShell

  mkDir(outdir2)

  echo "Setting up Git repo: " & url
  discard execAction(&"cd {outdir2} && git init .")
  discard execAction(&"cd {outdir2} && git remote add origin {url}")

  if plist.len != 0:
    # TODO: document this, it's not clear
    let sparsefile = outdir / ".git/info/sparse-checkout"

    discard execAction(&"cd {outdir2} && git config core.sparsecheckout true")
    writeFile(sparsefile, plist)

  if checkout.len != 0:
    echo "Checking out " & checkout
    discard execAction(&"cd {outdir2} && git pull --tags origin master")
    discard execAction(&"cd {outdir2} && git checkout {checkout}")
  else:
    echo "Pulling repository"
    discard execAction(&"cd {outdir2} && git pull --depth=1 origin master")
