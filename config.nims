# Workaround for C++ scanner.cc causing link error with other C obj files
when defined(MacOSX):
  switch("clang.linkerexe", "g++")
else:
  switch("gcc.linkerexe", "g++")

# Workaround for NilAccessError crash on Windows #98
# Could also help for OSX/Linux crash
switch("gc", "markAndSweep")

# Retain stackTrace for clear errors
switch("stackTrace", "on")
switch("lineTrace", "on")

# Path to compiler
switch("path", "$nim")

# Case objects
when not defined(danger):
  switch("define", "nimOldCaseObjects")