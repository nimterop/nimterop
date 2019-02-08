import macros, os, osproc, regex, strformat, strutils

import "."/[paths, compat]

proc execAction*(cmd: string, nostderr=false): string =
  var
    ccmd = ""
    ret = 0
  when defined(Windows):
    ccmd = "cmd /c " & cmd
  elif defined(posix):
    ccmd = cmd
  else:
    doAssert false

  when nimvm:
    (result, ret) = gorgeEx(ccmd)
  else:
    let opt = if nostderr: {poUsePath} else: {poStdErrToStdOut, poUsePath}
    (result, ret) = execCmdEx(ccmd, opt)
  if ret != 0:
    let msg = "Command failed: " & $(ret, nostderr) & "\nccmd: " & ccmd & "\nresult:\n" & result
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
