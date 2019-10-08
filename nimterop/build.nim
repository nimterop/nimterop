import macros, osproc, strformat, strutils, tables

import os except findExe, sleep

import "."/[compat]

proc sanitizePath*(path: string, noQuote = false, sep = $DirSep): string =
  result = path.multiReplace([("\\\\", sep), ("\\", sep), ("/", sep)])
  if not noQuote:
    result = result.quoteShell

proc sleep*(milsecs: int) =
  ## Sleep at compile time
  let
    cmd =
      when defined(windows):
        "cmd /c timeout "
      else:
        "sleep "

    (oup, ret) = gorgeEx(cmd & $(milsecs / 1000))

proc execAction*(cmd: string, retry = 0, nostderr = false): string =
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
  if ret != 0:
    if retry > 0:
      sleep(500)
      result = execAction(cmd, retry = retry - 1)
    else:
      doAssert true, "Command failed: " & $(ret, nostderr) & "\ncmd: " & ccmd & "\nresult:\n" & result

proc findExe*(exe: string): string =
  ## Find the specified executable using the `which`/`where` command - supported
  ## at compile time
  var
    cmd =
      when defined(windows):
        "where " & exe
      else:
        "which " & exe

    (oup, code) = gorgeEx(cmd)

  if code == 0:
    return oup.splitLines()[0].strip()

proc mkDir*(dir: string) =
  ## Create a directory at compile time
  ##
  ## The `os` module is not available at compile time so a few
  ## crucial helper functions are included with nimterop.
  if not dirExists(dir):
    let
      flag = when not defined(Windows): "-p" else: ""
    discard execAction(&"mkdir {flag} {dir.sanitizePath}", retry = 2)

proc cpFile*(source, dest: string, move=false) =
  ## Copy a file from `source` to `dest` at compile time
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

  discard execAction(&"{cmd} {source.sanitizePath}", retry = 2)

proc rmDir*(source: string) =
  ## Remove a directory or pattern at compile time
  rmFile(source, dir = true)

proc extractZip*(zipfile, outdir: string) =
  ## Extract a zip file using `powershell` on Windows and `unzip` on other
  ## systems to the specified output directory
  var cmd = "unzip -o $#"
  if defined(Windows):
    cmd = "powershell -nologo -noprofile -command \"& { Add-Type -A " &
          "'System.IO.Compression.FileSystem'; " &
          "[IO.Compression.ZipFile]::ExtractToDirectory('$#', '.'); }\""

  echo "# Extracting " & zipfile
  discard execAction(&"cd {outdir.sanitizePath} && {cmd % zipfile}")

proc extractTar*(tarfile, outdir: string) =
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

  echo "# Extracting " & tarfile
  discard execAction(&"cd {outdir.sanitizePath} && {cmd}")
  if name.len != 0:
    rmFile(outdir / name)

proc downloadUrl*(url, outdir: string) =
  ## Download a file using `curl` or `wget` (or `powershell` on Windows) to the specified directory
  ##
  ## If an archive file, it is automatically extracted after download.
  let
    file = url.extractFilename()
    ext = file.splitFile().ext.toLowerAscii()
    archives = @[".zip", ".xz", ".gz", ".bz2", ".tgz", ".tar"]

  if not (ext in archives and fileExists(outdir/file)):
    echo "# Downloading " & file
    mkDir(outdir)
    var cmd = findExe("curl")
    if cmd.len != 0:
      cmd &= " -Lk $# -o $#"
    else:
      cmd = findExe("wget")
      if cmd.len != 0:
        cmd &= " $# -o $#"
      elif defined(Windows):
        cmd = "powershell [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; wget $# -OutFile $#"
      else:
        doAssert false, "No download tool available - curl, wget"
    discard execAction(cmd % [url, (outdir/file).sanitizePath])

    if ext == ".zip":
      extractZip(file, outdir)
    elif ext in archives:
      extractTar(file, outdir)

