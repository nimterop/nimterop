import hashes, macros, os, strformat, strutils

import "."/[globals, paths]
import "."/build/[ccompiler, misc, nimconf, shell]

proc findPath(path: string, fail = true): string =
  # Relative to project path
  let
    path = fixRelPath(path)
  result = path.replace("\\", "/")
  if not fileExists(result) and not dirExists(result):
    doAssert (not fail), "File or directory not found: " & path
    result = ""

proc getCacheValue(fullpath: string): string =
  if not gStateCT.nocache:
    result = fullpath.getFileDate()

proc getCacheValue(fullpaths: seq[string]): string =
  if not gStateCT.nocache:
    for fullpath in fullpaths:
      result &= getCacheValue(fullpath)

proc getNimCheckError(nimFile: string) =
  let
    (check, _) = execAction(
      &"{getCurrentNimCompiler()} check {nimFile.sanitizePath}",
      die = false
    )

  doAssert false, &"\n\n{check}\n\n" &
    "Codegen limitation or error - review 'nim check' output above generated for " & nimFile

proc getToast(fullpaths: seq[string], recurse: bool = false, dynlib: string = "",
  mode = "c", flags = "", outFile = "", noNimout = false): string =
  var
    cmd = when defined(Windows): "cmd /c " else: ""
    ext = "h"

  let
    toastExe = toastExePath()
    # see https://github.com/nimterop/nimterop/issues/69
    cacheKey = getCacheValue(toastExe) & getCacheValue(fullpaths)

  doAssert fileExists(toastExe), "toast not compiled: " & toastExe.sanitizePath &
    " make sure 'nimble build' or 'nimble install' built it"

  cmd &= &"{toastExe} --preprocess -m:{mode}"

  if recurse:
    cmd.add " --recurse"

  if flags.nBl:
    cmd.add " " & flags

  for i in gStateCT.defines:
    cmd.add &" --defines+={i.quoteShell}"

  for i in gStateCT.includeDirs:
    cmd.add &" --includeDirs+={i.sanitizePath}"

  for i in gStateCT.exclude:
    cmd.add &" --exclude+={i.sanitizePath}"

  for i in gStateCT.passC:
    cmd.add &" --passC+={i.quoteShell}"
  gStateCT.passC = @[]

  for i in gStateCT.passL:
    cmd.add &" --passL+={i.quoteShell}"
  gStateCT.passL = @[]

  for i in gStateCT.compile:
    cmd.add &" --compile+={i.sanitizePath}"
  gStateCT.compile = @[]

  if not noNimout:
    cmd.add &" --pnim"

    if dynlib.nBl:
      cmd.add &" --dynlib={dynlib}"

    if gStateCT.symOverride.nBl:
      cmd.add &" --symOverride={gStateCT.symOverride.join(\",\")}"

    cmd.add &" --nim:{getCurrentNimCompiler().sanitizePath}"

    if gStateCT.pluginSourcePath.nBl:
      cmd.add &" --pluginSourcePath={gStateCT.pluginSourcePath.sanitizePath}"

    ext = "nim"

  for fullpath in fullpaths:
    cmd.add &" {fullpath.sanitizePath}"

  let
    cacheFile = getNimteropCacheDir() / "toastCache" / "nimterop_" &
      ($(cmd & cacheKey).hash().abs()).addFileExt(ext)

  if outFile.nBl:
    result = fixRelPath(outFile)
  else:
    result = cacheFile

  when defined(Windows):
    result = result.replace(DirSep, '/')

  let
    # When to regenerate the wrapper
    regen =
      if gStateCT.nocache or compileOption("forceBuild"):
        # No caching or forced
        true
      elif not fileExists(result):
        # Cache or outfile doesn't exist
        true
      elif outFile.nBl and (not fileExists(cacheFile) or
        result.getFileDate() > cacheFile.getFileDate()):
        # Outfile exists but cache doesn't or outdated
        true
      else:
        false

  if regen:
    let
      dir = result.parentDir()
    if not dirExists(dir):
      mkDir(dir)

    cmd.add &" -o {result.sanitizePath}"

    var
      (output, ret) = execAction(cmd, die = false)
    if ret != 0:
      # If toast fails, print failure to output and delete any generated files
      echo "XXX ", cmd, " ", output
      let errout = if result.fileExists(): result.readFile() & output else: output
      rmFile(result)
      doAssert false, "\n\n" & errout & "\n"

    # Write empty cache file to track changes when outFile specified
    if outFile.nBl:
      let dir = cacheFile.parentDir()
      if not dirExists(dir):
        mkdir(dir)

      writeFile(cacheFile, "")

