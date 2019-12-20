#[
module for backward compatibility
put everything that requires `when (NimMajor, NimMinor, NimPatch)` here
]#

import os

when (NimMajor, NimMinor, NimPatch) >= (0, 19, 9):
  proc myNormalizedPath*(path: string): string = path.normalizedPath()

  export relativePath

else:
  import std/[ospaths,strutils]

  proc myNormalizedPath*(path: string): string =
    result = path.normalizedPath()
    when defined(windows):
      result = result.strip(trailing = false, chars = {'\\'})

  proc relativePath*(file, base: string): string =
    ## naive version of `os.relativePath` ; remove after nim >= 0.19.9
    runnableExamples:
      import ospaths, unittest
      check:
        "/foo/bar/baz/log.txt".unixToNativePath.relativePath("/foo/bar".unixToNativePath) == "baz/log.txt".unixToNativePath
        "foo/bar/baz/log.txt".unixToNativePath.relativePath("foo/bar".unixToNativePath) == "baz/log.txt".unixToNativePath
    var base = base.myNormalizedPath
    var file = file.myNormalizedPath
    if not base.endsWith DirSep: base.add DirSep
    doAssert file.startsWith base
    result = file[base.len .. ^1]

  proc getCurrentCompilerExe*(): string = "nim"
