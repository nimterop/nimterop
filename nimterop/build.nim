import macros, osproc, regex, sequtils, strformat, strutils

import os except findExe

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

  discard execAction(&"{cmd} {source.quoteShell}")

proc rmDir*(source: string) =
  ## Remove a directory or pattern at compile time
  rmFile(source, dir = true)

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

proc findFile*(file: string|Regex, dir: string, recurse = true, first = false): string =
  ## Find the file in the specified directory
  ##
  ## ``file`` can be a string or a regex object
  ##
  ## Turn off recursive search with ``recurse`` and stop on first match with
  ## ``first``. Without it, the shortest match is returned.
  when file is Regex:
    var
      rm: RegexMatch

  for f in walkDirRec(dir, yieldFilter = {pcFile, pcLinkToFile},
    followFilter = if recurse: {pcDir} else: {}):
    let
      fn = f.extractFilename()
    when file is string:
      if (result.len == 0 or result.len > f.len) and fn == file:
        result = f
        if first: break
    else:
      if (result.len == 0 or result.len > f.len) and fn.match(file, rm):
        result = f
        if first: break

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
    for i in @[path / "autogen.sh", path / "build" / "autogen.sh"]:
      if fileExists(i):
        echo "#   Running autogen.sh"

        discard execAction(&"cd {i.parentDir().quoteShell} && bash autogen.sh")

        break

  if fileExists(path / "configure"):
    echo "#   Running configure " & flags

    var
      cmd = &"cd {path.quoteShell} && bash configure"
    if flags.len != 0:
      cmd &= &" {flags}"

    echo execAction(cmd)

  doAssert (path / check).fileExists(), "# Configure failed"

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

  doAssert (path / check).fileExists(), "# cmake failed"

proc make*(path, check: string|Regex, flags = "") =
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
  if findFile(check, path).len != 0:
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

  doAssert findFile(check, path).len != 0, "# make failed"

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
        path = line.strip()
      path.normalizePath()
      if path notin result:
        result.add path

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
          path = path.strip()
        path.normalizePath()
        if path notin result:
          result.add path
      break
    elif '\t' in line:
      var
        path = line.strip()
      path.normalizePath()
      if path notin result:
        result.add path

proc getStdPath(header: string): string =
  for inc in getGccPaths():
    result = findFile(header, inc, recurse = false, first = true)
    if result.len != 0:
      break

proc getStdLibPath(lname: string): string =
  for lib in getGccLibPaths():
    result = findFile(re(lname), lib, recurse = false, first = true)
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
    lpath = findFile(re(lname), outdir)
    makeFlagsProc = &"-j {getNumProcs()} {makeFlags}"

  if lpath.len != 0:
    return lpath

  if fileExists(outdir / "CMakeLists.txt"):
    if findExe("cmake").len != 0:
      var
        gen = ""
      when defined(windows):
        if findExe("sh").len != 0:
          gen = "MSYS Makefiles"
        else:
          gen = "MinGW Makefiles"
      else:
        gen = "Unix Makefiles"
      cmake(outdir / "build", "Makefile", &".. -G {gen.quoteShell} {cmakeFlags}")
      cmakeDeps = true
      make(outdir / "build", re(lname), makeFlagsProc)
    else:
      cmakeDepStr &= "cmake executable missing"

  template cfgCommon() {.dirty.} =
    configure(outdir, "Makefile", conFlags)
    conDeps = true
    make(outdir, re(lname), makeFlagsProc)

  if not cmakeDeps:
    if not fileExists(outdir / "configure"):
      if fileExists(outdir / "autogen.sh") or fileExists(outdir / "build" / "autogen.sh"):
        if findExe("aclocal").len != 0:
          if findExe("autoconf").len != 0:
            if findExe("libtoolize").len != 0 or findExe("glibtoolize").len != 0:
              if findExe("autopoint").len != 0:
                cfgCommon()
              else:
                conDepStr &= "autopoint executable missing"
            else:
              conDepStr &= "libtoolize executable missing"
          else:
            conDepStr &= "autoconf executable missing"
        else:
          conDepStr &= "aclocal executable missing"
    else:
      if findExe("bash").len != 0:
        cfgCommon()
      else:
        conDepStr &= "bash executable missing"

  var
    error = ""
  if not cmakeDeps and cmakeDepStr.len != 0:
    error &= &"cmake capable but {cmakeDepStr}\n"
  if not conDeps and conDepStr.len != 0:
    error &= &"configure capable but {conDepStr}\n"
  if error.len == 0:
    error = "No build files found in " & outdir
  doAssert cmakeDeps or conDeps, &"\n# Build configuration failed - {error}\n"

  result = findFile(re(lname), outdir)