proc cDebug*() {.compileTime.} =
  ## Enable debug messages and display the generated Nim code
  gStateCT.debug = true

proc cDisableCaching*() {.compileTime.} =
  ## Disable caching of generated Nim code - useful during wrapper development
  ##
  ## If files included by header being processed by
  ## `cImport()` change and affect the generated content, they will be ignored
  ## and the cached value will continue to be used . Use `cDisableCaching()` to
  ## avoid this scenario during development.
  ##
  ## `nim -f` can also be used to flush the cached content.
  gStateCT.nocache = true

proc cSearchPath*(path: string): string {.compileTime.} =
  ## Get full path to file or directory `path` in search path configured
  ## using `cAddSearchDir()` and `cAddStdDir()`.
  ##
  ## This can be used to locate files or directories that can be passed onto
  ## `cCompile()`, `cIncludeDir()` and `cImport()`.
  result = findPath(path, fail = false)
  if result.Bl:
    var found = false
    for inc in gStateCT.searchDirs:
      result = findPath(inc / path, fail = false)
      if result.nBl:
        found = true
        break
    doAssert found, "File or directory not found: " & path &
      " gStateCT.searchDirs: " & $gStateCT.searchDirs

proc cAddSearchDir*(dir: string) {.compileTime.} =
  ## Add directory `dir` to the search path used in calls to
  ## `cSearchPath()`.
  runnableExamples:
    import nimterop/paths, os
    static:
      cAddSearchDir testsIncludeDir()
      doAssert cSearchPath("test.h").fileExists

  if dir notin gStateCT.searchDirs:
    gStateCT.searchDirs.add(dir)

proc cAddStdDir*(mode = "c") {.compileTime.} =
  ## Add the standard `c` [default] or `cpp` include paths to search
  ## path used in calls to `cSearchPath()`.
  runnableExamples:
    import os
    static:
      cAddStdDir()
      doAssert cSearchPath("math.h").fileExists
  for inc in getGccPaths(mode):
    cAddSearchDir inc

macro cDefine*(name: static[string], val: static[string] = ""): untyped =
  ## `#define` an identifer that is forwarded to the C/C++ preprocessor if
  ## called within `cImport()` or `c2nImport()` as well as to the C/C++
  ## compiler during Nim compilation using `{.passC: "-DXXX".}`
  ##
  ## This needs to be called before `cImport()` to take effect.
  var str = name
  if val.nBl:
    str &= &"={val.quoteShell}"

  if str notin gStateCT.defines:
    gStateCT.defines.add(str)

macro cDefine*(values: static seq[string]): untyped =
  ## `#define` multiple identifers that are forwarded to the C/C++ preprocessor
  ## if called within `cImport()` or `c2nImport()` as well as to the C/C++
  ## compiler during Nim compilation using `{.passC: "-DXXX".}`
  ##
  ## This needs to be called before `cImport()` to take effect.
  for value in values:
    let
      spl = value.split("=", maxsplit = 1)
      name = spl[0]
      val = if spl.len == 2: spl[1] else: ""
    discard quote do:
      cDefine(`name`, `val`)

macro cIncludeDir*(dirs: static seq[string], exclude: static[bool] = false): untyped =
  ## Add include directories that are forwarded to the C/C++ preprocessor if
  ## called within `cImport()` or `c2nImport()` as well as to the C/C++
  ## compiler during Nim compilation using `{.passC: "-IXXX".}`.
  ##
  ## Set `exclude = true` if the contents of these include directories should
  ## not be included in the wrapped output.
  ##
  ## This needs to be called before `cImport()` to take effect.
  for dir in dirs:
    let fullpath = findPath(dir)
    if fullpath notin gStateCT.includeDirs:
      gStateCT.includeDirs.add(fullpath)
      if exclude:
        gStateCT.exclude.add(fullpath)

