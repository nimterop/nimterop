import os, osproc, strformat, strutils

import "."/[compat]

proc execAction*(cmd: string, nostderr=false): string =
  ## Execute an external command - supported at compile time
  ##
  ## Checks if command exits successfully before returning. If not, an
  ## error is raised.
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
  doAssert ret == 0, "Command failed: " & $(ret, nostderr) & "\nccmd: " & ccmd & "\nresult:\n" & result

proc findExe*(exe: string): string =
  ## Find the specified executable using the which/where command - supported
  ## at compile time
  var
    cmd =
      when defined(windows):
        "where " & exe
      else:
        "which " & exe

    (oup, code) = gorgeEx(cmd)

  if code == 0:
    return oup.strip()

proc mkDir*(dir: string) =
  ## Create a directory at cmopile time
  ##
  ## The `os` module is not available at compile time so a few
  ## crucial helper functions are included with nimterop.
  if not dirExists(dir):
    let
      flag = when not defined(Windows): "-p" else: ""
    discard execAction(&"mkdir {flag} {dir.quoteShell}")

proc cpFile*(source, dest: string, move=false) =
  ## Copy a file from source to destination at compile time
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
  ## Move a file from source to destination at compile time
  cpFile(source, dest, move=true)

proc extractZip*(zipfile, outdir: string) =
  ## Extract a zip file using powershell on Windows and unzip on other
  ## systems to the specified output directory
  var cmd = "unzip -o $#"
  if defined(Windows):
    cmd = "powershell -nologo -noprofile -command \"& { Add-Type -A " &
          "'System.IO.Compression.FileSystem'; " &
          "[IO.Compression.ZipFile]::ExtractToDirectory('$#', '.'); }\""

  echo "# Extracting " & zipfile
  discard execAction(&"cd {outdir.quoteShell} && {cmd % zipfile}")

proc downloadUrl*(url, outdir: string) =
  ## Download a file using curl or wget (or powershell on Windows) to the specified directory
  ##
  ## If a zip file, it is automatically extracted after download.
  let
    file = url.extractFilename()
    ext = file.splitFile().ext.toLowerAscii()

  if not (ext == ".zip" and fileExists(outdir/file)):
    echo "# Downloading " & file
    mkDir(outdir)
    var cmd = findExe("curl")
    if cmd.len != 0:
      cmd &= " -L $# -o $#"
    else:
      cmd = findExe("wget")
      if cmd.len != 0:
        cmd &= " $# -o $#"
      elif defined(Windows):
        cmd = "powershell [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; wget $# -OutFile $#"
      else:
        doAssert false, "No download tool available - curl, wget"
    discard execAction(cmd % [url, (outdir/file).quoteShell])

    if ext == ".zip":
      extractZip(file, outdir)

proc gitReset*(outdir: string) =
  ## Hard reset the git repository at the specified directory
  echo "# Resetting " & outdir

  let cmd = &"cd {outdir.quoteShell} && git reset --hard"
  while execAction(cmd).contains("Permission denied"):
    sleep(1000)
    echo "#   Retrying ..."

proc gitCheckout*(file, outdir: string) =
  ## Checkout the specified file in the git repository specified
  ##
  ## This effectively resets all changes in the file and can be
  ## used to undo any changes that were made to source files to enable
  ## successful wrapping with `cImport()` or `c2nImport()`.
  echo "# Resetting " & file
  let file2 = file.relativePath outdir
  let cmd = &"cd {outdir.quoteShell} && git checkout {file2.quoteShell}"
  while execAction(cmd).contains("Permission denied"):
    sleep(500)
    echo "#   Retrying ..."

