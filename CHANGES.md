# Nimterop Change History

## Version 0.5.0

This release introduces a new backend for wrapper generation dubbed `ast2` that leverages the Nim compiler AST and renderer. The new design simplifies feature development and already includes all the functionality of the legacy algorithm plus fixes for several open issues.

The new backend can be leveraged with the `-f:ast2` flag to `toast` or `flags = "-f:ast2"` to `cImport()`. The legacy algorithm will be the default backend for this release but no new functionality or bugfixes are expected going forward. Usage of the legacy algorithm will display a *deprecated* hint to encourage users to test their wrappers with `-f:ast2` and remove any overrides that the new algorithm supports.

Version 0.6.0 of Nimterop will make `ast2` the default backend and the legacy algorithm will be removed altogether.

See the full list of changes here:

https://github.com/nimterop/nimterop/compare/v0.4.4...v0.5.0

### Breaking changes

- Nimterop now skips generating the `{.header.}` pragma by default in non-dynlib mode. This skips the header file `#include` in the generated code and allows creation of wrappers that do not require presence of the header during compile time. There are cases where this will not work so the `--includeHeader | -H` flag is available to revert to the legacy behavior when required. This change applies to both `ast2` and the legacy backend so if an existing wrapper breaks, test it with `-H` to see if it starts working again. [#169][i169]

- Nimterop defaulted to C++ mode for preprocessing and tree-sitter parsing in all cases unless explicitly informed to use C mode. This has been changed and is now detected based on the file extension. This means some existing wrappers could break since they might contain C++ code or include C++ headers like `#include <string>` which will not work in C mode. Explicitly setting `mode = "cpp"` or `-mcpp` should fix such issues. [#176][i176]

- Enums were originally being mapped to `distint int` - this has been changed to `distinct cint` since the sizes are incorrect on 64-bit and is especially noticeable when types or unions have enum fields.

- `static inline` functions are no longer wrapped by the legacy backend. The `ast2` backend correctly generates wrappers for such functions but they are only generated when `--includeHeader | -H` is in effect. This is because such functions do not exist in the binary and can only be referenced when the header is compiled in.

- Support for Nim v0.19.6 has been dropped and the test matrix now covers v0.20.2, v1.0.6, v1.2.0 and devel.

### New functionality

- `ast2` includes support for various C constructs that were issues with the legacy backend. These changes should reduce the reliance on `cOverride()` and existing wrappers should attempt to clean up such sections where possible.
  - N-dimensional arrays and pointers - [#54][i54]
  - Synomyms for types - [#74][i74]
  - Varargs support - [#76][i76]
  - Nested structs, unions and enums - [#137][i137] [#147][i147]
  - Forward declarations of types - [#148][i148]
  - Nested function pointers - [#155][i155] [#156][i156]
  - Various enum fixes - [#159][i159] [#171][i171]
  - Map `int arr[]` to `arr: UncheckedArray[cint]` - [#174][i174]

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

- Nimterop is now able to detect Nim configuration of projects and can better handle cases where defaults such as `nimcacheDir` or `nimblePath` are overridden. This especially enables better interop with workflows that do not depend on Nimble. [#151][i151] [#153][i153]

- Nimterop defaults to `cmake`, followed by `autoconf` for building libraries with `getHeader()`. It is now possible to change the order of discovery with the `buildType` value. [#200][i200]

[i54]: https://github.com/nimterop/nimterop/issues/54
[i74]: https://github.com/nimterop/nimterop/issues/74
[i76]: https://github.com/nimterop/nimterop/issues/76
[i137]: https://github.com/nimterop/nimterop/issues/137
[i147]: https://github.com/nimterop/nimterop/issues/147
[i148]: https://github.com/nimterop/nimterop/issues/148
[i151]: https://github.com/nimterop/nimterop/issues/151
[i153]: https://github.com/nimterop/nimterop/issues/153
[i155]: https://github.com/nimterop/nimterop/issues/155
[i156]: https://github.com/nimterop/nimterop/issues/156
[i159]: https://github.com/nimterop/nimterop/issues/159
[i169]: https://github.com/nimterop/nimterop/issues/169
[i171]: https://github.com/nimterop/nimterop/issues/171
[i174]: https://github.com/nimterop/nimterop/issues/174
[i176]: https://github.com/nimterop/nimterop/issues/176
[i181]: https://github.com/nimterop/nimterop/issues/181
[i197]: https://github.com/nimterop/nimterop/issues/197
[i200]: https://github.com/nimterop/nimterop/issues/200