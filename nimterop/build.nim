import hashes, macros, osproc, sets, strformat, strutils, tables

import os except findExe, sleep

export extractFilename, `/`

type
  BuildType* = enum
    btAutoconf, btCmake

  BuildStatus = object
    built: bool
    buildPath: string
    error: string

# build specific debug since we cannot import globals (yet)
var
  gDebug* = false
  gDebugCT* {.compileTime.} = false
  gNimExe* = ""

proc echoDebug(str: string) =
  let str = "\n# " & str.strip().replace("\n", "\n# ")
  when nimvm:
    if gDebugCT: echo str
  else:
    if gDebug: echo str

proc fixCmd(cmd: string): string =
  when defined(Windows):
    # Replace 'cd d:\abc' with 'd: && cd d:\abc`
    var filteredCmd = cmd
    if cmd.toLower().startsWith("cd"):
      var
        colonIndex = cmd.find(":")
        driveLetter = cmd.substr(colonIndex-1, colonIndex)
      if (driveLetter[0].isAlphaAscii() and
          driveLetter[1] == ':' and
          colonIndex == 4):
        filteredCmd = &"{driveLetter} && {cmd}"
    result = "cmd /c " & filteredCmd
  elif defined(posix):
    result = cmd
  else:
    doAssert false

proc sanitizePath*(path: string, noQuote = false, sep = $DirSep): string =
  result = path.multiReplace([("\\\\", sep), ("\\", sep), ("/", sep)])
  if not noQuote:
    result = result.quoteShell

proc getCurrentNimCompiler*(): string =
  when nimvm:
    result = getCurrentCompilerExe()
    when defined(nimsuggest):
      result = result.replace("nimsuggest", "nim")
  else:
    result = gNimExe

# Nim cfg file related functionality
include "."/nimconf

proc sleep*(milsecs: int) =
  ## Sleep at compile time
  let
    cmd =
      when defined(Windows):
        "cmd /c timeout "
      else:
        "sleep "

  discard gorgeEx(cmd & $(milsecs / 1000))

proc getNimteropCacheDir(): string =
  # Get location to cache all nimterop artifacts
  result = getNimcacheDir() / "nimterop"

proc execAction*(cmd: string, retry = 0, die = true, cache = false,
                 cacheKey = ""): tuple[output: string, ret: int] =
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
      sleep(1000)
      result = execAction(cmd, retry = retry - 1, die, cache, cacheKey)
    elif die:
      doAssert false, "Command failed: " & $result.ret & "\ncmd: " & ccmd &
                      "\nresult:\n" & result.output

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
    return output.splitLines()[0].strip()

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
          "del /s/q/f"
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
    echo "# Removing " & result
    rmDir(result)

proc extractZip*(zipfile, outdir: string, quiet = false) =
  ## Extract a zip file using `powershell` on Windows and `unzip` on other
  ## systems to the specified output directory
  var cmd = "unzip -o $#"
  if defined(Windows):
    cmd = "powershell -nologo -noprofile -command \"& { Add-Type -A " &
          "'System.IO.Compression.FileSystem'; " &
          "[IO.Compression.ZipFile]::ExtractToDirectory('$#', '.'); }\""

  if not quiet:
    echo "# Extracting " & zipfile
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
    echo "# Extracting " & tarfile
  discard execAction(&"cd {outdir.sanitizePath} && {cmd}")
  if name.len != 0:
    rmFile(outdir / name)

proc downloadUrl*(url, outdir: string, quiet = false) =
  ## Download a file using `curl` or `wget` (or `powershell` on Windows) to the specified directory
  ##
  ## If an archive file, it is automatically extracted after download.
  let
    file = url.extractFilename()
    ext = file.splitFile().ext.toLowerAscii()
    archives = @[".zip", ".xz", ".gz", ".bz2", ".tgz", ".tar"]

  if not (ext in archives and fileExists(outdir/file)):
    if not quiet:
      echo "# Downloading " & file
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
    discard execAction(cmd % [url.quoteShell, (outdir/file).sanitizePath], retry = 3)

    if ext == ".zip":
      extractZip(file, outdir, quiet)
    elif ext in archives:
      extractTar(file, outdir, quiet)

proc gitReset*(outdir: string) =
  ## Hard reset the git repository at the specified directory
  echo "# Resetting " & outdir

  let cmd = &"cd {outdir.sanitizePath} && git reset --hard"
  while execAction(cmd).output.contains("Permission denied"):
    sleep(1000)
    echo "#   Retrying ..."