macro cIncludeDir*(dir: static[string], exclude: static[bool] = false): untyped =
  ## Add an include directory that is forwarded to the C/C++ preprocessor if
  ## called within `cImport()` or `c2nImport()` as well as to the C/C++
  ## compiler during Nim compilation using `{.passC: "-IXXX".}`.
  ##
  ## Set `exclude = true` if the contents of this include directory should
  ## not be included in the wrapped output.
  ##
  ## This needs to be called before `cImport()` to take effect.
  return quote do:
    cIncludeDir(@[`dir`], `exclude` == 1)

macro cExclude*(paths: static seq[string]): untyped =
  ## Exclude specified paths - files or directories from the wrapped output
  ##
  ## Full path to file or directory is required.
  result = newNimNode(nnkStmtList)
  for path in paths:
    gStateCT.exclude.add path

macro cExclude*(path: static string): untyped =
  ## Exclude specified path - file or directory from the wrapped output.
  ##
  ## Full path to file or directory is required.
  return quote do:
    cExclude(@[`path`])

macro cPassC*(value: static string): untyped =
  ## Create a `{.passC.}` entry that gets forwarded to the C/C++ compiler
  ## during Nim compilation.
  ##
  ## `cPassC()` needs to be called before `cImport()` to take effect and gets
  ## consumed and reset so as not to impact subsequent `cImport()` calls.
  gStateCT.passC.add value

macro cPassL*(value: static string): untyped =
  ## Create a `{.passL.}` entry that gets forwarded to the C/C++ compiler
  ## during Nim compilation.
  ##
  ## `cPassL()` needs to be called before `cImport()` to take effect and gets
  ## consumed and reset so as not to impact subsequent `cImport()` calls.
  gStateCT.passL.add value

macro cCompile*(path: static string, mode: static[string] = "c", exclude: static[string] = ""): untyped =
  ## Compile and link C/C++ implementation into resulting binary using `{.compile.}`
  ##
  ## `path` can be a specific file or contain `*` wildcard for filename:
  ##
  ## .. code-block:: nim
  ##
  ##     cCompile("file.c")
  ##     cCompile("path/to/*.c")
  ##
  ## `mode` recursively searches for code files in `path`.
  ##
  ## `c` searches for `*.c` whereas `cpp` searches for `*.C *.cpp *.c++ *.cc *.cxx`
  ##
  ## .. code-block:: nim
  ##
  ##    cCompile("path/to/dir", "cpp")
  ##
  ## `exclude` can be used to exclude files by partial string match. Comma separated to
  ## specify multiple exclude strings
  ##
  ## .. code-block:: nim
  ##
  ##    cCompile("path/to/dir", exclude="test2.c")
  ##
  ## `cCompile()` needs to be called before `cImport()` to take effect and gets
  ## consumed and reset so as not to impact subsequent `cImport()` calls.

  proc fcompile(file: string) =
    let
      (_, fn, ext) = file.splitFile()
    var
      ufn = fn
      uniq = 1
    while ufn in gStateCT.compcache:
      ufn = fn & $uniq
      uniq += 1

    # - https://github.com/nim-lang/Nim/issues/10299
    # - https://github.com/nim-lang/Nim/issues/10486
    gStateCT.compcache.add(ufn)
    if fn == ufn:
      gStateCT.compile.add file.replace("\\", "/")
    else:
      # - https://github.com/nim-lang/Nim/issues/9370
      let
        hash = file.hash().abs()
        tmpFile = file.parentDir() / &"_nimterop_{$hash}_{ufn}{ext}"
      if not tmpFile.fileExists() or file.getFileDate() > tmpFile.getFileDate():
        cpFile(file, tmpFile)
      gStateCT.compile.add tmpFile.replace("\\", "/")

  # Due to https://github.com/nim-lang/Nim/issues/9863
  # cannot use seq[string] for excludes
  proc notExcluded(file, exclude: string): bool =
    result = true
    if "_nimterop_" in file:
      result = false
    elif exclude.nBl:
      for excl in exclude.split(","):
        if excl in file:
          result = false

  proc dcompile(dir, exclude: string, ext="") =
    let
      (dir, pat) =
        if "*" in dir:
          dir.splitPath()
        else:
          (dir, "")

    for file in walkDirRec(dir):
      if ext.nBl or pat.nBl:
        let
          fext = file.splitFile().ext
        if (ext.nBl and fext != ext) or (pat.nBl and fext != pat[1 .. ^1]):
          continue
      if file.notExcluded(exclude):
        fcompile(file)

  if "*" in path:
    dcompile(path, exclude)
  else:
    let fpath = findPath(path)
    if fileExists(fpath) and fpath.notExcluded(exclude):
      fcompile(fpath)
    elif dirExists(fpath):
      if mode.contains("cpp"):
        for i in @[".cpp", ".c++", ".cc", ".cxx"]:
          dcompile(fpath, exclude, i)
        when not defined(Windows):
          dcompile(fpath, exclude, ".C")
      else:
        dcompile(fpath, exclude, ".c")

