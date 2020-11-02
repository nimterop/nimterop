# Nimterop Change History

## Version 0.7.0

This is a minor release that switches from using absolute paths for `cImport()` dynlib parameters to relative paths. This allows nimterop based projects to create binaries that can move around, along with their library dependencies. While this is not a new feature per se, it is potentially a breaking change.

Note that `getHeader()` still returns absolute paths for `xxxLPath` but when passed into `cImport()`, it gets converted to relative paths on Windows and sets `RPATH` on posix systems. This is accomplished with the new `setupDynlib()` proc.

See the full list of changes here:

https://github.com/nimterop/nimterop/compare/v0.6.13...v0.7.0

## Version 0.6.0

This release adds the ability to download precompiled binaries from [Conan.io](https://conan.io/center) and Julia's [BinaryBuilder.org](https://binarybuilder.org). This alleviates the  headache of searching and downloading libraries manually both for wrapper writers as well as end users. There are some known limitations but it should prove to become more useful as these sites expand their capabilities.

Conan.io shared builds tend to have all dependencies statically linked into the binary so a single so/dll/dylib has everything. For Conan.io static builds and all libraries on BinaryBuilder.org, dependencies are also downloaded and linked as needed. They are returned in the new `const xxxLDeps` in case wrapper writers need it for some reason.

Known concerns:
- Conan.io only compiles Windows builds with Microsoft's VC++ compiler so static .lib files may not always work with MinGW on Windows.
- Conan.io compiles all Mac builds on OSX 10.14 so older versions of the OS will grumble when statically linking these libraries.
- BinaryBuilder.org does not include static libs for all their projects.

Refer to the documentation for `getHeader()` for details on how to use this new capability.

See the full list of changes here:

https://github.com/nimterop/nimterop/compare/v0.5.9...v0.6.13

### Breaking changes

- The legacy algorithm has been removed as promised. `ast2` is now the default and wrappers no longer need to explicitly specify `-f:ast2` in order to use it.

- All shared libraries installed by `getHeader()` will now get copied into the `libdir` parameter specified. If left blank, `libdir` will default to the directory where the executable binary gets created (outdir). While this is not really a breaking change, it is a change in behavior compared to older versions of nimterop. Note that `Std` libraries are not copied over. [#154][i154]

- `git.nim` has been removed. This module was an artifact from the early days and was renamed to `build.nim` back in v0.2.0.

- Nameless enum values are no longer typed to the made-up enum type name, they are instead typed as `cint` to match the underlying type. This allows using such enums without having to depend on the made-up name which could change if enum ordering changes upstream. [#236][i236] (since v0.6.1)

- Static libraries installed and linked with `getHeader()` now have their `{.passL.}` pragmas forwarded to the generated wrapper. This might lead to link errors in existing wrappers if other dependencies are specified with `{.passL.}` calls and the order of linking is wrong. This can be fixed by changing such explicit `{.passL.}` calls with `cPassL()` which will forward the link call to the generated wrapper as well. (since v0.6.5)

### New functionality

- `getHeader()` now detects and links against `.lib` files as part of enabling Conan.io. Not all `.lib` files are compatible with MinGW as already stated above but for those that work, this is a required capability.

- The `dynlib` command line parameter to `toast` and `cImport()` can also be the path to a shared library (dll|so|dylib) in place of a Nim const string containing the path. This allows for the traditional use case of passing `"xxxLPath"` to `cImport()` as well as simply passing the path to the library on the command line as is. This allows the creation of standalone cached wrappers as well as the usage of the `--check` and the `--stub` functionality that `toast` provides via `cImport()`.

- `gitPull()` now checks if an existing repository is at the `checkout` value specified. If not, it will pull the latest changes and checkout the specified commit, tag or branch.

- `cImport()` can now write the generated wrapper output to a user-defined file with the `nimFile` param. [#127][i127] (since v0.6.1)

- Nimterop now supports anonymous nested structs/unions but it only works correctly for unions when `noHeader` is turned off (the default). This is because Nim does not support nested structs/unions and is unaware of the underlying memory structure. [#237][i237] (since v0.6.1)

- `xxxJBB` now allows for customizing the base location to search packages with the `jbbFlags` param to `getHeader()`. Specifying `giturl=xxx` where `xxx` could be a full Git URL or just the username for Github.com allows changing the default Git repo. In addition, `url=xxx` is also supported to download project info and binaries compiled with BinaryBuilder.org but hosted at another non-Git location. (since v0.6.3)

- It is now possible to exclude the contents of specific files or entire directories from the wrapped output using `--exclude | -X` with `toast` or `cExclude()` from a wrapper. This might be required when a header uses `#include` to pull in external dependencies. E.g. `sciter` has a `#include <gtk/gtk.h>` which pulls in the entire GTK ecosystem which is needed for successful preprocessing but we do not want to include those headers in the wrapped output when using `--recurse | -r`. (since v0.6.4)

- All `cDefine()`, `cIncludeDir()` and `cCompile()` calls now forward relevant pragmas into the generated wrapper further enabling standalone wrappers. [#239][i239]

- Added `cPassC()` and `cPassL()` to forward C/C++ compilation pragmas into the generated wrapper. These should be used in place of `{.passC.}` and `{.passL.}` and need to be called before `cImport()` to take effect. (since v0.6.5)

- Added `--compile`, `--passC` and `--passL` flags to `toast` to enable the previous two improvements. (since v0.6.5)

- Added `renderPragma()` to create pragmas inline in case `cImport()` is not being used. (since v0.6.5)

- `xxxConan` and `xxxJBB` now allow skipping required dependencies by specifying `skip=pkg1,pkg2` to the `conanFlags` and `jbbFlags` params to `getHeader()`. (since v0.6.6)

### Other improvements

- Generated wrappers no longer depend on nimterop being present - no more `import nimterop/types`. Supporting code is directly included in the wrapper output and only when required. E.g. enum macro is only included if wrapper contains enums. [#125][i125] (since v0.6.1)

- `cImport()` now includes wrapper output from a file rather than inline. Errors in generated wrappers will no longer point to a line in `macros.nim` making debugging easier. (since v0.6.1)

- `cIncludeDir()` can now accept a `seq[string]` of directories and an optional `exclude` param which sets those include directories to not be included in the wrapped output. (since v0.6.4)

- `cDefine()` can now accept a `seq[string]` of values. (since v0.6.5)

- Enabled support for musl systems. (since v0.6.12)

## Version 0.5.0

This release introduces a new backend for wrapper generation dubbed `ast2` that leverages the Nim compiler AST and renderer. The new design simplifies feature development and already includes all the functionality of the legacy algorithm plus fixes for several open issues.

The new backend can be leveraged with the `-f:ast2` flag to `toast` or `flags = "-f:ast2"` to `cImport()`. The legacy algorithm will be the default backend for this release but no new functionality or bugfixes are expected going forward. Usage of the legacy algorithm will display a *deprecated* hint to encourage users to test their wrappers with `-f:ast2` and remove any overrides that the new algorithm supports.

Version 0.6.0 of Nimterop will make `ast2` the default backend and the legacy algorithm will be removed altogether.

See the full list of changes here:

https://github.com/nimterop/nimterop/compare/v0.4.4...v0.5.4

### Breaking changes

- Nimterop used to default to C++ mode for preprocessing and tree-sitter parsing in all cases unless explicitly informed to use C mode. This has been changed and is now detected based on the file extension. This means some existing wrappers could break since they might contain C++ code or include C++ headers like `#include <string>` which will not work in C mode. Explicitly setting `mode = "cpp"` or `-mcpp` should fix such issues. [#176][i176]

- Enums were originally being mapped to `distint int` - this has been changed to `distinct cint` since the sizes are incorrect on 64-bit and is especially noticeable when types or unions have enum fields.

- `static inline` functions are no longer wrapped by the legacy backend. The `ast2` backend correctly generates wrappers for such functions but they are only generated when `--noHeader | -H` is not in effect. This is because such functions do not exist in the binary and can only be referenced when the header is compiled in.

- Support for Nim v0.19.6 has been dropped and the test matrix now covers v0.20.2, v1.0.6, v1.2.0 and devel.

### New functionality

- Nimterop can now skip generating the `{.header.}` pragma when the `--noHeader | -H` flag is used. This skips the header file `#include` in the generated code and allows creation of wrappers that do not require presence of the header during compile time. Note that `static inline` functions will only be wrapped when the header is compiled in. This change applies to both `ast2` and the legacy backend, although `ast2` can also generate wrappers with both `{.header.}` and `{.dynlib.}` in effect enabling type size checking with `-d:checkAbi`. More information is available in the [README.md](README.md). [#169][i169]

- `ast2` includes support for various C constructs that were issues with the legacy backend. These changes should reduce the reliance on `cOverride()` and existing wrappers should attempt to clean up such sections where possible.
  - N-dimensional arrays and pointers - [#54][i54]
  - Synomyms for types - [#74][i74]
  - Varargs support - [#76][i76]
  - Nested structs, unions and enums - [#137][i137] [#147][i147]
  - Forward declarations of types - [#148][i148]
  - Nested function pointers - [#155][i155] [#156][i156]
  - Various enum fixes - [#159][i159] [#171][i171]
  - Map `int arr[]` to `arr: UncheckedArray[cint]` - [#174][i174]
  - Global variables including arrays and procs (since v0.5.4)

- `ast2` also includes an advanced expression parser that can reliably handle constructs typically seen with `#define` statements and enumeration values:
  - Integers + integer like expressions (hex, octal, suffixes)
  - Floating point expressions
  - Strings and character literals, including C's escape characters
  - Math operators `+ - / *`
  - Some Unary operators `- ! ~`
  - Any identifiers
  - C type descriptors `int char` etc
  - Boolean values `true false`
  - Shift, cast, math or sizeof expressions
  - Most type coercions

- Wrappers can now point to an external plugin file with `cPluginPath()` instead of having to declaring plugins inline with `cPlugin()`. This allows multiple wrappers to share the same plugin. [#181][i181]

- `cImport()` adds support for importing multiple headers in a single call - this enables support for libraries that have many header files that include shared headers and typically cannot be imported in multiple `cImport()` calls since it results in duplicate symbols. Calling `toast` with multiple headers uses the same algorithm.

- `ast2` now creates Nim doc comments instead of reqular comments which get rendered when the wrapper is run through `nim doc` or the `buildDocs()` API. [#197][i197]

- `toast` now includes `--replace | -G` to manipulate identifier names beyond `--prefix` and `--suffix`. `-G:X=Y` replaces X with Y and `-G:@_[_]+=_` replaces multiple `_` with a single instance using the `@` prefix to enable regular expressions.

- `toast` also includes `--typeMap | -T` to map C types to another type. E.g. `--typeMap:GLint64=int64` generates a wrapper where all instances of `GLint64` are remapped to the Nim type `int64` and `GLint64` is not defined. (since v0.5.2)

- CLI flags can now be specified one or more per line in a file and path provided to `toast`. They will be expanded in place. [#196][i196] (since v0.5.3)

- Nimterop is now able to detect Nim configuration of projects and can better handle cases where defaults such as `nimcacheDir` or `nimblePath` are overridden. This especially enables better interop with workflows that do not depend on Nimble. [#151][i151] [#153][i153]

- Nimterop defaults to `cmake`, followed by `autoconf` for building libraries with `getHeader()`. It is now possible to change the order of discovery with the `buildType` value. [#200][i200]

[i54]: https://github.com/nimterop/nimterop/issues/54
[i74]: https://github.com/nimterop/nimterop/issues/74
[i76]: https://github.com/nimterop/nimterop/issues/76
[i125]: https://github.com/nimterop/nimterop/issues/125
[i127]: https://github.com/nimterop/nimterop/issues/127
[i137]: https://github.com/nimterop/nimterop/issues/137
[i147]: https://github.com/nimterop/nimterop/issues/147
[i148]: https://github.com/nimterop/nimterop/issues/148
[i151]: https://github.com/nimterop/nimterop/issues/151
[i153]: https://github.com/nimterop/nimterop/issues/153
[i154]: https://github.com/nimterop/nimterop/issues/154
[i155]: https://github.com/nimterop/nimterop/issues/155
[i156]: https://github.com/nimterop/nimterop/issues/156
[i159]: https://github.com/nimterop/nimterop/issues/159
[i169]: https://github.com/nimterop/nimterop/issues/169
[i171]: https://github.com/nimterop/nimterop/issues/171
[i174]: https://github.com/nimterop/nimterop/issues/174
[i176]: https://github.com/nimterop/nimterop/issues/176
[i181]: https://github.com/nimterop/nimterop/issues/181
[i196]: https://github.com/nimterop/nimterop/issues/196
[i197]: https://github.com/nimterop/nimterop/issues/197
[i200]: https://github.com/nimterop/nimterop/issues/200
[i236]: https://github.com/nimterop/nimterop/issues/236
[i237]: https://github.com/nimterop/nimterop/issues/237
[i239]: https://github.com/nimterop/nimterop/issues/239