proc gitPull*(url: string, outdir = "", plist = "", checkout = "") =
  ## Pull the specified git repository to the output directory
  ##
  ## `plist` is the list of specific files and directories or wildcards
  ## to sparsely checkout. Multiple values can be specified one entry per
  ## line. It is optional and if omitted, the entire repository will be
  ## checked out.
  ##
  ## `checkout` is the git tag, branch or commit hash to checkout once
  ## the repository is downloaded. This allows for pinning to a specific
  ## version of the code.
  if dirExists(outdir/".git"):
    gitReset(outdir)
    return

  let
    outdirQ = outdir.quoteShell

  mkDir(outdir)

  echo "# Setting up Git repo: " & url
  discard execAction(&"cd {outdirQ} && git init .")
  discard execAction(&"cd {outdirQ} && git remote add origin {url}")

  if plist.len != 0:
    # If a specific list of files is required, create a sparse checkout
    # file for git in its config directory
    let sparsefile = outdir / ".git/info/sparse-checkout"

    discard execAction(&"cd {outdirQ} && git config core.sparsecheckout true")
    writeFile(sparsefile, plist)

  if checkout.len != 0:
    echo "# Checking out " & checkout
    discard execAction(&"cd {outdirQ} && git pull --tags origin master")
    discard execAction(&"cd {outdirQ} && git checkout {checkout}")
  else:
    echo "# Pulling repository"
    discard execAction(&"cd {outdirQ} && git pull --depth=1 origin master")

proc configure*(path, check: string, flags = "") =
  ## Run the GNU `configure` command to generate all Makefiles or other
  ## build scripts in the specified path
  ##
  ## If a `configure` script is not present and an `autogen.sh` script
  ## is present, it will be run before attempting `configure`.
  ##
  ## `check` is a file that will be generated by the `configure` command.
  ## This is required to prevent configure from running on every build. It
  ## is relative to the `path` and should not be an absolute path.
  ##
  ## `flags` are any flags that should be passed to the `configure` command.
  if (path / check).fileExists():
    return

  echo "# Configuring " & path

  if not fileExists(path / "configure"):
    if fileExists(path / "autogen.sh"):
      echo "#   Running autogen.sh"

      discard execAction(&"cd {path.quoteShell} && bash autogen.sh")

  if fileExists(path / "configure"):
    echo "#   Running configure " & flags

    var
      cmd = &"cd {path.quoteShell} && bash configure"
    if flags.len != 0:
      cmd &= &" {flags}"

    echo execAction(cmd)

proc cmake*(path, check, flags: string) =
  ## Run the `cmake` command to generate all Makefiles or other
  ## build scripts in the specified path
  ##
  ## `path` will be created since typically `cmake` is run in an
  ## empty directory.
  ##
  ## `check` is a file that will be generated by the `cmake` command.
  ## This is required to prevent `cmake` from running on every build. It
  ## is relative to the `path` and should not be an absolute path.
  ##
  ## `flags` are any flags that should be passed to the `cmake` command.
  ## Unlike `configure`, it is required since typically it will be the
  ## path to the repository, typically `..` when `path` is a subdir.
  if (path / check).fileExists():
    return

  echo "# Running cmake " & flags
  echo "#   Path: " & path

  mkDir(path)

  var
    cmd = &"cd {path.quoteShell} && cmake {flags}"

  echo execAction(cmd)

proc make*(path, check: string, flags = "") =
  ## Run the `make` command to build all binaries in the specified path
  ##
  ## `check` is a file that will be generated by the `make` command.
  ## This is required to prevent `make` from running on every build. It
  ## is relative to the `path` and should not be an absolute path.
  ##
  ## `flags` are any flags that should be passed to the `make` command.
  ##
  ## If make.exe is missing and mingw32-make.exe is available, it will
  ## be copied over to make.exe in the same location.
  if (path / check).fileExists():
    return

  echo "# Running make " & flags
  echo "#   Path: " & path

  var
    cmd = findExe("make")

  if cmd.len == 0:
    cmd = findExe("mingw32-make")
    if cmd.len != 0:
      cpFile(cmd, cmd.replace("mingw32-make", "make"))
  doAssert cmd.len != 0, "Make not found"

  cmd = &"cd {path.quoteShell} && make"
  if flags.len != 0:
    cmd &= &" {flags}"

  echo execAction(cmd)