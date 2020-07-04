import hashes, osproc, sets, strformat, strutils

when not defined(TOAST):
  import os except findExe, sleep
else:
  import os

import ".."/globals
import "."/[misc, nimconf]

when not defined(TOAST):
  proc sleep*(milsecs: int) =
    ## Sleep at compile time
    let
      cmd =
        when defined(Windows):
          "cmd /c timeout "
        else:
          "sleep "

    discard gorgeEx(cmd & $(milsecs / 1000))
else:
  export sleep

proc execAction*(cmd: string, retry = 0, die = true, cache = false,
                 cacheKey = "", onRetry: proc() = nil,
                 onError: proc(output: string, err: int) = nil): tuple[output: string, ret: int] =
  ## Execute an external command - supported at compile time
  ##
  ## Checks if command exits successfully before returning. If not, an
  ## error is raised. Always caches results to be used in nimsuggest or nimcheck
  ## mode.
  ##
  ## `retry` - number of times command should be retried before error
  ## `die = false` - return on errors
  ## `cache = true` - cache results unless cleared with -f
  ## `cacheKey` - key to create unique cache entry
  ## `onRetry()` - proc to call before retrying
  ## `onError(output, err)` - proc to call on error
  let
    ccmd = fixCmd(cmd)

  when nimvm:
    # Cache results for speedup if cache = true
    # Else cache for preserving functionality in nimsuggest and nimcheck
    let
      hash = (ccmd & cacheKey).hash().abs()
      cachePath = getNimteropCacheDir() / "execCache" / "nimterop_" & $hash
      cacheFile = cachePath & ".txt"
      retFile = cachePath & "_ret.txt"

    when defined(nimsuggest) or defined(nimcheck):
      # Load results from cache file if generated in previous run
      if fileExists(cacheFile) and fileExists(retFile):
        result.output = cacheFile.readFile()
        result.ret = retFile.readFile().parseInt()
      elif die:
        doAssert false, "Results not cached - run nim c/cpp at least once\n" & ccmd
    else:
      if cache and fileExists(cacheFile) and fileExists(retFile) and not compileOption("forceBuild"):
        # Return from cache when requested
        result.output = cacheFile.readFile()
        result.ret = retFile.readFile().parseInt()
      else:
        # Execute command and store results in cache
        (result.output, result.ret) = gorgeEx(ccmd)
        if result.ret == 0 or die == false:
          # mkdir for execCache dir (circular dependency)
          let dir = cacheFile.parentDir()
          if not dirExists(dir):
            let flag = when not defined(Windows): "-p" else: ""
            discard execAction(&"mkdir {flag} {dir.sanitizePath}")
          cacheFile.writeFile(result.output)
          retFile.writeFile($result.ret)
  else:
    # Used by toast
    (result.output, result.ret) = execCmdEx(ccmd)

  # On failure, retry or die as requested
  if result.ret != 0:
    if retry > 0:
      if not onRetry.isNil:
        onRetry()
      sleep(500)
      result = execAction(cmd, retry = retry - 1, die, cache, cacheKey)
    else:
      if not onError.isNil:
        onError(result.output, result.ret)

      doAssert not die, "Command failed: " & $result.ret & "\ncmd: " & ccmd &
                        "\nresult:\n" & result.output

when not defined(TOAST):
  proc findExe*(exe: string): string =
    ## Find the specified executable using the `which`/`where` command - supported
    ## at compile time
    var
      cmd =
        when defined(Windows):
          "where " & exe
        else:
          "which " & exe

      (output, ret) = execAction(cmd, die = false)

    if ret == 0:
      return output.splitLines()[0].strip().sanitizePath
else:
  export findExe

proc mkDir*(dir: string) =
  ## Create a directory at compile time
  ##
  ## The `os` module is not available at compile time so a few
  ## crucial helper functions are included with nimterop.
  if not dirExists(dir):
    let
      flag = when not defined(Windows): "-p" else: ""
    discard execAction(&"mkdir {flag} {dir.sanitizePath}", retry = 2)

proc cpFile*(source, dest: string, psymlink = false, move = false) =
  ## Copy a file from `source` to `dest` at compile time
  ##
  ## `psymlink = true` preserves symlinks instead of dereferencing on posix
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
          if psymlink:
            "cp -fa"
          else:
            "cp -f"

  discard execAction(&"{cmd} {source.sanitizePath} {dest.sanitizePath}", retry = 2)

