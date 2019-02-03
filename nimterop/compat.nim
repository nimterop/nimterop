#[
module for backward compatibility
put everything that requires `when (NimMajor, NimMinor, NimPatch)` here
]#

import std/strutils

when (NimMajor, NimMinor, NimPatch) >= (0, 19, 9):
  import std/os
  export os.relativePath
else:
  import std/os except relativePath
  proc relativePath*(file, base: string): string =
    ## naive version of `os.relativePath` ; remove after nim >= 0.19.9
    runnableExamples:
      import ospaths, unittest
      check:
        "/foo/bar/baz/log.txt".unixToNativePath.relativePath("/foo/bar".unixToNativePath) == "baz/log.txt".unixToNativePath
        "foo/bar/baz/log.txt".unixToNativePath.relativePath("foo/bar".unixToNativePath) == "baz/log.txt".unixToNativePath
    var base2 = base.normalizedPath
    var file2 = file.normalizedPath
    if not base2.endsWith DirSep: base2.add DirSep
    doAssert file2.startsWith base2, $(file, base, file2, base2, $DirSep)
    result = file2[base2.len .. ^1]
