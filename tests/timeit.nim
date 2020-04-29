import std/monotimes, os, osproc, sequtils, strformat, strutils, times

when isMainModule:
  var params = commandLineParams()
  params.apply(quoteShell)

  let cmd = params.join(" ")
  echo &"================\nRunning: {cmd}\n"

  let

    start = getMonoTime()
    ret = execCmd(cmd)
    endt = getMonoTime()

    outf = getAppDir() / "timeit.txt"
    outd = if fileExists(outf): readFile(outf) else: ""
    outp = &"\nRan: {cmd}\nTime taken: {$(endt - start)}\n"

  echo outp
  writeFile(outf, outd & outp)
  quit(ret)