#[
see D20190127T231316 workaround for fact that toast needs to build scanner.cc, which would otherwise result in link erros such as:
"std::terminate()", referenced from:
      ___clang_call_terminate in scanner.cc.o
]#
when defined(MacOSX):
  switch("clang.linkerexe", "g++")
else:
  switch("gcc.linkerexe", "g++")
