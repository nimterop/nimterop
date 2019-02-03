import os

proc nimteropRoot*(): string =
  # currentSourcePath.parentDir.parentDir
  # workaround BUG windows D20190202T182024
  const dir = currentSourcePath
  const ret = dir.parentDir.parentDir
  let ret2 = dir.parentDir.parentDir
  echo ("nimteropRoot", dir, currentSourcePath, ret, ret2)
  dir.parentDir.parentDir

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

