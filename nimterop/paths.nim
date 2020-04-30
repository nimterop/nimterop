import os

import "."/build

const
  cacheDir* = getProjectCacheDir("nimterop", forceClean = false)

proc nimteropRoot*(): string =
  currentSourcePath.parentDir.parentDir

proc nimteropSrcDir*(): string =
  nimteropRoot() / "nimterop"

proc toastExePath*(): string =
  nimteropSrcDir() / ("toast".addFileExt ExeExt)

proc testsIncludeDir*(): string =
  nimteropRoot() / "tests" / "include"
