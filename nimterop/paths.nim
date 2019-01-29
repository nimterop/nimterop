import os

proc nimteropRoot*(): string =
  currentSourcePath.parentDir.parentDir

proc nimteropBuildDir*(): string =
  ## all nimterop generated files go under here (gitignored)
  nimteropRoot() / "build"

proc nimteropSrcDir*(): string =
  nimteropRoot() / "nimterop"

proc toastExePath*(): string =
  # not sure how to make nimble install under here with `bin = @[...]`
  # nimteropBuildDir() / "toast"
  nimteropSrcDir() / "nimterop" / "toast"

proc incDir*(): string =
  nimteropBuildDir() / "inc"