proc gitReset*(outdir: string) =
  ## Hard reset the git repository at the specified directory
  echo "# Resetting " & outdir

  let cmd = &"cd {outdir.sanitizePath} && git reset --hard"
  while execAction(cmd).contains("Permission denied"):
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
    outdirQ = outdir.sanitizePath

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

proc findFile*(file: string, dir: string, recurse = true, first = false, regex = false): string =
  ## Find the file in the specified directory
  ##
  ## `file` is a regular expression if `regex` is true
  ##
  ## Turn off recursive search with `recurse` and stop on first match with
  ## `first`. Without it, the shortest match is returned.
  var
    cmd =
      when defined(windows):
        "nimgrep --filenames --oneline --nocolor $1 $2 $3"
      elif defined(linux):
        "find $3 $1 -regextype egrep -regex $2"
      elif defined(osx):
        "find -E $3 $1 -regex $2"

    recursive = ""

  if recurse:
    when defined(windows):
      recursive = "--recursive"
  else:
    when not defined(windows):
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
    (files, ret) = gorgeEx(cmd)
  if ret == 0:
    for line in files.splitLines():
      let f =
        when defined(windows):
          if ": " in line:
            line.split(": ", maxsplit = 1)[1]
          else:
            ""
        else:
          line

      if (f.len != 0 and (result.len == 0 or result.len > f.len)):
        result = f
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

        echo execAction(&"cd {(path / i).parentDir().sanitizePath} && bash autogen.sh")

        break

  if not fileExists(path / "configure"):
    for i in @["configure.ac", "configure.in"]:
      if fileExists(path / i):
        echo "#   Running autoreconf"

        echo execAction(&"cd {path.sanitizePath} && autoreconf -fi")

        break

  if fileExists(path / "configure"):
    echo "#   Running configure " & flags

    var
      cmd = &"cd {path.sanitizePath} && bash configure"
    if flags.len != 0:
      cmd &= &" {flags}"

    echo execAction(cmd)

  doAssert (path / check).fileExists(), "# Configure failed"

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

  var
    cmd = &"cd {path.sanitizePath} && cmake {flags}"

  echo execAction(cmd)

  doAssert (path / check).fileExists(), "# cmake failed"

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

  echo execAction(cmd)

  doAssert findFile(check, path, regex = regex).len != 0, "# make failed"

proc getGccPaths*(mode = "c"): seq[string] =
  var
    nul = when defined(Windows): "nul" else: "/dev/null"
    mmode = if mode == "cpp": "c++" else: mode
    inc = false

    (outp, _) = gorgeEx(&"""{getEnv("CC", "gcc")} -Wp,-v -x{mmode} {nul}""")

  for line in outp.splitLines():
    if "#include <...> search starts here" in line:
      inc = true
      continue
    elif "End of search list" in line:
      break
    if inc:
      var
        path = line.strip().myNormalizedPath()
      if path notin result:
        result.add path

  when defined(osx):
    result.add execAction("xcrun --show-sdk-path").strip() & "/usr/include"

proc getGccLibPaths*(mode = "c"): seq[string] =
  var
    nul = when defined(Windows): "nul" else: "/dev/null"
    mmode = if mode == "cpp": "c++" else: mode
    linker = when defined(OSX): "-Xlinker" else: ""

    (outp, _) = gorgeEx(&"""{getEnv("CC", "gcc")} {linker} -v -x{mmode} {nul}""")

  for line in outp.splitLines():
    if "LIBRARY_PATH=" in line:
      for path in line[13 .. ^1].split(PathSep):
        var
          path = path.strip().myNormalizedPath()
        if path notin result:
          result.add path
      break
    elif '\t' in line:
      var
        path = line.strip().myNormalizedPath()
      if path notin result:
        result.add path

  when defined(osx):
    result.add "/usr/lib"

proc getStdPath(header: string): string =
  for inc in getGccPaths():
    result = findFile(header, inc, recurse = false, first = true)
    if result.len != 0:
      break