proc gitCheckout*(file, outdir: string) =
  ## Checkout the specified `file` in the git repository at `outdir`
  ##
  ## This effectively resets all changes in the file and can be
  ## used to undo any changes that were made to source files to enable
  ## successful wrapping with `cImport()` or `c2nImport()`.
  echo "# Resetting " & file
  let file2 = file.relativePath outdir
  let cmd = &"cd {outdir.sanitizePath} && git checkout {file2.sanitizePath}"
  while execAction(cmd).output.contains("Permission denied"):
    sleep(500)
    echo "#   Retrying ..."

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
  if dirExists(outdir/".git"):
    gitReset(outdir)
    return

  let
    outdirQ = outdir.sanitizePath

  mkDir(outdir)

  if not quiet:
    echo "# Setting up Git repo: " & url
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

  if checkout.len != 0:
    if not quiet:
      echo "# Checking out " & checkout
    discard execAction(&"cd {outdirQ} && git fetch", retry = 3)
    discard execAction(&"cd {outdirQ} && git checkout {checkout}")
  else:
    if not quiet:
      echo "# Pulling repository"
    discard execAction(&"cd {outdirQ} && git pull --depth=1 origin master", retry = 3)

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
  if not recurse:
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

proc flagBuild*(base: string, flags: openArray[string]): string =
  ## Simple helper proc to generate flags for `configure`, `cmake`, etc.
  ##
  ## Every entry in `flags` is replaced into the `base` string and
  ## concatenated to the result.
  ##
  ## E.g.
  ##   `base = "--disable-$#"`
  ##   `flags = @["one", "two"]`
  ##
  ## `flagBuild(base, flags) => " --disable-one --disable-two"`
  for i in flags:
    result &= " " & base % i

proc linkLibs*(names: openArray[string], staticLink = true): string =
  ## Create linker flags for specified libraries
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

proc configure*(path, check: string, flags = "") =
  ## Run the GNU `configure` command to generate all Makefiles or other
  ## build scripts in the specified path
  ##
  ## If a `configure` script is not present and an `autogen.sh` script
  ## is present, it will be run before attempting `configure`.
  ##
  ## Next, if `configure.ac` or `configure.in` exist, `autoreconf` will
  ## be executed.
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
    for i in @["autogen.sh", "build" / "autogen.sh"]:
      if fileExists(path / i):
        echo "#   Running autogen.sh"

        when defined(unix):
          echoDebug execAction(
            &"cd {(path / i).parentDir().sanitizePath} && ./autogen.sh").output
        else:
          echoDebug execAction(
            &"cd {(path / i).parentDir().sanitizePath} && bash ./autogen.sh").output

        break

  if not fileExists(path / "configure"):
    for i in @["configure.ac", "configure.in"]:
      if fileExists(path / i):
        echo "#   Running autoreconf"

        echoDebug execAction(&"cd {path.sanitizePath} && autoreconf -fi").output

        break

  if fileExists(path / "configure"):
    echo "#   Running configure " & flags

    when defined(unix):
      var
        cmd = &"cd {path.sanitizePath} && ./configure"
    else:
      var
        cmd = &"cd {path.sanitizePath} && bash ./configure"
    if flags.len != 0:
      cmd &= &" {flags}"

    echoDebug execAction(cmd).output

  doAssert (path / check).fileExists(), "Configure failed"

proc getCmakePropertyStr(name, property, value: string): string =
  &"\nset_target_properties({name} PROPERTIES {property} \"{value}\")\n"

proc getCmakeIncludePath*(paths: openArray[string]): string =
  ## Create a `cmake` flag to specify custom include paths
  ##
  ## Result can be included in the `flag` parameter for `cmake()` or
  ## the `cmakeFlags` parameter for `getHeader()`.
  for path in paths:
    result &= path & ";"
  result = " -DCMAKE_INCLUDE_PATH=" & result[0 .. ^2].sanitizePath(sep = "/")

proc setCmakeProperty*(outdir, name, property, value: string) =
  ## Set a `cmake` property in `outdir / CMakeLists.txt` - usable in the `xxxPreBuild` hook
  ## for `getHeader()`
  ##
  ## `set_target_properties(name PROPERTIES property "value")`
  let
    cm = outdir / "CMakeLists.txt"
  if cm.fileExists():
    cm.writeFile(
      cm.readFile() & getCmakePropertyStr(name, property, value)
    )

