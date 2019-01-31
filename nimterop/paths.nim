import os

proc nimteropRoot*(): string =
  currentSourcePath.parentDir.parentDir

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