macro renderPragma*(): untyped =
  ## All `cDefine()`, `cIncludeDir()`, `cCompile()`, `cPassC()` and `cPassL()`
  ## content typically gets forwarded via `cImport()` to the generated wrapper to be
  ## rendered as part of the output so as to enable standalone wrappers. If `cImport()`
  ## is not being used for some reason, `renderPragma()` can create these pragmas
  ## in the nimterop wrapper itself. A good example is using `getHeader()` without
  ## calling `cImport()`.
  ##
  ## `c2nImport()` already uses this macro so there's no need to use it when typically
  ## wrapping headers.
  result = newNimNode(nnkStmtList)

  for i in gStateCT.defines:
    let str = "-D" & i
    result.add quote do:
      {.passC: `str`.}

  for i in gStateCT.includeDirs:
    let str = &"-I{i.quoteShell}"
    result.add quote do:
      {.passC: `str`.}

  for i in gStateCT.passC:
    result.add quote do:
      {.passC: `i`.}
  gStateCT.passC = @[]

  for i in gStateCT.passL:
    result.add quote do:
      {.passL: `i`.}
  gStateCT.passL = @[]

  for i in gStateCT.compile:
    result.add quote do:
      {.compile: `i`.}
  gStateCT.compile = @[]

proc cSkipSymbol*(skips: seq[string]) {.compileTime.} =
  ## Similar to `cOverride()`, this macro allows filtering out symbols not of
  ## interest from the generated output.
  ##
  ## `cSkipSymbol()` only affects calls to `cImport()` that follow it.
  runnableExamples:
    static: cSkipSymbol @["proc1", "Type2"]
  gStateCT.symOverride.add skips

