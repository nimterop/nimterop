import macros, os, osproc, regex, strformat, strutils

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

macro extractZip*(zipfile, outdir: static string): untyped =
  var cmd = "unzip -o $#"
  if defined(Windows):
    cmd = "powershell -nologo -noprofile -command \"& { Add-Type -A " &
          "'System.IO.Compression.FileSystem'; " &
          "[IO.Compression.ZipFile]::ExtractToDirectory('$#', '.'); }\""

  echo "Extracting " & zipfile
  discard execAction(&"cd \"{getProjectPath()/outdir}\" && " & cmd % zipfile)

macro downloadUrl*(url, outdir: static string): untyped =
  let
    file = url.extractFilename()
    ext = file.splitFile().ext.toLowerAscii()

  var cmd = "curl $# -o $#"
  if defined(Windows):
    cmd = "powershell wget $# -OutFile $#"

  if not (ext == ".zip" and fileExists(getProjectPath()/outdir/file)):
    echo "Downloading " & file
    discard execAction(cmd % [url, getProjectPath()/outdir/file])

  if ext == ".zip":
    discard quote do:
      extractZip(`file`, `outdir`)

macro gitReset*(outdir: static string): untyped =
  echo "Resetting " & outdir

  let cmd = &"cd \"{getProjectPath()/outdir}\" && git reset --hard"
  while execAction(cmd).contains("Permission denied"):
    sleep(1000)
    echo "  Retrying ..."

macro gitCheckout*(file, outdir: static string): untyped =
  echo "Resetting " & file

  let cmd = &"cd \"{getProjectPath()/outdir}\" && git checkout $#" % file.replace(outdir & "/", "")
  while execAction(cmd).contains("Permission denied"):
    sleep(500)
    echo "  Retrying ..."

macro gitPull*(url: static string, outdirN: static string = "", plist: static string = "", checkout: static string = ""): untyped =
  let
    outdir = if outdirN.isAbsolute(): outdirN else: getProjectPath()/outdirN

  if dirExists(outdir/".git"):
    discard quote do:
      gitReset(`outdir`)
    return
  else:
    let
      flag = when not defined(Windows): "-p" else: ""
    echo execAction(&"mkdir {flag} \"{outdir}\"")

  echo "Setting up Git repo: " & url
  discard execAction(&"cd \"{outdir}\" && git init .")
  discard execAction(&"cd \"{outdir}\" && git remote add origin " & url)

  if plist.len != 0:
    let sparsefile = &"{outdir}/.git/info/sparse-checkout"

    discard execAction(&"cd \"{outdir}\" && git config core.sparsecheckout true")
    writeFile(sparsefile, plist)

  if checkout.len != 0:
    echo "Checking out " & checkout
    discard execAction(&"cd \"{outdir}\" && git pull --tags origin master")
    discard execAction(&"cd \"{outdir}\" && git checkout {checkout}")
  else:
    echo "Pulling repository"
    discard execAction(&"cd \"{outdir}\" && git pull --depth=1 origin master")
