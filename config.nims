# avoids clashes between installed and local version of each module
switch("path", ".")

#[
see D20190127T231316 workaround for fact that toast needs to build
scanner.cc, which would otherwise result in link errors such as:
"std::terminate()", referenced from:
      ___clang_call_terminate in scanner.cc.o
]#
when defined(MacOSX):
  switch("clang.linkerexe", "g++")
else:
  switch("gcc.linkerexe", "g++")

# Workaround for NilAccessError crash on Windows #98
when defined(Windows):
  switch("gc", "markAndSweep")

const workaround_10629 = defined(windows) and getCommand() == "doc"
  # pending https://github.com/nim-lang/Nim/pull/10629
when workaround_10629:
  switch("define", "workaround_10629")
  import ospaths, strformat, strutils
  proc getNimRootDir(): string =
    fmt"{currentSourcePath}".parentDir.parentDir.parentDir
  var file = getNimRootDir() / "lib/pure/includes/osseps.nim"
  if not existsFile file:
    file = getNimRootDir() / "lib/pure/ospaths.nim"
  const file2 = getTempDir() / "ospaths.nim"
  var text = file.readFile
  text = replace(text, """
    DirSep* = '/'""", """
    DirSep* = '\\'""")
  writeFile file2, text
  patchFile("stdlib", file.splitFile.name, file2)
