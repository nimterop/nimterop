import os

let
  wrappers = @["genotrance/nimarchive", "genotrance/nimgit2"]

rmDir("wrappers")
mkDir("wrappers")
withDir("wrappers"):
  for wrapper in wrappers:
    let
      name = wrapper.extractFilename()
    exec "git clone https://github.com/" & wrapper
    withDir(name):
      exec "nimble install -d"
      exec "nimble test"