macro cOverride*(body): untyped =
  ## When the wrapper code generated by nimterop is missing certain symbols or not
  ## accurate, it may be required to hand wrap them. Define them in a `cOverride()`
  ## macro block so that Nimterop uses these definitions instead.
  ##
  ## For example:
  ##
  ## .. code-block:: c
  ##
  ##    int svGetCallerInfo(const char** fileName, int *lineNumber);
  ##
  ## This might map to:
  ##
  ## .. code-block:: nim
  ##
  ##    proc svGetCallerInfo(fileName: ptr cstring; lineNumber: var cint)
  ##
  ## Whereas it might mean:
  ##
  ## .. code-block:: nim
  ##
  ##    cOverride:
  ##      proc svGetCallerInfo(fileName: var cstring; lineNumber: var cint)
  ##
  ## Using the `cOverride()` block, nimterop can be instructed to use this
  ## definition of `svGetCallerInfo()` instead. This works for procs, consts
  ## and types.
  ##
  ## `cOverride()` only affects the next `cImport()` call. This is because any
  ## recognized symbols get overridden in place and any remaining symbols get
  ## added to the top. If reused, the next `cImport()` would add those symbols
  ## again leading to redefinition errors.

  iterator findOverrides(node: NimNode): tuple[name, override: string, kind: NimNodeKind] =
    for child in node:
      case child.kind
      of nnkTypeSection, nnkConstSection:
        # Types, const
        for inst in child:
          let name =
            if inst[0].kind == nnkPragmaExpr:
              $inst[0][0]
            else:
              $inst[0]

          yield (name.strip(chars={'*'}), inst.repr, child.kind)
      of nnkProcDef:
        let
          name = $child[0]

        yield (name.strip(chars={'*'}), child.repr, child.kind)
      else:
        discard

  if gStateCT.overrides.Bl:
    gStateCT.overrides = """
import sets, tables

proc onSymbolOverride*(sym: var Symbol) {.exportc, dynlib.} =
"""

  # If cPlugin called before cOverride
  if gStateCT.pluginSourcePath.nBl:
    gStateCT.pluginSourcePath = ""

  var
    names: seq[string]
  for name, override, kind in body.findOverrides():
    let
      typ =
        case kind
        of nnkTypeSection: "nskType"
        of nnkConstSection: "nskConst"
        of nnkProcDef: "nskProc"
        else: ""

    gStateCT.overrides &= &"""
  if sym.name == "{name}" and sym.kind == {typ} and "{name}" in cOverrides["{typ}"]:
    sym.override = """ & "\"\"\"" & override & "\"\"\"\n"

    gStateCT.overrides &= &"    cOverrides[\"{typ}\"].excl \"{name}\"\n"

    gStateCT.overrides = gStateCT.overrides.replace("proc onSymbolOverride",
      &"cOverrides[\"{typ}\"].incl \"{name}\"\nproc onSymbolOverride")

    names.add name

    gStateCT.symOverride.add name

  if names.nBl:
    decho "Overriding " & names.join(" ")

proc cPluginHelper(body: string, imports = "import macros, nimterop/plugin\n\n") =
  gStateCT.pluginSource = body

  if gStateCT.pluginSource.nBl or gStateCT.overrides.nBl:
    let
      data = imports & body & "\n\n" & gStateCT.overrides
      hash = data.hash().abs()
      path = getProjectCacheDir("cPlugins", forceClean = false) / "nimterop_" & $hash & ".nim"

    if not fileExists(path) or gStateCT.nocache or compileOption("forceBuild"):
      mkDir(path.parentDir())
      writeFile(path, data)
      writeNimConfig(path & ".cfg")

    doAssert fileExists(path), "Unable to write plugin file: " & path

    gStateCT.pluginSourcePath = path

macro cPlugin*(body): untyped =
  ## When `cOverride()` and `cSkipSymbol()` are not adequate, the `cPlugin()`
  ## macro can be used to customize the generated Nim output. The following
  ## callbacks are available at this time.
  ##
  ## .. code-block:: nim
  ##
  ##     proc onSymbol(sym: var Symbol) {.exportc, dynlib.}
  ##
  ## `onSymbol()` can be used to handle symbol name modifications required due
  ## to invalid characters in identifiers or to rename symbols that would clash
  ## due to Nim's style insensitivity. The symbol name and type is provided to
  ## the callback and the name can be modified.
  ##
  ## While `cPlugin` can easily remove leading/trailing `_` or prefixes and
  ## suffixes like `SDL_`, passing `--prefix` or `--suffix` flags to `cImport`
  ## in the `flags` parameter is much easier. However, these flags will only be
  ## considered when no `cPlugin` is specified.
  ##
  ## Returning a blank name will result in the symbol being skipped. This will
  ## fail for `nskParam` and `nskField` since the generated Nim code will be wrong.
  ##
  ## Symbol types can be any of the following:
  ## - `nskConst` for constants
  ## - `nskType` for type identifiers, including primitive
  ## - `nskParam` for param names
  ## - `nskField` for struct field names
  ## - `nskEnumField` for enum (field) names, though they are in the global namespace as `nskConst`
  ## - `nskProc` - for proc names
  ##
  ## `macros` and `nimterop/plugins` are implicitly imported to provide access to standard
  ## plugin facilities.
  ##
  ## `cPlugin()`  only affects calls to `cImport()` that follow it.
  runnableExamples:
    cPlugin:
      import strutils

      # Strip leading and trailing underscores
      proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
        sym.name = sym.name.strip(chars={'_'})

  runnableExamples:
    cPlugin:
      import strutils

      # Strip prefix from procs
      proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
        if sym.kind == nskProc and sym.name.contains("SDL_"):
          sym.name = sym.name.replace("SDL_", "")

  cPluginHelper(body.repr)

