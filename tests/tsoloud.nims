# Workaround for C++ scanner.cc causing link error with other C obj files
when defined(MacOSX):
  switch("clang.linkerexe", "g++")
else:
  switch("gcc.linkerexe", "g++")