proc setCmakeLibName*(outdir, name, prefix = "", oname = "", suffix = "") =
  ## Set a `cmake` property in `outdir / CMakeLists.txt` to specify a custom library output
  ## name - usable in the `xxxPreBuild` hook for `getHeader()`
  ##
  ## `prefix` is typically `lib`
  ## `oname` is the library name
  ## `suffix` is typically `.a`
  ##
  ## Sometimes, `cmake` generates non-standard library names - e.g. zlib compiles to
  ## `libzlibstatic.a` on Windows. This proc can help rename it to `libzlib.a` so that `getHeader()`
  ## can find it after the library is compiled.
  ##
  ## ```
  ## set_target_properties(name PROPERTIES PREFIX "prefix")
  ## set_target_properties(name PROPERTIES OUTPUT_NAME "oname")
  ## set_target_properties(name PROPERTIES SUFFIX "suffix")
  ## ```
  let
    cm = outdir / "CMakeLists.txt"
  if cm.fileExists():
    var
      str = ""
    if prefix.len != 0:
      str &= getCmakePropertyStr(name, "PREFIX", prefix)
    if oname.len != 0:
      str &= getCmakePropertyStr(name, "OUTPUT_NAME", oname)
    if suffix.len != 0:
      str &= getCmakePropertyStr(name, "SUFFIX", suffix)
    if str.len != 0:
      cm.writeFile(cm.readFile() & str)

proc setCmakePositionIndependentCode*(outdir: string) =
  ## Set a `cmake` directive to create libraries with -fPIC enabled
  let
    cm = outdir / "CMakeLists.txt"
  if cm.fileExists():
    let
      pic = "set(CMAKE_POSITION_INDEPENDENT_CODE ON)"
      cmd = cm.readFile()
    if not cmd.contains(pic):
      cm.writeFile(
        pic & "\n" & cmd
      )

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

  let
    cmd = &"cd {path.sanitizePath} && cmake {flags}"

  echoDebug execAction(cmd).output

  doAssert (path / check).fileExists(), "cmake failed"

proc make*(path, check: string, flags = "", regex = false) =
  ## Run the `make` command to build all binaries in the specified path
  ##
  ## `check` is a file that will be generated by the `make` command.
  ## This is required to prevent `make` from running on every build. It
  ## is relative to the `path` and should not be an absolute path.
  ##
  ## `flags` are any flags that should be passed to the `make` command.
  ##
  ## `regex` can be set to true if `check` is a regular expression.
  ##
  ## If `make.exe` is missing and `mingw32-make.exe` is available, it will
  ## be copied over to make.exe in the same location.
  if findFile(check, path, regex = regex).len != 0:
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

  cmd = &"cd {path.sanitizePath} && make"
  if flags.len != 0:
    cmd &= &" {flags}"

  echoDebug execAction(cmd).output

  doAssert findFile(check, path, regex = regex).len != 0, "make failed"

proc getCompilerMode*(path: string): string =
  ## Determines a target language mode from an input filename, if one is not already specified.
  let file = path.splitFile()
  if file.ext in [".hxx", ".hpp", ".hh", ".H", ".h++", ".cpp", ".cxx", ".cc", ".C", ".c++"]:
    result = "cpp"
  elif file.ext in [".h", ".c"]:
    result = "c"

proc getGccModeArg*(mode: string): string =
  ## Produces a GCC argument that explicitly sets the language mode to be used by the compiler.
  if mode == "cpp":
    result = "-xc++"
  elif mode == "c":
    result = "-xc"

proc getCompiler*(): string =
  var
    compiler =
      when defined(gcc):
        "gcc"
      elif defined(clang):
        "clang"
      else:
        doAssert false, "Nimterop only supports gcc and clang at this time"

  result = getEnv("CC", compiler)

proc getGccPaths*(mode: string): seq[string] =
  var
    nul = when defined(Windows): "nul" else: "/dev/null"
    inc = false

    (outp, _) = execAction(&"""{getCompiler()} -Wp,-v {getGccModeArg(mode)} {nul}""", die = false)

  for line in outp.splitLines():
    if "#include <...> search starts here" in line:
      inc = true
      continue
    elif "End of search list" in line:
      break
    if inc:
      var
        path = line.strip().normalizedPath()
      if path notin result:
        result.add path

  when defined(osx):
    result.add(execAction("xcrun --show-sdk-path").output.strip() & "/usr/include")

proc getGccLibPaths*(mode: string): seq[string] =
  var
    nul = when defined(Windows): "nul" else: "/dev/null"
    linker = when defined(OSX): "-Xlinker" else: ""

    (outp, _) = execAction(&"""{getCompiler()} {linker} -v {getGccModeArg(mode)} {nul}""", die = false)

  for line in outp.splitLines():
    if "LIBRARY_PATH=" in line:
      for path in line[13 .. ^1].split(PathSep):
        var
          path = path.strip().normalizedPath()
        if path notin result:
          result.add path
      break
    elif '\t' in line:
      var
        path = line.strip().normalizedPath()
      if path notin result:
        result.add path

  when defined(osx):
    result.add "/usr/lib"

