import os, strformat, strutils

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
