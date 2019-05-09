[![Chat on Gitter](https://badges.gitter.im/gitterHQ/gitter.png)](https://gitter.im/nimterop/Lobby)
[![Build status](https://ci.appveyor.com/api/projects/status/hol1yvqbp6hq4ao8/branch/master?svg=true)](https://ci.appveyor.com/project/genotrance/nimterop-8jcj7/branch/master)
[![Build Status](https://travis-ci.org/nimterop/nimterop.svg?branch=master)](https://travis-ci.org/nimterop/nimterop)

Detailed documentation [here](https://nimterop.github.io/nimterop/theindex.html).

Nimterop is a [Nim](https://nim-lang.org/) package that aims to make C/C++ interop seamless

Nim has one of the best FFI you can find - importing C/C++ is supported out of the box. All you need to provide is type and proc definitions for Nim to interop with C/C++ binaries. Generation of these wrappers is easy for simple libraries but quickly gets out of hand. [c2nim](https://github.com/nim-lang/c2nim) greatly helps here by parsing and converting C/C++ into Nim but is limited due to the complex and constantly evolving C/C++ grammar. [nimgen](https://github.com/genotrance/nimgen) mainly focuses on automating the wrapping process and fills some holes but is again limited to c2nim's capabilities.

The goal of nimterop is to leverage the [tree-sitter](http://tree-sitter.github.io/tree-sitter/) engine to parse C/C++ code and then convert relevant portions of the AST into Nim definitions. [tree-sitter](https://github.com/tree-sitter) is a Github sponsored project that can parse a variety of languages into an AST which is then leveraged by the [Atom](https://atom.io/) editor for syntax highlighting and code folding. The advantages of this approach are multifold:
- Benefit from the tree-sitter community's investment into language parsing
- Wrap what is recognized in the AST rather than completely failing due to parsing errors
- Avoid depending on Nim compiler API which is evolving constantly and makes backwards compatibility a bit challenging

Most of the functionality is contained within the `toast` binary that is built when nimterop is installed and can be used standalone similar to how c2nim can be used today. In addition, nimterop also offers an API to pull in the generated Nim content directly into an application.

The nimterop feature set is still limited to C but is expanding rapidly. C++ support will be added once most popular C libraries can be wrapped seamlessly.

Nimterop has seen some adoption within the community and the simplicity and success of this approach justifies additional investment of time and effort. Regardless, the goal is to make interop seamless so nimterop will focus on wrapping headers and not the outright conversion of C/C++ implementation.

__Installation__

Nimterop can be installed via [Nimble](https://github.com/nim-lang/nimble):

```bash
nimble install nimterop -y
```
or:
```bash
git clone http://github.com/nimterop/nimterop && cd nimterop
nimble develop -y
nimble build
```

This will download and install nimterop in the standard Nimble package location, typically `~/.nimble`. Once installed, it can be imported into any Nim program. Note that the `~/.nimble/bin` directory needs to be added to the `PATH` for nimterop to work.

__Usage__

```nim
import nimterop/cimport

static:
  cDebug()
cDefine("HAS_ABC")
cDefine("HAS_ABC", "DEF")
cIncludeDir("clib/include")
cImport("clib.h")

cCompile("clib/src/*.c")
```

Check out [template.nim](https://github.com/nimterop/nimterop/blob/master/nimterop/template.nim) as a starting point for wrapping a new library. The template can be copied and trimmed down and modified as required.

Refer to the ```tests``` directory for examples on how the library can be used.

The `toast` binary can also be used directly on the CLI:

```
toast -h
Usage:
  main [optional-params] C/C++ source/header
  Options(opt-arg sep :|=|spc):
  -h, --help                           print this cligen-erated help
  --help-syntax                        advanced: prepend, multi-val,..
  -p, --preprocess     bool     false  run preprocessor on header
  -a, --past           bool     false  print AST output
  -n, --pnim           bool     false  print Nim output
  -r, --recurse        bool     false  process #include files
  -c, --nocomments     bool     false  exclude top-level comments from output
  -D=, --defines=      strings  {}     definitions to pass to preprocessor
  -I=, --includeDirs=  strings  {}     include directory to pass to preprocessor
  -l=, --dynlib=       string   ""     Import symbols from library in specified Nim string
  -O=, --symOverride=  strings  {}     skip generating specified symbols
  --pluginSourcePath=  string   ""     Nim file to build and load as a plugin
  -d, --debug          bool     false  enable debug output
  -m=, --mode=         string   "cpp"  language parser: c or cpp
  -g, --pgrammar       bool     false  print grammar
```

__Implementation Details__

In order to use the tree-sitter C library, it has to be compiled into a separate binary called `toast` (to AST) since the Nim VM doesn't yet support FFI. `toast` takes a C/C++ file and runs it through the tree-sitter API which returns an AST data structure. This can then be printed out to stdout in a Lisp S-Expression format or the relevant Nim wrapper output. This content can be saved to a `.nim` file and imported if so desired.

Alternatively, the `cImport()` macro allows easier creation of wrappers in code. It runs `toast` on the specified header file and injects the generated wrapper content into the application at compile time. A few other helper procs are provided to influence this process. Output is cached to save time on subsequent runs.

`toast` can also be used to run the header through the preprocessor which cleans up the code considerably. Along with the recursion capability which runs through all #include files, one large simpler header file can be created which can then be processed with `toast` or even `c2nim` if so desired.

The tree-sitter library is limited as well - it may fail on some advanced language constructs but is designed to handle them gracefully since it is expected to have bad code while actively typing in an editor. When an error is detected, tree-sitter includes an ERROR node at that location in the AST. At this time, `cImport()` will complain and continue if it encounters any errors. Depending on how severe the errors are, compilation may succeed or fail. Glaring issues will be communicated to the tree-sitter team but their goals may not always align with those of this project.

__Credits__

Nimterop depends on [tree-sitter](http://tree-sitter.github.io/tree-sitter/) and all licensing terms of [tree-sitter](https://github.com/tree-sitter/tree-sitter/blob/master/LICENSE) apply to the usage of this package. The tree-sitter functionality is pulled and wrapped using nimterop itself.

__Feedback__

Nimterop is a work in progress and any feedback or suggestions are welcome. It is hosted on [GitHub](https://github.com/nimterop/nimterop) with an MIT license so issues, forks and PRs are most appreciated.
