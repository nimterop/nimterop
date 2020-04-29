import os, osproc, sequtils, strformat, strutils, times

when (NimMajor, NimMinor) >= (1, 0):
  import std/monotimes

  template getTime(): MonoTime = getMonoTime()
else:
  template getTime(): float = epochTime()

when isMainModule:
  var params = commandLineParams()
  params.apply(quoteShell)

  let cmd = params.join(" ")
  echo &"================\nRunning: {cmd}\n"

  let

    start = getTime()
    ret = execCmd(cmd)
    endt = getTime()

    outf = getAppDir() / "timeit.txt"
    outd = if fileExists(outf): readFile(outf) else: ""
    outp = &"\nRan: {cmd}\nTime taken: {$(endt - start)}\n"

  echo outp
  writeFile(outf, outd & outp)
  quit(ret)