macro cPluginPath*(path: static[string]): untyped =
  ## Rather than embedding the `cPlugin()` code within the wrapper, it might be
  ## preferable to have it stored in a separate source file. This allows for reuse
  ## across multiple wrappers when applicable.
  ##
  ## The `cPluginPath()` macro enables this functionality - specify the path to the
  ## plugin file and it will be consumed in the same way as `cPlugin()`.
  ##
  ## `path` is relative to the current dir and not necessarily relative to the
  ## location of the wrapper file. Use `currentSourcePath` to specify a path relative
  ## to the wrapper file.
  ##
  ## Unlike `cPlugin()`, this macro also does not implicitly import any other modules
  ## since the standalone plugin file will need explicit imports for `nim check` and
  ## suggestions to work. `import nimterop/plugin` is required for all plugins.
  doAssert fileExists(path), "Plugin file not found: " & path
  cPluginHelper(readFile(path), imports = "")

macro cImport*(filenames: static seq[string], recurse: static bool = false, dynlib: static string = "",
  mode: static string = "c", flags: static string = "", nimFile: static string = ""): untyped =
  ## Import multiple headers in one shot
  ##
  ## This macro is preferable over multiple individual `cImport()` calls, especially
  ## when the headers might `#include` the same headers and result in duplicate symbols.
  result = newNimNode(nnkStmtList)

  var
    fullpaths: seq[string]

  for filename in filenames:
    fullpaths.add findPath(filename)

  # In case cOverride called after cPlugin
  if gStateCT.pluginSourcePath.Bl:
    cPluginHelper(gStateCT.pluginSource)

  gecho "# Importing " & fullpaths.join(", ").sanitizePath

  let
    nimFile = getToast(fullpaths, recurse, dynlib, mode, flags, nimFile)

  # Reset plugin and overrides for next cImport
  if gStateCT.overrides.nBl:
    gStateCT.pluginSourcePath = ""
    gStateCT.overrides = ""

  if gStateCT.debug:
    gecho nimFile.readFile()

  gecho "# Saved to " & nimFile

  try:
    let
      nimFileNode = newStrLitNode(nimFile.changeFileExt(""))
    result.add quote do:
      include `nimFileNode`
  except:
    getNimCheckError(nimFile)

macro cImport*(filename: static string, recurse: static bool = false, dynlib: static string = "",
  mode: static string = "c", flags: static string = "", nimFile: static string = ""): untyped =
  ## Import all supported definitions from specified header file. Generated
  ## content is cached in `nimcache` until `filename` changes unless
  ## `cDisableCaching()` is set. `nim -f` can also be used to flush the cache.
  ##
  ## `recurse` can be used to generate Nim wrappers from `#include` files
  ## referenced in `filename`. This is only done for files in the same
  ## directory as `filename` or in a directory added using
  ## `cIncludeDir()`.
  ##
  ## `dynlib` can be used to specify the Nim string to use to specify the dynamic
  ## library to load the imported symbols from. For example:
  ##
  ## .. code-block:: nim
  ##
  ##    const
  ##      dynpcre =
  ##        when defined(Windows):
  ##          when defined(cpu64):
  ##            "pcre64.dll"
  ##          else:
  ##            "pcre32.dll"
  ##        elif hostOS == "macosx":
  ##          "libpcre(.3|.1|).dylib"
  ##        else:
  ##          "libpcre.so(.3|.1|)"
  ##
  ##    cImport("pcre.h", dynlib="dynpcre")
  ##
  ## If `dynlib` is not specified, the C/C++ implementation files can be compiled
  ## in with `cCompile()`, or the `{.passL.}` pragma can be used to specify the
  ## static lib to link.
  ##
  ## `mode` selects the preprocessor and tree-sitter parser to be used to process
  ## the header.
  ##
  ## `flags` can be used to pass any other command line arguments to `toast`. A
  ## good example would be `--prefix` and `--suffix` which strip leading and
  ## trailing strings from identifiers, `_` being quite common.
  ##
  ## `nimFile` is the location where the generated wrapper should get written.
  ## By default, the generated wrapper is written to `nimcache` and included from
  ## there. `nimFile` makes it possible to write the wrapper to a predetermined
  ## location which can then be directly imported into the main application and
  ## checked into source control if preferred. Importing the nimterop wrapper with
  ## `nimFile` specified still works per usual. If `nimFile` is not an absolute
  ## path, it is relative to the project path.
  ##
  ## `cImport()` consumes and resets preceding `cOverride()` calls. `cPlugin()`
  ## is retained for the next `cImport()` call unless a new `cPlugin()` call is
  ## defined.
  return quote do:
    cImport(@[`filename`], bool(`recurse`), `dynlib`, `mode`, `flags`, `nimFile`)

