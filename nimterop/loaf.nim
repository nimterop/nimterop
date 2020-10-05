import system except find

import os

import cligen

import strutils except find
import regex except find

proc findRec(dir: string, pattern: string | Regex, recurse: bool) =
  for kind, path in walkDir(dir):
    if kind in [pcDir, pcLinkToDir]:
      if recurse: findRec(path, pattern, recurse)
    elif pattern in path:
      echo path.absolutePath()

proc find(recurse = false, rexp = false, args: seq[string]) =
  var
    pat = ""
    rpat: Regex
  for arg in args:
    if not arg.startsWith("-"):
      if dirExists(arg):
        if rexp:
          findRec(arg, rpat, recurse)
        else:
          findRec(arg, pat, recurse)
      else:
        pat = arg
        if rexp: rpat = re(arg)

when isMainModule:
  dispatchMulti([
    find, help = {
      "recurse": "recursive search",
      "rexp": "patterns are regular expressions",
      "args": "pattern1 dir1 dir2 pattern2 dir3 ..."
    }
  ])
