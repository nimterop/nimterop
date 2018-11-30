import macros, os, osproc, regex, strformat, strutils

import "." / [globals, utils]

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

macro gitPull*(url: static string, outdirN = "", plistN = "", checkoutN = ""): untyped =
  let
    outdir = getProjectPath()/outdirN.strVal()
    plist = plistN.strVal()
    checkout = checkoutN.strVal()

  if dirExists(outdir/".git"):
    discard quote do:
      gitReset(`outdirN`)
    return
  else:
    echo execAction(&"mkdir \"{outdir}\"")

  echo "Setting up Git repo: " & url
  discard execAction(&"cd \"{outdir}\" && git init .")
  discard execAction(&"cd \"{outdir}\" && git remote add origin " & url)

  if plist.len != 0:
    let sparsefile = &"{outdir}/.git/info/sparse-checkout"

    discard execAction(&"cd \"{outdir}\" && git config core.sparsecheckout true")
    writeFile(sparsefile, plist)
    echo "Wrote"

  if checkout.len != 0:
    echo "Checking out " & checkout
    discard execAction(&"cd \"{outdir}\" && git pull --tags origin master")
    discard execAction(&"cd \"{outdir}\" && git checkout {checkout}")
  else:
    echo "Pulling repository"
    discard execAction(&"cd \"{outdir}\" && git pull --depth=1 origin master")