macro c2nImport*(filename: static string, recurse: static bool = false, dynlib: static string = "",
  mode: static string = "c", flags: static string = "", nimFile: static string = ""): untyped =
  ## Import all supported definitions from specified header file using `c2nim`
  ##
  ## Similar to `cImport()` but uses `c2nim` to generate the Nim wrapper instead
  ## of `toast`. Note that neither `cOverride()`, `cSkipSymbol()` nor `cPlugin()`
  ## have any impact on `c2nim`.
  ##
  ## `toast` is only used to preprocess the header file and `recurse` if specified.
  ##
  ## `mode` should be set to `cpp` for c2nim to wrap C++ headers.
  ##
  ## `flags` can be used to pass other command line arguments to `c2nim`.
  ##
  ## `nimFile` is the location where the generated wrapper should get written,
  ## similar to `cImport()`.
  ##
  ## `nimterop` does not depend on `c2nim` as a `nimble` dependency so it does not
  ## get installed automatically. Any wrapper or library that requires this proc
  ## needs to install `c2nim` with `nimble install c2nim` or add it as a dependency
  ## in its own `.nimble` file.
  result = newNimNode(nnkStmtList)

  let
    fullpath = findPath(filename)

  gecho "# Importing " & fullpath & " with c2nim"

  let
    hFile = getToast(@[fullpath], recurse, dynlib, mode, noNimout = true)
    nimFile = if nimFile.nBl: fixRelPath(nimFile) else: hFile.changeFileExt("nim")
    header = "header" & fullpath.splitFile().name.split(seps = {'-', '.'}).join()

  if not fileExists(nimFile) or gStateCT.nocache or compileOption("forceBuild"):
    var
      cmd = when defined(Windows): "cmd /c " else: ""
    cmd &= &"c2nim {hFile} --header:{header}  --out:{nimFile.sanitizePath}"

    if dynlib.nBl:
      cmd.add &" --dynlib:{dynlib}"
    if mode.contains("cpp"):
      cmd.add " --cpp"
    if flags.nBl:
      cmd.add &" {flags}"

    for i in gStateCT.defines:
      cmd.add &" --assumedef:{i.quoteShell}"

    # Have to create pragmas for c2nim since toast handles this at runtime
    result.add quote do:
      renderPragma()

    let
      (c2nimout, ret) = execAction(cmd)
    if ret != 0:
      rmFile(nimFile)
      doAssert false, "\n\nc2nim codegen limitation or error - " & c2nimout

    nimFile.writeFile(&"const {header} = \"{fullpath}\"\n\n" & readFile(nimFile))

  if gStateCT.debug:
    gecho nimFile.readFile()

  gecho "# Saved to " & nimFile

  try:
    let
      nimFileNode = newStrLitNode(nimFile.changeFileExt(""))
    result.add quote do:
      include `nimFileNode`
  except:
    getNimCheckError(nimFile)