proc getDynlibExt(): string =
  when defined(windows):
    result = ".dll"
  elif defined(linux):
    result = ".so[0-9.]*"
  elif defined(macosx):
    result = ".dylib[0-9.]*"

macro getHeader*(header: static[string], giturl: static[string] = "", dlurl: static[string] = "", outdir: static[string] = "",
  conFlags: static[string] = "", cmakeFlags: static[string] = "", makeFlags: static[string] = ""): untyped =
  ## Get the path to a header file for wrapping with
  ## `cImport() <cimport.html#cImport.m%2C%2Cstring%2Cstring%2Cstring>`_ or
  ## `c2nImport() <cimport.html#c2nImport.m%2C%2Cstring%2Cstring%2Cstring>`_.
  ##
  ## This proc checks -d:xxx defines based on the header name (e.g. lzma from lzma.h),
  ## and accordingly employs different ways to obtain the source.
  ##
  ## ``-d:xxxStd`` - search standard system paths. E.g. ``/usr/include`` and ``/usr/lib`` on Linux
  ## ``-d:xxxGit`` - clone source from a git repo specified in ``giturl``
  ## ``-d:xxxDL`` - download source from ``dlurl`` and extract if required
  ##
  ## This allows a single wrapper to be used in different ways depending on the user's needs.
  ## If no -d:xxx defines are specified, ``outdir`` will be searched for the header.
  ##
  ## The library is then configured (with cmake or autotools if possible) and built
  ## using make, unless using ``-d:xxxStd`` which presumes that the system package
  ## manager was used to install prebuilt headers and binaries.
  ##
  ## The header path is stored in ``const xxxPath`` and can be used in a ``cImport()`` call
  ## in the calling wrapper. The dynamic library path is stored in ``const xxxLPath`` and can
  ## be used for the ``dynlib`` parameter (within quotes).
  ##
  ## ``-d:xxxStatic`` can be specified to statically link with the library instead. This
  ## will automatically add a ``{.passL.}`` call to the static library for convenience.
  var
    name = header.split(".")[0]

    nameStd = newIdentNode(name & "Std")
    nameGit = newIdentNode(name & "Git")
    nameDL = newIdentNode(name & "DL")

    nameStatic = newIdentNode(name & "Static")

    path = newIdentNode(name & "Path")
    lpath = newIdentNode(name & "LPath")
    version = newIdentNode(name & "Version")
    lname = newIdentNode(name & "LName")

    lre = "(lib)?$1[0-9.\\-]*\\" % name

  result = newNimNode(nnkStmtList)
  result.add(quote do:
    const
      `version`* {.strdefine.} = ""
      `lname` =
        when defined(`nameStatic`):
          `lre` & ".a"
        else:
          `lre` & getDynlibExt()

    when defined(`nameStd`):
      const
        `path`* = getStdPath(`header`)
        `lpath`* = getStdLibPath(`lname`)
    else:
      const
        `path`* =
          when defined(`nameGit`):
            getGitPath(`header`, `giturl`, `outdir`, `version`)
          elif defined(`nameDL`):
            getDlPath(`header`, `dlurl`, `outdir`, `version`)
          else:
            getLocalPath(`header`, `outdir`)

        `lpath`* = buildLibrary(`lname`, `outdir`, `conFlags`, `cmakeFlags`, `makeFlags`)

    static:
      doAssert `path`.len != 0, "\nHeader " & `header` & " not found - " & "missing/empty outdir or -d:$1Std -d:$1Git or -d:$1DL not specified" % `name`
      doAssert `lpath`.len != 0, "\nLibrary " & `lname` & " not found"
      echo "# Including library " & `lpath`

    when defined(`nameStatic`):
      {.passL: `lpath`.}
  )
