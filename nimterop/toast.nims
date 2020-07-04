import os

# Workaround for C++ scanner.cc causing link error with other C obj files
switch("clang.linkerexe", "clang++")
switch("gcc.linkerexe", "g++")

# Workaround for NilAccessError crash on Windows #98
# Could also help for OSX/Linux crash
switch("gc", "boehm")

# Retain stackTrace for clear errors
switch("stackTrace", "on")
switch("lineTrace", "on")

# Path to compiler
switch("path", "$nim")

# Case objects
when not defined(danger):
  switch("define", "nimOldCaseObjects")

# Prevent outdir override
switch("out", currentSourcePath.parentDir() / "toast".addFileExt(ExeExt))

# Define TOAST for globals.nim
switch("define", "TOAST")

switch("passL", "-Wl,--export-dynamic")