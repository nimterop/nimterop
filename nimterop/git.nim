import macros, os, osproc, regex, strformat, strutils

import "."/paths

proc execAction*(cmd: string, nostderr=false): string =
  var
    ccmd = ""
    ret = 0
  when defined(Windows):
    ccmd = "cmd /c " & cmd
  when defined(Linux) or defined(MacOSX):
    ccmd = "bash -c '" & cmd & "'"

  when nimvm:
    (result, ret) = gorgeEx(ccmd)
  else:
    if nostderr:
      (result, ret) = execCmdEx(ccmd, {poUsePath})
    else:
      (result, ret) = execCmdEx(ccmd)
  if ret != 0:
    echo "Command failed: " & $ret
    echo ccmd
    echo result
    quit(1)

proc extractZip*(zipfile, outdir: string) =
  var cmd = "unzip -o $#"
  if defined(Windows):
    cmd = "powershell -nologo -noprofile -command \"& { Add-Type -A " &
          "'System.IO.Compression.FileSystem'; " &
          "[IO.Compression.ZipFile]::ExtractToDirectory('$#', '.'); }\""

  echo "Extracting " & zipfile
  let cmd2 = cmd % zipfile
  discard execAction(&"cd {outdir.quoteShell} && {cmd2}")

proc downloadUrl*(url, outdir: string) =
  doAssert outdir.isAbsolute
  let
    file = url.extractFilename()
    ext = file.splitFile().ext.toLowerAscii()

  if not (ext == ".zip" and fileExists(outdir/file)):
    echo "Downloading " & file
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

proc relativePathNaive*(file, base: string): string =
  ## naive version of `os.relativePath` ; remove after nim >= 0.19.9
  runnableExamples:
    doAssert "/foo/bar/baz/log.txt".relativePathNaive("/foo/bar") == "baz/log.txt"
  var base = base
  if not base.endsWith "/": base.add "/"
  doAssert file.startsWith base
  result = file[base.len .. ^1]

proc gitCheckout*(file, outdir: string) =
  echo "Resetting " & file
  let file2 = file.relativePathNaive outdir
  let cmd = &"cd {outdir.quoteShell} && git checkout {file2.quoteShell}"
  while execAction(cmd).contains("Permission denied"):
    sleep(500)
    echo "  Retrying ..."

proc gitPull*(url: string, outdir = "", plist = "", checkout = "") =
  doAssert outdir.isAbsolute()
  if dirExists(outdir/".git"):
    gitReset(outdir)
    return
  let
    outdir2 = outdir.quoteShell
    flag = when not defined(Windows): "-p" else: ""
  echo execAction(&"mkdir {flag} {outdir2}")

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