proc getStdLibPath(lname: string): string =
  for lib in getGccLibPaths():
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

proc getLocalPath(header, outdir: string): string =
  if outdir.len != 0:
    result = findFile(header, outdir)

proc getNumProcs(): string =
  when defined(windows):
    getEnv("NUMBER_OF_PROCESSORS").strip()
  elif defined(linux):
    execAction("nproc").strip()
  elif defined(macosx):
    execAction("sysctl -n hw.ncpu").strip()
  else:
    "1"

proc buildLibrary(lname, outdir, conFlags, cmakeFlags, makeFlags: string): string =
  var
    conDeps = false
    conDepStr = ""
    cmakeDeps = false
    cmakeDepStr = ""
    lpath = findFile(lname, outdir, regex = true)
    makeFlagsProc = &"-j {getNumProcs()} {makeFlags}"
    made = false
    makePath = outdir

  if lpath.len != 0:
    return lpath

  if not fileExists(outdir / "Makefile"):
    if fileExists(outdir / "CMakeLists.txt"):
      if findExe("cmake").len != 0:
        var
          gen = ""
        when defined(windows):
          if findExe("sh").len != 0:
            let
              uname = execAction("sh -c uname -a").toLowerAscii()
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
        makePath = outdir / "buildcache"
        cmake(makePath, "Makefile", &".. -G {gen} {cmakeFlags}")
        cmakeDeps = true
      else:
        cmakeDepStr &= "cmake executable missing"

    if not cmakeDeps:
      if findExe("bash").len != 0:
        for file in @["configure", "configure.ac", "configure.in", "autogen.sh", "build/autogen.sh"]:
          if fileExists(outdir / file):
            configure(outdir, "Makefile", conFlags)
            conDeps = true

            break
      else:
        conDepStr &= "bash executable missing"

  if fileExists(makePath / "Makefile"):
    make(makePath, lname, makeFlagsProc, regex = true)
    made = true

  var
    error = ""
  if not cmakeDeps and cmakeDepStr.len != 0:
    error &= &"cmake capable but {cmakeDepStr}\n"
  if not conDeps and conDepStr.len != 0:
    error &= &"configure capable but {conDepStr}\n"
  if error.len == 0:
    error = "No build files found in " & outdir
  doAssert cmakeDeps or conDeps or made, &"\n# Build configuration failed - {error}\n"

  result = findFile(lname, outdir, regex = true)

proc getDynlibExt(): string =
  when defined(windows):
    result = ".dll"
  elif defined(linux):
    result = ".so[0-9.]*"
  elif defined(macosx):
    result = ".dylib[0-9.]*"

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

