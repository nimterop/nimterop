import os, strutils

import nimterop/[cimport, git, paths]

# Documentation:
#   https://github.com/nimterop/nimterop
#   https://nimterop.github.io/nimterop/cimport.html

const
  # Location where any sources should get downloaded. Adjust depending on
  # actual location of wrapper file relative to project.
  baseDir = currentSourcePath.parentDir()/"build"

  # All files and dirs should be inside to baseDir
  srcDir = baseDir/"project"

static:
  # Print generated Nim to output
  cDebug()

  # Disable caching so that wrapper is generated every time. Useful during
  # development. Remove once wrapper is working as expected.
  cDisableCaching()
  
  # Download C/C++ source code from a git repository
  gitPull("https://github.com/user/project", outdir = srcDir, plist = """
include/*.h
src/*.c
""", checkout = "tag/branch/hash")

  # Download source from the web - zip files are auto extracted
  downloadUrl("https://hostname.com/file.h", outdir = srcDir)

  # Run GNU configure on the source
  when defined(posix):
    configure(srcDir, fileThatShouldGetGenerated)

  # Run standard file/directory operations with mkDir(), cpFile(), mvFile()

  # Edit file contents if required with readFile(), writeFile() and standard
  # string operations
  
  # Run any other external commands with execAction()

  # Skip any symbols from being wrapped
  cSkipSymbol(@["type1", "proc2"])

# Manually wrap any symbols since nimterop cannot or incorrectly wraps them
cOverride:
  # Standard Nim code to wrap types, consts, procs, etc.
  type
    symbol = object

# Specify include directories for gcc and Nim
cIncludeDir(srcDir/"include")

# Define global symbols
cDefine("SYMBOL", "value")

# Any global compiler options
{.passC: "flags".}

# Any global linker options
{.passL: "flags".}

# Compile in any common source code
cCompile(srcDir/"file.c")

# Perform OS specific tasks
when defined(windows):
  # Windows specific symbols, options and files

  # Dynamic library to link against
  const dynlibFile =
    when defined(cpu64):
      "xyz64.dll"
    else:
      "xyz32.dll"
elif defined(posix):
  # Common posix symbols, options and files

  when defined(linux):
    # Linux specific
    const dynlibFile = "libxyz.so(.2|.1|)"
  elif defined(osx):
    # MacOSX specific
    const dynlibFile = "libxyz(.2|.1|).dylib"
  else:
    static: doAssert false
else:
  static: doAssert false

# Use cPlugin() to make any symbol changes
cPlugin:
  import strutils

  # Symbol renaming examples
  proc onSymbol*(sym: var Symbol) {.exportc, dynlib.} =
    # Get rid of leading and trailing underscores
    sym.name = sym.name.strip(chars = {'_'})

    # Remove prefixes or suffixes from procs
    if sym.kind == nskProc and sym.name.contains("SDL_"):
      sym.name = sym.name.replace("SDL_", "")

# Finally import wrapped header file. Recurse if #include files should also
# be wrapped. Set dynlib if binding to dynamic library.
cImport(srcDir/"include/file.h", recurse = true, dynlib="dynlibFile")