proc getGccInfo*(): tuple[arch, os, compiler, version: string] =
  let
    (outp, _) = execAction(&"{getCompiler()} -v")
  for line in outp.splitLines():
    if line.startsWith("Target: "):
      result.arch = line.split(' ')[1].split('-')[0]
      result.os =
        if "linux" in line:
          "linux"
        elif "android" in line:
          "android"
        elif "darwin" in line:
          "macos"
        elif "w64" in line or "mingw" in line:
          "windows"
        else:
          "unknown"
    elif " version " in line:
      result.version = line.split(" version ")[1].split(' ')[0]
  if "clang" in outp:
    if result.os == "macos":
      result.compiler = "apple-clang"
    else:
      result.compiler = "clang"
  else:
    result.compiler = "gcc"

template fixOutDir() {.dirty.} =
  let
    outdir = if outdir.isAbsolute(): outdir else: getProjectDir() / outdir

proc compareVersions*(ver1, ver2: string): int =
  ## Compare two version strings x.y.z and return -1, 0, 1
  ##
  ## ver1 < ver2 = -1
  ## ver1 = ver2 = 0
  ## ver1 > ver2 = 1
  let
    ver1seq = ver1.replace("-", "").split('.')
    ver2seq = ver2.replace("-", "").split('.')
  for i in 0 ..< ver1seq.len:
    let
      p1 = ver1seq[i]
      p2 = if i < ver2seq.len: ver2seq[i] else: "0"

    try:
      let
        h1 = p1.parseHexInt()
        h2 = p2.parseHexInt()

      if h1 < h2: return -1
      elif h1 > h2: return 1
    except ValueError:
      if p1 < p2: return -1
      elif p1 > p2: return 1

# Conan support
include conan

# Julia Binary Builder support
include jbb

proc getStdPath(header, mode: string): string =
  for inc in getGccPaths(mode):
    result = findFile(header, inc, recurse = false, first = true)
    if result.len != 0:
      break

proc getStdLibPath(lname, mode: string): string =
  for lib in getGccLibPaths(mode):
    result = findFile(lname, lib, recurse = false, first = true, regex = true)
    if result.len != 0:
      break

proc getGitPath(header, url, outdir, version: string): string =
  doAssert url.len != 0, "No git url setup for " & header
  doAssert findExe("git").len != 0, "git executable missing"

  gitPull(url, outdir, checkout = version)

  result = findFile(header, outdir)

proc getDlPath(header, url, outdir, version: string): string =
  doAssert url.len != 0, "No download url setup for " & header

  var
    dlurl = url
  if "$#" in url or "$1" in url:
    doAssert version.len != 0, "Need version for download url"
    dlurl = url % version
  else:
    doAssert version.len == 0, "Download url does not contain version"

  downloadUrl(dlurl, outdir)

  var
    dirname = ""
  for kind, path in walkDir(outdir, relative = true):
    if kind == pcFile and path != dlurl.extractFilename():
        dirname = ""
        break
    elif kind == pcDir:
      if dirname.len == 0:
        dirname = path
      else:
        dirname = ""
        break

  if dirname.len != 0:
    for kind, path in walkDir(outdir / dirname, relative = true):
      mvFile(outdir / dirname / path, outdir / path)

  result = findFile(header, outdir)

proc getConanPath(header, uri, outdir, version: string, shared: bool): string =
  var
    uri = uri

  if "$#" in uri or "$1" in uri:
    doAssert version.len != 0, "Need version for Conan.io uri: " & uri
    uri = uri % version
  elif version.len != 0:
    uri = uri & "/" & version

  let
    pkg = newConanPackageFromUri(uri, shared)
  downloadConan(pkg, outdir)

  result = findFile(header, outdir)

proc getConanLDeps(outdir: string): seq[string] =
  let
    pkg = loadConanInfo(outdir)

  result = pkg.getConanLDeps(outdir)

proc getJBBPath(header, uri, outdir, version: string): string =
  let
    spl = uri.split('/', 1)
    name = spl[0]
    hasVersion = version.len != 0

  var
    ver =
      if spl.len == 2:
        spl[1]
      else:
        ""

  if ver.len != 0:
    if "$#" in ver or "$1" in ver:
      doAssert hasVersion, "Need version for BinaryBuilder.org uri: " & uri
      ver = ver % version
    elif hasVersion:
      doAssert false, "Version in both uri `" & uri & "` and `-d:xxxSetVer=\"" &
        version & "\"` for BinaryBuilder.org"
  elif hasVersion:
    ver = version

  let
    pkg = newJBBPackage(name, ver)
  downloadJBB(pkg, outdir)

  result = findFile(header, outdir)

proc getJBBLDeps(outdir: string, shared: bool): seq[string] =
  let
    pkg = loadJBBInfo(outdir)

  result = pkg.getJBBLDeps(outdir, shared)

