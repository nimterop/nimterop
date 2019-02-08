#[
module for backward compatibility
put everything that requires `when (NimMajor, NimMinor, NimPatch)` here
]#

import os

when (NimMajor, NimMinor, NimPatch) >= (0, 19, 9):
  export relativePath
else:
  import std/[ospaths,strutils]

  proc relativePath*(file, base: string): string =
    ## naive version of `os.relativePath` ; remove after nim >= 0.19.9
    runnableExamples:
      import ospaths, unittest
      check:
        "/foo/bar/baz/log.txt".unixToNativePath.relativePath("/foo/bar".unixToNativePath) == "baz/log.txt".unixToNativePath
        "foo/bar/baz/log.txt".unixToNativePath.relativePath("foo/bar".unixToNativePath) == "baz/log.txt".unixToNativePath
    var base = base.normalizedPath
    var file = file.normalizedPath
    if not base.endsWith DirSep: base.add DirSep
    doAssert file.startsWith base
    result = file[base.len .. ^1]
