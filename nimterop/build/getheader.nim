import macros, os, strutils, tables

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

proc getDynlibExt(): string =
  when defined(Windows):
    result = "[0-9.\\-]*\\.dll"
  elif defined(linux) or defined(FreeBSD):
    result = "\\.so[0-9.]*"
  elif defined(macosx):
    result = "[0-9.\\-]*\\.dylib"

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