proc getLocalPath(header, outdir: string): string =
  if outdir.len != 0:
    result = findFile(header, outdir)

proc getNumProcs(): string =
  when defined(Windows):
    getEnv("NUMBER_OF_PROCESSORS").strip()
  elif defined(linux):
    execAction("nproc").output.strip()
  elif defined(macosx) or defined(FreeBSD):
    execAction("sysctl -n hw.ncpu").output.strip()
  else:
    "1"

proc buildWithCmake(outdir, flags: string): BuildStatus =
  if not fileExists(outdir / "Makefile"):
    if fileExists(outdir / "CMakeLists.txt"):
      if findExe("cmake").len != 0:
        var
          gen = ""
        when defined(Windows):
          if findExe("sh").len != 0:
            let
              uname = execAction("sh -c uname -a").output.toLowerAscii()
            if uname.contains("msys"):
              gen = "MSYS Makefiles".quoteShell
            elif uname.contains("mingw"):
              gen = "MinGW Makefiles".quoteShell & " -DCMAKE_SH=\"CMAKE_SH-NOTFOUND\""
            else:
              echo "Unsupported system: " & uname
          else:
            gen = "MinGW Makefiles".quoteShell
        else:
          gen = "Unix Makefiles".quoteShell
        if findExe("ccache").len != 0:
          gen &= " -DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache"
        result.buildPath = outdir / "buildcache"
        cmake(result.buildPath, "Makefile", &".. -G {gen} {flags}")
        result.built = true
      else:
        result.error = "cmake capable but cmake executable missing"
  else:
    result.buildPath = outdir

proc buildWithAutoConf(outdir, flags: string): BuildStatus =
  if not fileExists(outdir / "Makefile"):
    if findExe("bash").len != 0:
      for file in @["configure", "configure.ac", "configure.in", "autogen.sh", "build/autogen.sh"]:
        if fileExists(outdir / file):
          configure(outdir, "Makefile", flags)
          result.buildPath = outdir
          result.built = true
          break
    else:
      result.error = "configure capable but bash executable missing"
  else:
    result.buildPath = outdir

proc buildLibrary(lname, outdir, conFlags, cmakeFlags, makeFlags: string, buildTypes: openArray[BuildType]): string =
  var
    lpath = findFile(lname, outdir, regex = true)
    makeFlagsProc = &"-j {getNumProcs()} {makeFlags}"
    makePath = outdir

  if lpath.len != 0:
    return lpath

  var buildStatus: BuildStatus

  for buildType in buildTypes:
    case buildType
    of btCmake:
      buildStatus = buildWithCmake(makePath, cmakeFlags)
    of btAutoconf:
      buildStatus = buildWithAutoConf(makePath, conFlags)

    if buildStatus.built:
      break

  if buildStatus.buildPath.len > 0:
    let libraryExists = findFile(lname, buildStatus.buildPath, regex = true).len > 0

    if not libraryExists and fileExists(buildStatus.buildPath / "Makefile"):
      make(buildStatus.buildPath, lname, makeFlagsProc, regex = true)
      buildStatus.built = true

  let error = if buildStatus.error.len > 0: buildStatus.error else: "No build files found in " & outdir
  doAssert buildStatus.built, &"\nBuild configuration failed - {error}\n"

  result = findFile(lname, outdir, regex = true)

proc getDynlibExt(): string =
  when defined(Windows):
    result = "[0-9.\\-]*\\.dll"
  elif defined(linux) or defined(FreeBSD):
    result = "\\.so[0-9.]*"
  elif defined(macosx):
    result = "[0-9.\\-]*\\.dylib"

var
  gDefines {.compileTime.} = initTable[string, string]()

macro setDefines*(defs: static openArray[string]): untyped =
  ## Specify `-d:xxx` values in code instead of having to rely on the command
  ## line or `cfg` or `nims` files.
  ##
  ## At this time, Nim does not allow creation of `-d:xxx` defines in code. In
  ## addition, Nim only loads config files for the module being compiled but not
  ## for imported packages. This becomes a challenge when wanting to ship a wrapper
  ## library that wants to control `getHeader()` for an underlying package.
  ##
  ##   E.g. nimarchive wanting to set `-d:lzmaStatic`
  ##
  ## The consumer of nimarchive would need to set such defines as part of their
  ## project, making it inconvenient.
  ##
  ## By calling this proc with the defines preferred before importing such a module,
  ## the caller can set the behavior in code instead.
  ##
  ## .. code-block:: nim
  ##
  ##    setDefines(@["lzmaStatic", "lzmaDL", "lzmaSetVer=5.2.4"])
  ##
  ##    import lzma
  for def in defs:
    let
      nv = def.strip().split("=", maxsplit = 1)
    if nv.len != 0:
      let
        n = nv[0]
        v =
          if nv.len == 2:
            nv[1]
          else:
            ""
      gDefines[n] = v

