[![Chat on Gitter](https://badges.gitter.im/gitterHQ/gitter.png)](https://gitter.im/nimterop/Lobby)
[![Build status](https://ci.appveyor.com/api/projects/status/hol1yvqbp6hq4ao8/branch/master?svg=true)](https://ci.appveyor.com/project/genotrance/nimterop-8jcj7/branch/master)
[![Build Status](https://travis-ci.org/nimterop/nimterop.svg?branch=master)](https://travis-ci.org/nimterop/nimterop)

Nimterop is a [Nim](https://nim-lang.org/) package that aims to make C/C++ interop seamless

Most of the wrapping functionality is contained within the `toast` binary that is built when nimterop is installed and can be used standalone similar to how `c2nim` can be used today. In addition, nimterop also offers an API to pull in the generated Nim content directly into an application and other functionality that helps in automating the wrapping process. There is also support to statically or dynamically link to system installed libraries or downloading and building them with `autoconf` or `cmake` from a Git repo or source archive.

The nimterop wrapping functionality is still limited to C but is constantly expanding. C++ support will be added once most popular C libraries can be wrapped seamlessly. Meanwhile, `c2nim` can also be used in place of `toast` with the `c2nImport()` API call.

The goal is to make interop seamless so nimterop will focus on wrapping headers and not the outright conversion of C/C++ implementation.

## Installation

Nimterop can be installed via [Nimble](https://github.com/nim-lang/nimble):

```bash
nimble install nimterop -y
```
or:
```bash
git clone http://github.com/nimterop/nimterop && cd nimterop
nimble develop -y
nimble build -d:danger
```

This will download and install nimterop in the standard Nimble package location, typically `~/.nimble`. Once installed, it can be imported into any Nim program.

## Usage

Nimterop can be used in two ways:
- Creating a wrapper file - a `.nim` file that contains calls to the high-level API that can download and build the C library as well as generate the required Nim code to interface with the library. This wrapper file can then be imported into Nim code like any other module and it will be processed at compile time.
- Using the command line `toast` tool to generate the Nim code which can then be stored into a file and imported separately.

Any combination of the above is possible - only download, build or wrapping and nimterop avoids imposing any particular workflow.

### Build API

Creating a wrapper has two parts, the first is to setup the C library. This includes downloading it or finding it if already installed, and building it if applicable. The `getHeader()` high-level API provides all of this functionality as a convenience. The following `.nim` wrapper file is an example of using the high-level `getHeader()` API to perform all building, wrapping and linking automatically:

```nim
import nimterop/[build, cimport]

static:
  cDebug()                                                # Print wrapper to stdout

const
  baseDir = getProjectCacheDir("testwrapper")             # Download library within nimcache

getHeader(
  "header.h",                                             # The header file to wrap, full path is returned in `headerPath`
  giturl = "https://github.com/username/repo",            # Git repo URL
  dlurl = "https://website.org/download/repo-$1.tar.gz",  # Download URL for archive or raw file
  outdir = baseDir,                                       # Where to download/build/search
  conFlags = "--disable-comp --enable-feature",           # Flags to pass configure script
  cmakeFlags = "-DENABLE_STATIC_LIB=ON"                   # Flags to pass to Cmake
  altNames = "hdr"                                        # Alterate names of the library binary, full path returned in `headerLPath`
)

# Wrap headerPath as returned from getHeader() and link statically
# or dynamically depending on user input
when not defined(headerStatic):
  cImport(headerPath, recurse = true, dynlib = "headerLPath")       # Pass dynlib if not static link
else:
  cImport(headerPath, recurse = true)
```

Module documentation for the build API can be found [here](https://nimterop.github.io/nimterop/build.html). Refer to the ```tests``` directory for additional examples on how the library can be used. Also, check out the [wiki](https://github.com/nimterop/nimterop/wiki/Wrappers) for a list of all known wrappers that have been created using nimterop. They will provide real world examples of how to wrap libraries. Please do add your project once you are done so that others can benefit from your work.

__Download / Search__

The above wrapper is generic and allows the end user to control how it works. Note that `headerPath` is derived from `header.h` so if you have `SDL.h` as the argument to `getHeader()`, it generates `SDLPath` and `SDLLPath` and is controlled by `-d:SDLStatic`, `-d:SDLGit` and so forth.

- If the library is already installed in `/usr/include` then the `-d:headerStd` define to Nim can be used to instruct `getHeader()` to search for `header.h` in the standard system path.
- If the library needs to be downloaded, the user can use `-d:headerGit` to clone the source from the specified git URL or `-d:headerDL` to get the source from download URL.
  - The `-d:headerSetVer=X.Y.Z` flag can be used to specify which version to download. It is used as the tag name for Git whereas for DL, it replaces `$1` in the URL if defined.
- If no flag is provided, `getHeader()` simply looks for the library in `outdir`. The user could use Git submodules or manually download or check-in the library to that directory and `getHeader()` will use it directly.

__Pre build__

`getHeader()` provides a `headerPreBuild()` hook that gets called after the library is downloaded but before it is built. This allows for any manipulations of the source files or build scripts before build. [archive](https://github.com/genotrance/nimarchive/blob/master/nimarchive/archive.nim) has such an example.

The build API also includes various compile time helper procs that aid in file manipulation, Cmake shortcuts, library linking, etc. Refer to [build](https://nimterop.github.io/nimterop/build.html) for more details.

__Build__

Nimterop currently supports `configure` and `cmake` based building of libraries, with `cmake` taking precedence if a project supports both. Nimterop verifies that the tool selected is available and notifies the user if any issues are found. Bash is required on Windows for `configure` and the binary shipped with Git has been tested.

Flags can be specified to these tools via `getHeader()` or directly via the underlying `configure()` and `cmake()` calls. Once the build scripts are ready, `getHeader()` then calls `make()`. At every step, `getHeader()` checks for the presence of created artifacts and does not redo steps that have been successfully completed.

__Linking__

- If `-d:headerStatic` is specified, `getHeader()` will return the static library path in `headerLPath`. The wrapper writer can check for this and call `cImport()` accordingly as in the example above. If it is omitted, the dynamic library is returned in `headerLPath`.
- `getHeader()` searches for libraries based on the header name by default:
  - `libheader.so` or `libheader.a` on Linux
  - `libheader.dylib` on OSX
  - `header.dll` or `header.a` on Windows
- If a library has a different header and library binary name, `altNames` can be used to configure an alternate name of library binary.
  - For example, Bzip2 has `bzlib.h` but the library is `libbz2.so` so `altNames = "bz2"`.
  - In the example above, `altNames = "hdr"` so `getHeader()` will look for `libhdr.so`, `hdr.dll`, etc.
  - See [bzlib.nim](https://github.com/genotrance/nimarchive/blob/master/nimarchive/bzlib.nim) for an example.
- [lzma.nim](https://github.com/nimterop/nimterop/blob/master/tests/lzma.nim) is an example of a library that allows both static and dynamic linking.

__User control__

The `-d:xxxYYY` Nim define flags have already been described above and can be specified on the command line or in a nim.cfg file. It is also possible to specify them within the wrapper itself using `setDefines()` if required. Further, all defines, regardless of how they are specified, can be generically checked using `isDefined()`.

If more fine-tuned control is desired over the build process, it is possible to manually control all steps that `getHeader()` performs by directly using the API provided by [build](https://nimterop.github.io/nimterop/build.html). Note also that there is no requirement to use these APIs to setup the library. Any other established mechanisms can be used to do so any limitations imposed by Nimterop are unintentional and feedback is most welcome.

### Wrapper API

Once the C library is setup, the next step is to generate code that inform Nim of all the types and functions that are available. Following is a simple example covering the API:

```nim
import nimterop/cimport

static:
  cDebug()
  cDisableCaching()           # Regenerate Nim wrapper every time

cDefine("HAS_ABC")            # Set #defines for preprocessor and compiler
cDefine("HAS_ABC", "DEF")

cIncludeDir("clib/include")   # Setup any include directories

cImport("clib.h")             # Generate wrappers for header specified

cCompile("clib/src/*.c")      # Compile in any implementation source files
```

Module documentation for the wrapper API can be found [here](https://nimterop.github.io/nimterop/cimport.html).

__Preprocessing__

In order to leverage the preprocessor, certain projects might need `cDefine()` calls to set `#define` values. Simpler library may have documentation that cover this but larger ones will rely on build tools that discover and set values in a `config.h` which is loaded with `#include`. Projects might also require some `cIncludeDir()` calls to specify paths to directories that contain other headers. This might be within the library or refer to another library.

The wrapper API always runs headers through the C preprocessor before wrapping. Details on why are discussed further down.

By default, the `$CC` environment variable is used for the compiler path. If not found, `toast` defaults to `gcc`.

__Wrapping__

The `cImport()` call invokes the `toast` binary with appropriate command line flags including any `cDefine()` and `cInclude()` parameters configured. The output of `toast` is then pulled into the module as Nim code and printed if `cDebug()` is specified. This allows for an end user to simply import the wrapper into their code and access the library API as Nim types and procs. Output is cached to save time on subsequent runs. It is also possible to just redirect the output to a file and import that instead if preferred.

The `recurse` flag can be set to enable the recursion capability which runs through all #include files in the header. If the library needs to be dyamically linked using Nim's `dynlib` pragma, the `dynlib = "constName"` attribute can be set to generate wrappers that load the DLL automatically. Without `dynlib`, static link is assumed so it is the user's responsibility to link the library.

There may be cases where the wrapper generated by `toast` for certain types or procs is not preferred, or may be skipped or altogether wrong due to limitations or bugs. In these instances, the `cOverride()` macro can be used to define consts, types or procs to use in place of the wrapper generated output. `cImport()` will forward this information to `toast` and the values will be inserted in context in the generated wrapper. This allows wrapper authors to work around tool limitations or to improve the wrapper output - say change `ptr X` to `var X` or to create more Nim friendly types or proc signatures.

Several C libraries also use leading and/or trailing `_` in identifiers and since Nim does not allow this, the `cPlugin()` macro can be used to modify such symbols or `cSkipSymbol()` them altogether. Instead of a full `cPlugin()` section, it might also be preferred to set `flags = "-E_ -F_"` to the `cImport()` call to trim out such characters. These features can also be used to remove common prefixes like `SDL_` to generate a cleaner wrapper. `cPlugin()` is real Nim code though so anything Nim allows is fair game. Note that `cPlugin()` overrides any `-E -F` flags. Also, behind the scenes, `cOverride()` is communicated to `toast` via `cPlugin()`.

If the same `cPlugin()` is needed in multiple wrapper files, the code can be moved into a standalone file and be used with the `cPluginPath()` call.

Lastly, `c2nImport()` provides access to calling `c2nim` from the wrapper instead of `toast`. Note that `c2nImport()` does not use any of the above described features like `cPlugin()` and needs to be controlled with the `flags` param.

__Compiling source__

The job of building and compiling the underlying C library is best left to the build mechanism selected by the library author so using `getHeader()` is recommended. For simpler projects with a few `.c` files though, `cCompile()` should be more than enough. It is not recommended for larger projects which heavily rely on functionality offered by build tools. Recreating reliable logic in Nim can be tedious and one can expect minimal support from that author if their tested build mechanism is not used.

### Docs API

Nimterop also provides a [docs](https://nimterop.github.io/nimterop/docs.html) API which can be used to generate documentation from the generated wrappers. This can be added as a task in the `.nimble` or `.nims` file for convenience. See [nimarchive.nimble](https://github.com/genotrance/nimarchive/blob/master/nimarchive.nimble) for an example.

### Command line API

The `toast` binary can also be used directly on the CLI, similar to `c2nim`. The `cPlugin()` interface

Note: unlike the wrapper API, the `-p | --preprocess` flag is not enabled by default but is *highly* recommended.

```
> toast -h
Usage:
  main [optional-params] C/C++ source/header
Options:
  -h, --help                              print this cligen-erated help
  --help-syntax                           advanced: prepend,plurals,..
  -k, --check          bool      false    check generated wrapper with compiler
  -C=, --convention=   string    "cdecl"  calling convention for wrapped procs
  -d, --debug          bool      false    enable debug output
  -D=, --defines=      strings   {}       definitions to pass to preprocessor
  -l=, --dynlib=       string    ""       import symbols from library in specified Nim string
  -f=, --feature=      Features  {}       flags to enable experimental features
  -H, --includeHeader  bool      false    add {.header.} pragma to wrapper
  -I=, --includeDirs=  strings   {}       include directory to pass to preprocessor
  -m=, --mode=         string    ""       language parser: c or cpp
  --nim=               string    "nim"    use a particular Nim executable
  -c, --nocomments     bool      false    exclude top-level comments from output
  -o=, --output=       string    ""       file to output content
  -a, --past           bool      false    print AST output
  -g, --pgrammar       bool      false    print grammar
  --pluginSourcePath=  string    ""       nim file to build and load as a plugin
  -n, --pnim           bool      false    print Nim output
  -E=, --prefix=       strings   {}       strip prefix from identifiers
  -p, --preprocess     bool      false    run preprocessor on header
  -r, --recurse        bool      false    process #include files
  -G=, --replace=      strings   {}       replace X with Y in identifiers, X1=Y1,X2=Y2, @X for regex
  -s, --stub           bool      false    stub out undefined type references as objects
  -F=, --suffix=       strings   {}       strip suffix from identifiers
  -O=, --symOverride=  strings   {}       skip generating specified symbols
```

## Why nimterop

Nim has one of the best FFI you can find - importing C/C++ is supported out of the box. All you need to provide is type and proc definitions for Nim to interop with C/C++ binaries. Generation of these wrappers is easy for simple libraries but can quickly get out of hand. [c2nim](https://github.com/nim-lang/c2nim) greatly helps here by parsing and converting C/C++ into Nim but is limited due to the complex and constantly evolving C/C++ grammar. [nimgen](https://github.com/genotrance/nimgen) mainly focused on automating the wrapping process with `c2nim` and filled some holes but is again limited to `c2nim` capabilities.

The goal of nimterop is to leverage the [tree-sitter](http://tree-sitter.github.io/tree-sitter/) engine to parse C/C++ code and then convert relevant portions of the AST into Nim definitions. [tree-sitter](https://github.com/tree-sitter) is a Github sponsored project that can parse a variety of languages into an AST which is then leveraged by the [Atom](https://atom.io/) editor for syntax highlighting and code folding. The advantages of this approach are multifold:
- Benefit from the tree-sitter community's ongoing investment into language parsing
- Wrap what is recognized in the AST rather than completely failing due to parsing errors

The tree-sitter library is limited though - it may fail on some advanced language constructs but is designed to handle them gracefully since it is expected to have bad code while actively typing in an editor. When an error is detected, tree-sitter includes an ERROR node at that location in the AST. At this time, `cImport()` will complain and continue if it encounters any errors. Depending on how severe the errors are, compilation may succeed or fail. Glaring issues will be communicated to the tree-sitter team but their goals may not always align with those of this project.

It is debatable whether a syntax highlighting engine like `tree-sitter` is the most reliable method to convert C code into AST. However, it is lightweight, cross-platform with no dependencies and handles error conditions gracefully. It has produced usable wrappers for C libraries though things could get murky when considering C++ but that will be a topic for another day. Nimterop relies heavily on the preprocessor, as discussed next, so having an engine which can run anywhere has been worth the compromise. Only time will tell though.

__Preprocessing__

The wrapper API always runs headers through the C preprocessor before wrapping, unlike the command line interface where the `-p | --preprocess` flag is not set by default but *highly* recommended. This is because almost all platform, compiler and package discovery is handled by build tools like `configure` and `cmake` which then use preprocessor `#define` values to tweak what C code is applicable for that platform. While parsing preprocessor macros is possible in tools like `toast`, given how dependent the `#ifdef` branches are on values provided by these and many other build tools, preprocessing seems is best left to them than attempting to self-discover or intercept that information.

Nimterop is still able to wrap most relevant `#define` like numbers and strings thanks to `gcc -E` providing the sufficient detail in its output. Many C libraries also use `#define` templates for some of their user facing API and providing that functionality in Nim is on the Nimterop roadmap.

The con of this approach of delegating to the preprocessor is that the Nim wrapper generated by Nimterop is no longer portable despite being Nim code. A wrapper rendered on Linux might not work on Windows since some APIs may not be available or inappropriate, integer sizes might be wrong, types could be missing and many other possible issues. But none of this is easily or accurately known at the Nim level since it would require input from the build tools which already work well with the preprocessor or have to be completely reimplemented within Nim. Neither approach that bypasses such build tools would be supported by the library author.

This is part of the reason why Nimterop provides a wrapper API so that the generation of wrappers is Nim code that can be rendered as part of the build process on the target platform. It helps to think of Nimterop as a build time tool like `cmake` that renders artifacts on the target rather than a tool whose generated artifacts should be checked into source control. Regardless, both the wrapper API and the `toast` command line still allow saving the wrapper output to a file to be stored in source control since it might work well enough for many projects.

## Credits

Nimterop depends on [tree-sitter](http://tree-sitter.github.io/tree-sitter/) and all licensing terms of [tree-sitter](https://github.com/tree-sitter/tree-sitter/blob/master/LICENSE) apply to the usage of this package. The tree-sitter functionality is pulled and wrapped using nimterop itself.

## Feedback

Nimterop is a work in progress and any feedback or suggestions are welcome. It is hosted on [GitHub](https://github.com/nimterop/nimterop) with an MIT license so issues, forks and PRs are most appreciated.