macro getHeader*(header: static[string], giturl: static[string] = "", dlurl: static[string] = "", outdir: static[string] = "",
  conFlags: static[string] = "", cmakeFlags: static[string] = "", makeFlags: static[string] = "",
  altNames: static[string] = ""): untyped =
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
  ##
  ## This allows a single wrapper to be used in different ways depending on the user's needs.
  ## If no `-d:xxx` defines are specified, `outdir` will be searched for the header as is.
  ##
  ## `-d:xxxSetVer=x.y.z` can be used to specify which version to use. It is used as a tag
  ## name for Git whereas for DL, it replaces `$1` in the URL defined.
  ##
  ## All defines can also be set in code using `setDefines()`.
  ##
  ## The library is then configured (with `cmake` or `autotools` if possible) and built
  ## using `make`, unless using `-d:xxxStd` which presumes that the system package
  ## manager was used to install prebuilt headers and binaries.
  ##
  ## The header path is stored in `const xxxPath` and can be used in a `cImport()` call
  ## in the calling wrapper. The dynamic library path is stored in `const xxxLPath` and can
  ## be used for the `dynlib` parameter (within quotes) or with `{.passL.}`.
  ##
  ## `-d:xxxStatic` can be specified to statically link with the library instead. This
  ## will automatically add a `{.passL.}` call to the static library for convenience.
  ##
  ## `conFlags`, `cmakeFlags` and `makeFlags` allow sending custom parameters to `configure`,
  ## `cmake` and `make` in case additional configuration is required as part of the build process.
  ##
  ## `altNames` is a list of alternate names for the library - e.g. zlib uses `zlib.h` for the header but
  ## the typical lib name is `libz.so` and not `libzlib.so`. In this case, `altNames = "z"`. Comma
  ## separate for multiple alternate names.
  ##
  ## `xxxPreBuild` is a hook that is called after the source code is pulled from Git or downloaded but
  ## before the library is built. This might be needed if some initial prep needs to be done before
  ## compilation. A few values are provided to the hook to help provide context:
  ##
  ## `outdir` is the same `outdir` passed in and `header` is the discovered header path in the
  ## downloaded source code.
  ##
  ## Simply define `proc xxxPreBuild(outdir, header: string)` in the wrapper and it will get called
  ## prior to the build process.
  var
    name = header.extractFilename().split(".")[0]

    stdStr = name & "Std"
    gitStr = name & "Git"
    dlStr = name & "DL"

    staticStr = name & "Static"
    verStr = name & "SetVer"

    nameStd = newIdentNode(stdStr)
    nameGit = newIdentNode(gitStr)
    nameDL = newIdentNode(dlStr)

    nameStatic = newIdentNode(staticStr)

    path = newIdentNode(name & "Path")
    lpath = newIdentNode(name & "LPath")
    version = newIdentNode(verStr)
    lname = newIdentNode(name & "LName")
    preBuild = newIdentNode(name & "PreBuild")

    lre = "(lib)?$1[_]?(static)?[0-9.\\-]*\\"

    stdVal = gDefines.hasKey(stdStr)
    gitVal = gDefines.hasKey(gitStr)
    dlVal = gDefines.hasKey(dlStr)
    staticVal = gDefines.hasKey(staticStr)
    verVal =
      if gDefines.hasKey(verStr):
        gDefines[verStr]
      else:
        ""

  if altNames.len != 0:
    let
      names = "(" & name & "|" & altNames.replace(",", "|") & ")"
    lre = lre % names
  else:
    lre = lre % name

  result = newNimNode(nnkStmtList)
  result.add(quote do:
    const
      `nameStd`* = when defined(`nameStd`): true else: `stdVal` == 1
      `nameGit`* = when defined(`nameGit`): true else: `gitVal` == 1
      `nameDL`* = when defined(`nameDL`): true else: `dlVal` == 1
      `nameStatic`* = when defined(`nameStatic`): true else: `staticVal` == 1

      `version`* {.strdefine.} = `verVal`
      `lname` =
        when `nameStatic`:
          `lre` & ".a"
        else:
          `lre` & getDynlibExt()

    when `nameStd`:
      const
        `path`* = getStdPath(`header`)
        `lpath`* = getStdLibPath(`lname`)
    else:
      const
        `path`* =
          when `nameGit`:
            getGitPath(`header`, `giturl`, `outdir`, `version`)
          elif `nameDL`:
            getDlPath(`header`, `dlurl`, `outdir`, `version`)
          else:
            getLocalPath(`header`, `outdir`)

      when declared(`preBuild`):
        static:
          `preBuild`(`outdir`, `path`)

      const
        `lpath`* = buildLibrary(`lname`, `outdir`, `conFlags`, `cmakeFlags`, `makeFlags`)

    static:
      doAssert `path`.len != 0, "\nHeader " & `header` & " not found - " & "missing/empty outdir or -d:$1Std -d:$1Git or -d:$1DL not specified" % `name`
      doAssert `lpath`.len != 0, "\nLibrary " & `lname` & " not found"
      echo "# Including library " & `lpath`

    when `nameStatic`:
      {.passL: `lpath`.}
  )