proc mvFile*(source, dest: string) =
  ## Move a file from `source` to `dest` at compile time
  cpFile(source, dest, move=true)

proc rmFile*(source: string, dir = false) =
  ## Remove a file or pattern at compile time
  let
    source = source.replace("/", $DirSep)
    cmd =
      when defined(Windows):
        if dir:
          "rd /s/q"
        else:
          "del /q/f"
      else:
        "rm -rf"
    exists =
      if dir:
        dirExists(source)
      else:
        fileExists(source)

  if exists:
    discard execAction(&"{cmd} {source.sanitizePath}", retry = 2)

proc rmDir*(dir: string) =
  ## Remove a directory or pattern at compile time
  rmFile(dir, dir = true)

proc cleanDir*(dir: string) =
  ## Remove all contents of a directory at compile time
  for kind, path in walkDir(dir):
    if kind == pcDir:
      rmDir(path)
    else:
      rmFile(path)

proc cpTree*(source, dest: string, move = false) =
  ## Copy contents of source dir to the destination, not the directory itself
  for kind, path in walkDir(source, relative = true):
    if kind == pcDir:
      cpTree(source / path, dest / path, move)
      if move:
        rmDir(source / path)
    else:
      if not dirExists(dest):
        mkDir(dest)
      if move:
        mvFile(source / path, dest / path)
      else:
        cpFile(source / path, dest / path)

proc mvTree*(source, dest: string) =
  ## Move contents of source dir to the destination, not the directory itself
  cpTree(source, dest, move = true)

proc getFileDate*(fullpath: string): string =
  ## Get file date for `fullpath`
  var
    ret = 0
    cmd =
      when defined(Windows):
        let
          (head, tail) = fullpath.splitPath()
        &"cmd /c forfiles /P {head.sanitizePath()} /M {tail.sanitizePath} /C \"cmd /c echo @fdate @ftime @fsize\""
      elif defined(Linux):
        &"stat -c %y {fullpath.sanitizePath}"
      elif defined(OSX) or defined(FreeBSD):
        &"stat -f %m {fullpath.sanitizePath}"

  (result, ret) = execAction(cmd)

proc touchFile*(fullpath: string) =
  ## Touch file to update modified date
  var
    cmd =
      when defined(Windows):
        &"cmd /c copy /b {fullpath.sanitizePath}+"
      else:
        &"touch {fullpath.sanitizePath}"

  discard execAction(cmd)

proc extractZip*(zipfile, outdir: string, quiet = false) =
  ## Extract a zip file using `powershell` on Windows and `unzip` on other
  ## systems to the specified output directory
  var cmd = "unzip -o $#"
  if defined(Windows):
    cmd = "powershell -nologo -noprofile -command \"& { Add-Type -A " &
          "'System.IO.Compression.FileSystem'; " &
          "[IO.Compression.ZipFile]::ExtractToDirectory('$#', '.'); }\""

  if not quiet:
    gecho "# Extracting " & zipfile
  discard execAction(&"cd {outdir.sanitizePath} && {cmd % zipfile}")

proc extractTar*(tarfile, outdir: string, quiet = false) =
  ## Extract a tar file using `tar`, `7z` or `7za` to the specified output directory
  var
    cmd = ""
    name = ""

  if findExe("tar").len != 0:
    let
      ext = tarfile.splitFile().ext.toLowerAscii()
      typ =
        case ext
        of ".gz", ".tgz": "z"
        of ".xz": "J"
        of ".bz2": "j"
        else: ""

    cmd = "tar xvf" & typ & " " & tarfile.sanitizePath
  else:
    for i in ["7z", "7za"]:
      if findExe(i).len != 0:
        cmd = i & " x $#" % tarfile.sanitizePath

        name = tarfile.splitFile().name
        if ".tar" in name.toLowerAscii():
          cmd &= " && " & i & " x $#" % name.sanitizePath

        break

  doAssert cmd.len != 0, "No extraction tool - tar, 7z, 7za - available for " & tarfile.sanitizePath

  if not quiet:
    gecho "# Extracting " & tarfile
  discard execAction(&"cd {outdir.sanitizePath} && {cmd}")
  if name.len != 0:
    rmFile(outdir / name)

