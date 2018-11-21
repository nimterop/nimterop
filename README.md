Nimterop is a [Nim](https://nim-lang.org/) package that aims to make C/C++ interop seamless

Nim has one of the best FFI you can find - importing C/C++ is supported out of the box. All you need to provide is type and proc definitions for Nim to interop with C/C++ binaries. Generation of these wrappers is easy for simple libraries but quickly gets out of hand. [c2nim](https://github.com/nim-lang/c2nim) greatly helps here by parsing and converting C/C++ into Nim but is limited due to the complex and constantly evolving C/C++ grammar. [nimgen](https://github.com/genotrance/nimgen) mainly focuses on automating the wrapping process and fills some holes but is again limited to c2nim's capabilities.

The goal of nimterop is to leverage the [tree-sitter](http://tree-sitter.github.io/tree-sitter/) engine to parse C/C++ code and then convert relevant portions of the AST into Nim definitions using compile-time macros. [tree-sitter](https://github.com/tree-sitter) is a Github sponsored project that can parse a variety of languages into an AST which is then leveraged by the [Atom](https://atom.io/) editor for syntax highlighting and code folding. The advantages of this approach are multifold:
- Benefit from the tree-sitter community's investment into language parsing
- Leverage Nim macros which are a user API and relatively stable
- Avoid depending on Nim compiler API which is evolving constantly

The nimterop feature set is still limited when compared with c2nim. Supported language constructs include:
- `#define NAME VALUE` where `VALUE` is a number (int, float, hex)
- `struct X`, `typedef struct`, `enum X`, `typedef enum`
- Functions with primitive types, structs, enums and typedef structs/enums as params and return values

Given the simplicity and success of this approach so far, it seems feasible to continue on for more complex code. The goal is to make interop seamless so nimterop will focus on wrapping headers and not the outright conversion of C/C++ implementation.

C++ constructs are still TBD depending on the results of the C interop.

__Installation__

Nimterop can be installed via [Nimble](https://github.com/nim-lang/nimble):

```
> nimble install http://github.com/genotrance/nimtreesitter?subdir=treesitter
> nimble install http://github.com/genotrance/nimtreesitter?subdir=treesitter_c
> nimble install http://github.com/genotrance/nimtreesitter?subdir=treesitter_cpp

> nimble install http://github.com/genotrance/nimterop
```

This will download and install nimterop in the standard Nimble package location, typically ~/.nimble. Once installed, it can be imported into any Nim program.

__Usage__

```nim
import nimterop/cimport

cDebug()
cDefine("HAS_ABC")
cDefine("HAS_ABC", "DEF")
cIncludeDir("clib/include")
cImport("clib.h")

cCompile("clib/src/*.c")
```

Refer to the ```tests``` directory for examples on how the library can be used.

__Documentation__

Detailed documentation is still forthcoming.

`cDebug()` - enable debug messages

`cDefine()` - `#define` an identifer that is forwarded to the compiler using `{.passC: "-DXXX".}` as well as _eventually_ used in processing `#ifdef` statements

`cIncludeDir()` - add an include directory that is forwarded to the compiler using `{.passC: "-IXXX".}` as well as searched for files included using `cImport()` statements and following `cIncludeDir()` statements

`cImport()` - import all supported definitions from specific import header file

`gitPull()` - pull a git repository prior to C/C++ interop

__Implementation Details__

In order to use the tree-sitter C library at compile-time, it has to be compiled into a separate binary called `toast` (to AST) since the Nim VM doesn't yet support FFI. `toast` takes a C/C++ file and runs it through the tree-sitter API which returns an AST data structure. This is then printed out to stdout in a Lisp S-Expression format.

The `cImport()` proc runs `toast` on the specified header file and parses the resulting S-Expression back into an AST data structure at compile time. This AST is then processed to generate the relevant Nim definitions to interop with the code accordingly. A few other helper procs are provided to influence this process.

The tree-sitter library is limited as well - it may fail on some advanced language constructs but is designed to handle them gracefully since it is expected to have bad code while actively typing in an editor. When an error is detected, tree-sitter includes an ERROR node at that location in the AST. At this time, `cImport()` will complain and continue if it encounters any errors. Depending on how severe the errors are, compilation may succeed or fail. Glaring issues will be communicated to the tree-sitter team but their goals may not always align with those of this project.

__Credits__

Nimterop depends on [tree-sitter](http://tree-sitter.github.io/tree-sitter/) and all licensing terms of [tree-sitter](https://github.com/tree-sitter/tree-sitter/blob/master/LICENSE) apply to the usage of this package. Interestingly, the tree-sitter functionality is [wrapped](https://github.com/genotrance/nimtreesitter) using c2nim and nimgen at this time. Depending on the success of this project, those could perhaps be bootstrapped using nimterop eventually.

__Feedback__

Nimterop is a work in progress and any feedback or suggestions are welcome. It is hosted on [GitHub](https://github.com/genotrance/nimterop) with an MIT license so issues, forks and PRs are most appreciated.
