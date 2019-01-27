import os

proc nimteropRoot*(): string =
  currentSourcePath.parentDir.parentDir

proc nimteropBuildDir*(): string =
  ## all nimterop generated files go under here (gitignored)
  nimteropRoot() / "build"

proc toastExePath*(): string =
  nimteropBuildDir() / "toast"

proc nimteropSrcDir*(): string =
  nimteropRoot() / "nimterop"

proc incDir*(): string =
  nimteropBuildDir() / "inc"