proc downloadUrl*(url, outdir: string, quiet = false, retry = 1) =
  ## Download a file using `curl` or `wget` (or `powershell` on Windows) to the specified directory
  ##
  ## If an archive file, it is automatically extracted after download.
  let
    file = url.extractFilename()
    filePath = outdir / file
    ext = file.splitFile().ext.toLowerAscii()
    archives = @[".zip", ".xz", ".gz", ".bz2", ".tgz", ".tar"]

  if not (ext in archives and fileExists(filePath)):
    if not quiet:
      gecho "# Downloading " & file
    mkDir(outdir)
    var cmd = findExe("curl")
    if cmd.len != 0:
      cmd &= " -Lk $# -o $#"
    else:
      cmd = findExe("wget")
      if cmd.len != 0:
        cmd &= " $# -O $#"
      elif defined(Windows):
        cmd = "powershell [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; wget $# -OutFile $#"
      else:
        doAssert false, "No download tool available - curl, wget"
    discard execAction(cmd % [url.quoteShell, (filePath).sanitizePath], retry = 3,
      onRetry = proc() = rmFile(filePath))

    if ext == ".zip":
      extractZip(file, outdir, quiet)
    elif ext in archives:
      extractTar(file, outdir, quiet)

proc gitReset*(outdir: string) =
  ## Hard reset the git repository at the specified directory
  gecho "# Resetting " & outdir

  let cmd = &"cd {outdir.sanitizePath} && git reset --hard"
  while execAction(cmd).output.contains("Permission denied"):
    sleep(1000)
    gecho "#   Retrying ..."

proc gitCheckout*(file, outdir: string) =
  ## Checkout the specified `file` in the git repository at `outdir`
  ##
  ## This effectively resets all changes in the file and can be
  ## used to undo any changes that were made to source files to enable
  ## successful wrapping with `cImport()` or `c2nImport()`.
  gecho "# Resetting " & file
  let file2 = file.relativePath outdir
  let cmd = &"cd {outdir.sanitizePath} && git checkout {file2.sanitizePath}"
  while execAction(cmd).output.contains("Permission denied"):
    sleep(500)
    gecho "#   Retrying ..."

proc gitAtCheckout*(outdir, checkout: string): bool =
  ## Check if specified git repository is checked out to the specified
  ## commit hash, tag or branch
  result = checkout in execAction(
    &"cd {outdir.sanitizePath} && git log --decorate --no-color -n 1 --format=oneline").output

proc gitDefaultBranch*(outdir: string): string =
  ## Get the default branch for a git repository before it is pulled
  result = "master"
  let
    output = execAction(
      &"cd {outdir.sanitizePath} && git remote show origin"
    ).output

  for line in output.splitLines():
    if "HEAD branch: " in line:
      result = line.split("branch: ")[1].strip()

proc gitPull*(url: string, outdir = "", plist = "", checkout = "", quiet = false) =
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
  let
    outdirQ = outdir.sanitizePath

  if dirExists(outdir/".git"):
    gitReset(outdir)
    if checkout.nBl and not gitAtCheckout(outdir, checkout):
      gecho &"# Updating repository to checkout {checkout}"
      discard execAction(
        &"cd {outdirQ} && git clean -fxd && git fetch && git checkout {checkout}", retry = 3)
    return

  mkDir(outdir)

  if not quiet:
    gecho "# Setting up Git repo: " & url
  discard execAction(&"cd {outdirQ} && git init .")
  discard execAction(&"cd {outdirQ} && git remote add origin {url}")

  if plist.len != 0:
    # If a specific list of files is required, create a sparse checkout
    # file for git in its config directory
    let sparsefile = outdir / ".git/info/sparse-checkout"

    discard execAction(&"cd {outdirQ} && git config core.sparsecheckout true")
    writeFile(sparsefile, plist)

  # In case directory has old files from another run
  discard execAction(&"cd {outdirQ} && git clean -fxd")

  # Checkout specified branch/tag/commit or default branch - typically master
  let
    checkout = if checkout.Bl: gitDefaultBranch(outdir) else: checkout

  if not quiet:
    gecho "# Checking out " & checkout
  discard execAction(&"cd {outdirQ} && git fetch", retry = 3)
  discard execAction(&"cd {outdirQ} && git checkout {checkout}")

