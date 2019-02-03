import os

proc nimteropRoot*(): string =
  result = currentSourcePath.parentDir.parentDir
  doAssert: result.len > 0 # pending https://github.com/nim-lang/Nim/pull/10629

proc nimteropBuildDir*(): string =
  ## all nimterop generated files go under here (gitignored)
  nimteropRoot() / "build"

proc nimteropSrcDir*(): string =
  nimteropRoot() / "nimterop"

proc toastExePath*(): string =
  nimteropSrcDir() / ("toast".addFileExt ExeExt)

proc incDir*(): string =
  nimteropBuildDir() / "inc"

proc testsIncludeDir*(): string =
  nimteropRoot() / "tests" / "include"

