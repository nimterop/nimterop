import os

let
  wrappers = @["genotrance/nimarchive", "genotrance/nimgit2"]

rmDir("wrappers")
mkDir("wrappers")
withDir("wrappers"):
  for wrapper in wrappers:
    let
      name = wrapper.extractFilename()
    exec "../../tests/timeit git clone https://github.com/" & wrapper
    withDir(name):
      exec "../../../tests/timeit nimble install -d"
      exec "../../../tests/timeit nimble test"