proc gitTags*(outdir: string): seq[string] =
  ## Get all the git tags in the specified directory
  let
    cmd = &"cd {outdir.sanitizePath} && git tag"
    tags = execAction(cmd).output.splitLines()
  for tag in tags:
    let
      tag = tag.strip()
    if tag.len != 0:
      result.add tag

proc findFiles*(file: string, dir: string, recurse = true, regex = false): seq[string] =
  ## Find all matching files in the specified directory
  ##
  ## `file` is a regular expression if `regex` is true
  ##
  ## Turn off recursive search with `recurse`
  var
    cmd =
      when defined(Windows):
        "nimgrep --filenames --oneline --nocolor $1 \"$2\" $3"
      elif defined(linux):
        "find $3 $1 -regextype egrep -regex $2"
      elif defined(osx) or defined(FreeBSD):
        "find -E $3 $1 -regex $2"

    recursive = ""

  if recurse:
    when defined(Windows):
      recursive = "--recursive"
  else:
    when not defined(Windows):
      recursive = "-maxdepth 1"

  var
    dir = dir
    file = file
  # If file = `path/file`, adjust dir = `dir/path` and search for new file
  if not (recurse or regex):
    let
      pdir = file.parentDir()
    if pdir.len != 0:
      dir = dir / pdir

    file = file.extractFilename

  cmd = cmd % [recursive, (".*[\\\\/]" & file & "$").quoteShell, dir.sanitizePath]

  let
    (files, ret) = execAction(cmd, die = false)
  if ret == 0:
    for line in files.splitLines():
      let f =
        when defined(Windows):
          if ": " in line:
            line.split(": ", maxsplit = 1)[1]
          else:
            ""
        else:
          line
      if f.len != 0:
        result.add f

proc findFile*(file: string, dir: string, recurse = true, first = false, regex = false): string =
  ## Find the file in the specified directory
  ##
  ## `file` is a regular expression if `regex` is true
  ##
  ## Turn off recursive search with `recurse` and stop on first match with
  ## `first`. Without it, the shortest match is returned.
  let
    matches = findFiles(file, dir, recurse, regex)
  for match in matches:
    if (result.len == 0 or result.len > match.len):
      result = match
      if first: break

proc linkLibs*(names: openArray[string], staticLink = true): string =
  ## Create linker flags for specified libraries using pkg-config
  ##
  ## Prepends `lib` to the name so you only need `ssl` for `libssl`.
  var
    stat = if staticLink: "--static" else: ""
    resSet: OrderedSet[string]
  resSet.init()

  for name in names:
    let
      cmd = &"pkg-config --libs --silence-errors {stat} lib{name}"
      (libs, _) = execAction(cmd, die = false)
    for lib in libs.split(" "):
      resSet.incl lib

  if staticLink:
    resSet.incl "--static"

  for res in resSet:
    result &= " " & res

proc getNumProcs*(): string =
  ## Get number of processors
  when defined(Windows):
    getEnv("NUMBER_OF_PROCESSORS").strip()
  elif defined(linux):
    execAction("nproc").output.strip()
  elif defined(macosx) or defined(FreeBSD):
    execAction("sysctl -n hw.ncpu").output.strip()
  else:
    "1"

proc getProjectCacheDir*(name: string, forceClean = true): string =
  ## Get a cache directory where all nimterop artifacts can be stored
  ##
  ## Projects can use this location to download source code and build binaries
  ## that can be then accessed by multiple apps. This is created under the
  ## per-user Nim cache directory.
  ##
  ## Use `name` to specify the subdirectory name for a project.
  ##
  ## `forceClean` is enabled by default and effectively deletes the folder
  ## if Nim is compiled with the `-f` or `--forceBuild` flag. This allows
  ## any project to start out with a clean cache dir on a forced build.
  ##
  ## NOTE: avoid calling `getProjectCacheDir()` multiple times on the same
  ## `name` when `forceClean = true` else checked out source might get deleted
  ## at the wrong time during build.
  ##
  ## E.g.
  ##   `nimgit2` downloads `libgit2` source so `name = "libgit2"`
  ##
  ##   `nimarchive` downloads `libarchive`, `bzlib`, `liblzma` and `zlib` so
  ##   `name = "nimarchive" / "libarchive"` for `libarchive`, etc.
  result = getNimteropCacheDir() / name

  if forceClean and compileOption("forceBuild"):
    gecho "# Removing " & result
    rmDir(result)