macro clearDefines*(): untyped =
  ## Clear all defines set using `setDefines()`.
  gDefines.clear()

macro isDefined*(def: untyped): untyped =
  ## Check if `-d:xxx` is set globally or via `setDefines()`
  let
    sdef = gDefines.hasKey(def.strVal())
  result = newNimNode(nnkStmtList)
  result.add(quote do:
    when defined(`def`) or `sdef` != 0:
      true
    else:
      false
  )

macro getHeader*(
  header: static[string], giturl: static[string] = "", dlurl: static[string] = "",
  conanuri: static[string] = "", jbburi: static[string] = "",
  outdir: static[string] = "", libdir: static[string] = "",
  conFlags: static[string] = "", cmakeFlags: static[string] = "", makeFlags: static[string] = "",
  altNames: static[string] = "", buildTypes: static[openArray[BuildType]] = [btCmake, btAutoconf]): untyped =
  ## Get the path to a header file for wrapping with
  ## `cImport() <cimport.html#cImport.m%2C%2Cstring%2Cstring%2Cstring>`_ or
  ## `c2nImport() <cimport.html#c2nImport.m%2C%2Cstring%2Cstring%2Cstring>`_.
  ##
  ## This proc checks `-d:xxx` defines based on the header name (e.g. lzma from lzma.h),
  ## and accordingly employs different ways to obtain the source.
  ##
  ## `-d:xxxStd` - search standard system paths. E.g. `/usr/include` and `/usr/lib` on Linux
  ## `-d:xxxGit` - clone source from a git repo specified in `giturl`
  ## `-d:xxxDL` - download source from `dlurl` and extract if required
  ## `-d:xxxConan` - download headers and binary from Conan.io using `conanuri` with
  ##   format `pkgname[/version[@user/channel][:bhash]]`
  ## `-d:xxxJBB` - download headers and binary from BinaryBuilder.org using `jbburi` with
  ##   format `pkgname[/version]`
  ##
  ## This allows a single wrapper to be used in different ways depending on the user's needs.
  ## If no `-d:xxx` defines are specified, `outdir` will be searched for the header as is.
  ## The user can opt to download the sources to `outdir` using any other method such as
  ## git sub-modules, vendoring or pointing to a repository that was already cloned.
  ##
  ## If multiple `-d:xxx` defines are specified, precedence is `Std` and then `Git`, `DL`,
  ## `Conan` or `JBB`. This allows using a system installed library if available before
  ## falling back to manual building. The user would need to specify both `-d:xxxStd` and
  ## one of the other methods.
  ##
  ## `-d:xxxSetVer=x.y.z` can be used to specify which version to use. It is used as a tag
  ## name for `Git` whereas for `DL`, `Conan` and `JBB`, it replaces `$1` in the URL
  ## if specified. Specifying `-d:xxxSetVer` without a `$1` will download that version for
  ## `Conan` and `JBB` if available. If no version is specified, the latest release of the
  ## package is downloaded. For `Conan`, `-d:xxxSetVer` can also be used to set additional
  ## URI information:
  ##   `-d:xxxSetVer=1.9.0@bincrafters/stable:bhash`
  ##
  ## If `conanuri` or `jbburi` are not defined and `Conan` or `JBB` is selected, the `header`
  ## filename is used instead.
  ##
  ## All defines can also be set in code using `setDefines()` and checked for using
  ## `isDefined()` which checks for defines set from both `-d` and `setDefines()`.
  ##
  ## The library is then configured (with `cmake` or `autotools` if possible) and built
  ## using `make`, unless using `-d:xxxStd` which presumes that the system package
  ## manager was used to install prebuilt headers and binaries, or using `-d:xxxConan`
  ## or `-d:xxxJBB` which download pre-built binaries.
  ##
  ## The header path is stored in `const xxxPath` and can be used in a `cImport()` call
  ## in the calling wrapper. The dynamic library path is stored in `const xxxLPath` and can
  ## be used for the `dynlib` parameter (within quotes) or with `{.passL.}`. Any dependency
  ## libraries downloaded by `Conan` or `JBB` are returned in `const xxxLDeps` as a seq[string].
  ##
  ## `libdir` can be used to instruct `getHeader()` to copy shared libraries and their
  ## dependencies to that directory. This prevents any runtime failures if `outdir` gets
  ## removed or its contents changed. By default, `libdir` is set to the output directory
  ## where the program binary will be created. The values of `xxxLPath` and `xxxLDeps` will
  ## reflect this new location. `libdir` is ignored for `Std` mode.
  ##
  ## `-d:xxxStatic` can be specified to statically link with the library instead. This
  ## will automatically add a `{.passL.}` call to the static library for convenience. Note
  ## that `-d:xxxConan` and `-d:xxxJBB` download all dependency libs as well and the
  ## `xxxLPath` will include paths to all of them separated by space in the right order for
  ## linking.
  ##
  ## Note also that Conan currently builds all OSX binaries on 10.14 so older versions of
  ## OSX will complain if statically linking to these binaries. Further, all Conan binaries
  ## for Windows are built with Visual Studio so static linking the `.lib` files with gcc
  ## or clang might lead to incompatibility issues if the library uses Visual Studio
  ## specific compiler features.
  ##
  ## `conFlags`, `cmakeFlags` and `makeFlags` allow sending custom parameters to `configure`,
  ## `cmake` and `make` in case additional configuration is required as part of the build
  ## process.
  ##
  ## `altNames` is a list of alternate names for the library - e.g. zlib uses `zlib.h` for
  ## the header but the typical lib name is `libz.so` and not `libzlib.so`. However, it is
  ## libzlib.dll on Windows if built with cmake. In this case, `altNames = "z,zlib"`. Comma
  ## separate for multiple alternate names without spaces.
  ##
  ## The original header name is not included by default if `altNames` is set since it could
  ## cause the wrong lib to be selected. E.g. `SDL2/SDL.h` could pick `libSDL.so` even if
  ## `altNames = "SDL2"`. Explicitly include it in `altNames` like the `zlib` example when
  ## required.
  ##
  ## `buildTypes` specifies a list of ordered build strategies to use when building the
  ## downloaded source files. Default is [btCmake, btAutoconf]
  ##
  ## `xxxPreBuild` is a hook that is called after the source code is pulled from Git or
  ## downloaded but before the library is built. This might be needed if some initial prep
  ## needs to be done before compilation. A few values are provided to the hook to help
  ## provide context:
  ##
  ##   `outdir` is the same `outdir` passed in and `header` is the discovered header path
  ##   in the downloaded source code.
  ##
  ## Simply define `proc xxxPreBuild(outdir, header: string)` in the wrapper and it will get
  ## called prior to the build process.
  var
    origname = header.extractFilename().split(".")[0]
    name = origname.split(seps = AllChars-Letters-Digits).join()

    # Default to origname if not specified
    conanuri = if conanuri.len != 0: conanuri else: origname
    jbburi = if jbburi.len != 0: jbburi else: origname

    # -d:xxx for this header
    stdStr = name & "Std"
    gitStr = name & "Git"
    dlStr = name & "DL"
    conanStr = name & "Conan"
    jbbStr = name & "JBB"

    staticStr = name & "Static"
    verStr = name & "SetVer"

    # Ident nodes of the -d:xxx to check in when statements
    nameStd = newIdentNode(stdStr)
    nameGit = newIdentNode(gitStr)
    nameDL = newIdentNode(dlStr)
    nameConan = newIdentNode(conanStr)
    nameJBB = newIdentNode(jbbStr)

    nameStatic = newIdentNode(staticStr)

    # Consts to generate
    path = newIdentNode(name & "Path")
    lpath = newIdentNode(name & "LPath")
    ldeps = newIdentNode(name & "LDeps")
    version = newIdentNode(verStr)
    lname = newIdentNode(name & "LName")
    preBuild = newIdentNode(name & "PreBuild")

    # Regex for library search
    lre = "(lib)?$1[_-]?(static)?"

    # If -d:xxx set with setDefines()
    stdVal = gDefines.hasKey(stdStr)
    gitVal = gDefines.hasKey(gitStr)
    dlVal = gDefines.hasKey(dlStr)
    conanVal = gDefines.hasKey(conanStr)
    jbbVal = gDefines.hasKey(jbbStr)
    staticVal = gDefines.hasKey(staticStr)
    verVal =
      if gDefines.hasKey(verStr):
        gDefines[verStr]
      else:
        ""
    mode = getCompilerMode(header)

    libdir = if libdir.len != 0: libdir else: getOutDir()

  # Use alternate library names if specified for regex search
  if altNames.len != 0:
    lre = lre % ("(" & altNames.replace(",", "|") & ")")
  else:
    lre = lre % origname

  result = newNimNode(nnkStmtList)
  result.add(quote do:
    # Need to check -d:xxx or setDefines()
    const
      `nameStd`* = when defined(`nameStd`): true else: `stdVal` == 1
      `nameGit`* = when defined(`nameGit`): true else: `gitVal` == 1
      `nameDL`* = when defined(`nameDL`): true else: `dlVal` == 1
      `nameConan`* = when defined(`nameConan`): true else: `conanVal` == 1
      `nameJBB`* = when defined(`nameJBB`): true else: `jbbVal` == 1
      `nameStatic`* = when defined(`nameStatic`): true else: `staticVal` == 1

    # Search for header in outdir (after retrieving code) depending on -d:xxx mode
    proc getPath(header, giturl, dlurl, conanuri, jbburi, outdir, version: string, shared: bool): string =
      when `nameGit`:
        getGitPath(header, giturl, outdir, version)
      elif `nameDL`:
        getDlPath(header, dlurl, outdir, version)
      elif `nameConan`:
        getConanPath(header, conanuri, outdir, version, shared)
      elif `nameJBB`:
        getJBBPath(header, jbburi, outdir, version)
      else:
        getLocalPath(header, outdir)

    const
      `version`* {.strdefine.} = `verVal`
      `lname` =
        when `nameStatic`:
          `lre` & "\\.(a|lib)"
        else:
          `lre` & getDynlibExt()

      # Look in standard path if requested by user
      stdPath =
        when `nameStd`: getStdPath(`header`, `mode`) else: ""
      stdLPath =
        when `nameStd`: getStdLibPath(`lname`, `mode`) else: ""

      useStd = stdPath.len != 0 and stdLPath.len != 0

      # Look elsewhere if requested while prioritizing standard paths
      prePath =
        when useStd:
          stdPath
        else:
          getPath(`header`, `giturl`, `dlurl`, `conanuri`, `jbburi`, `outdir`, `version`, not `nameStatic`)

    # Run preBuild hook before building library if not Std, Conan or JBB
    when not (useStd or `nameConan` or `nameJBB`) and declared(`preBuild`):
      static:
        `preBuild`(`outdir`, prePath)

    let
      # Library binary path - build if not standard / conan / jbb
      lpath {.compileTime.} =
        when useStd:
          stdLPath
        elif `nameConan` or `nameJBB`:
          findFile(`lname`, `outdir`, regex = true)
        else:
          buildLibrary(`lname`, `outdir`, `conFlags`, `cmakeFlags`, `makeFlags`, `buildTypes`)

      # Library dependecy paths
      ldeps {.compileTime.}: seq[string] =
        when not useStd:
          when `nameConan`:
            getConanLDeps(`outdir`)
          elif `nameJBB`:
            getJBBLDeps(`outdir`, not `nameStatic`)
          else:
            @[]
        else:
          @[]

    const
      # Header path - search again in case header is generated in build
      `path`* =
        if prePath.len != 0:
          prePath
        else:
          getPath(`header`, `giturl`, `dlurl`, `conanuri`, `jbburi`, `outdir`, `version`, not `nameStatic`)

    static:
      doAssert `path`.len != 0, "\nHeader " & `header` & " not found - " &
        "missing/empty outdir or -d:$1Std -d:$1Git -d:$1DL -d:$1Conan or -d:$1JBB not specified" % `name`
      doAssert lpath.len != 0, "\nLibrary " & `lname` & " not found"

    when `nameStatic`:
      const
        `lpath`* = lpath
        `ldeps`* = ldeps

      # Automatically link with static library and dependencies
      {.passL: `lpath`.}
      if `ldeps`.len != 0:
        {.passL: `ldeps`.join(" ").}

      static:
        echo "# Including library " & lpath
        if `ldeps`.len != 0:
          echo "# Including dependencies " & `ldeps`.join(" ")
    else:
      const
        `lpath`* = when not useStd: `libdir` / lpath.extractFilename() else: lpath
        `ldeps`* =
          when not useStd:
            block:
              var
                ldeps = ldeps
                copied: seq[string]
              for i in 0 ..< ldeps.len:
                let
                  lname = ldeps[i].extractFilename()
                  ldeptgt = `libdir` / lname
                if not fileExists(ldeptgt) or getFileDate(ldeps[i]) != getFileDate(ldeptgt):
                  cpFile(ldeps[i], ldeptgt, psymlink = true)
                  copied.add lname
                ldeps[i] = ldeptgt
              # Copy downloaded dependencies to `libdir`
              if copied.len != 0:
                echo "# Copying dependencies: " & copied.join(" ") & "\n#   to " & `libdir`
              ldeps
          else:
            ldeps

      static:
          when not useStd:
            # Copy downloaded shared libraries to `libdir`
            if not fileExists(`lpath`) or getFileDate(lpath) != getFileDate(`lpath`):
              echo "# Copying " & `lpath`.extractFilename() & " to " & `libdir`
              cpFile(lpath, `lpath`)

          echo "# Including library " & `lpath`
  )
