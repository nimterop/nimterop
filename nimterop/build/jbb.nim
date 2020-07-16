import json, os, strformat, strutils, tables

import ".."/globals
import "."/[ccompiler, nimconf, shell]

when (NimMajor, NimMinor, NimPatch) < (1, 2, 0):
  import marshal

type
  JBBPackage* = ref object
    ## JBBPackage type that stores package information
    name*: string
    version*: string

    baseUrl*: string    # Location to find package
    isGit*: bool        # Git or HTTP

    url*: string        # Download URL

    sharedLibs*: seq[string]
    staticLibs*: seq[string]
    requires*: seq[JBBPackage]

    skipRequires*: seq[string]

const
  # JBB URLs
  jbbBaseUrl = "https://github.com/JuliaBinaryWrappers"

  jbbInfo = "jbbinfo.json"
  jbbProject = "Project.toml"
  jbbArtifacts = "Artifacts.toml"

var
  # Reuse dependencies already downloaded
  gJBBRequires {.compileTime.}: Table[string, JBBPackage]

proc `==`*(pkg1, pkg2: JBBPackage): bool =
  ## Check if two JBBPackage objects are equal
  (not pkg1.isNil and not pkg2.isNil and
    pkg1.name == pkg2.name and
    pkg1.version == pkg2.version)

proc newJBBPackage*(name, version: string): JBBPackage =
  ## Create a new JBBPackage with specified name and version
  result = new(JBBPackage)
  result.name = name
  result.version = version
  result.baseUrl = jbbBaseUrl
  result.isGit = true

proc parseJBBProject(pkg: JBBPackage, outdir: string) =
  # Get all dependencies from Project.toml
  let
    file = outdir / jbbProject

  if fileExists(file):
    let
      data = readFile(file)
    var
      deps = false

    doAssert pkg.version in data, &"{pkg.name} v{pkg.version} not found"

    for line in data.splitLines():
      let
        line = line.strip()
      if line.nBl:
        if line.startsWith('['):
          if line == "[deps]":
            deps = true
          else:
            deps = false
        elif deps:
          let
            name = line.split()[0]
          if name.endsWith("_jll"):
            # Filter skipped dependencies
            let
              pname = name[0 .. ^5]
            if pname.toLowerAscii() notin pkg.skipRequires:
              pkg.requires.add newJBBPackage(pname, "")
              pkg.requires[^1].skipRequires = pkg.skipRequires

proc parseJBBArtifacts(pkg: JBBPackage, outdir: string) =
  # Get build information from Artifacts.toml
  let
    file = outdir / jbbArtifacts

    (arch, os, _, _) = getGccInfo()

  if fileExists(file):
    let
      data = readFile(file)

    doAssert pkg.version in data, &"{pkg.name} v{pkg.version} not found"

    var
      found = false
    for line in data.splitLines():
      let
        line = line.strip()
      if line.nBl:
        let
          spl = line.split(" = ", 1)
          name = spl[0]
          val = if spl.len == 2: spl[1].strip(chars = {'"', ' '}) else: ""

        # Match arch, os and glibc on Linux to find download URL
        case name
        of "arch":
          if val == arch and not found: found = true
        of "os":
          if val != os and found: found = false
        of "libc":
          when defined(Linux):
            if val != "glibc" and found: found = false
        of "url":
          if found:
            pkg.url = val
            break
        else:
          discard

proc findJBBLibs(pkg: JBBPackage, outdir: string) =
  pkg.sharedLibs = findFiles("(bin|lib)[\\\\/].*\\.(so|dll|dylib)[0-9.]*", outdir)

  for lib in findFiles("lib[\\\\/].*\\.(a|lib)$", outdir):
    if not lib.endsWith(".dll.a"):
      pkg.staticLibs.add lib

proc getJBBRepo*(pkg: JBBPackage, outdir: string) =
  ## Clone JBB package repo and checkout version tag if version is
  ## specified in package
  let
    path = outdir / "repos" / pkg.name

  if pkg.isGit:
    # Get package info using Git
    gitPull(
      pkg.baseUrl & ("/$1_jll.jl" % pkg.name),
      outdir = path,
      plist = "*.toml",
      "master",
      quiet = true
    )

    if pkg.version.nBl:
      # Checkout correct tag
      let
        tags = gitTags(path)
      for i in tags.len - 1 .. 0:
        if pkg.version in tags[i] and i != tags.len - 1:
          gitCheckout(path, tags[i-1])
  else:
    # Download package info from HTTP
    var
      url = pkg.baseUrl
    if "$#" in url or "$1" in url:
      doAssert pkg.version.nBl, "Need version for custom BinaryBuilder.org url: " & url
      url = url % pkg.version
    downloadUrl(url & "Artifacts.toml", path, quiet = true)
    downloadUrl(url & "Project.toml", path, quiet = true)

  pkg.parseJBBProject(path)
  pkg.parseJBBArtifacts(path)

proc loadJBBInfo*(outdir: string): JBBPackage =
  ## Load cached package info from `outdir/jbbinfo.json`
  let
    file = fixRelPath(outdir) / jbbInfo

  if fileExists(file):
    when (NimMajor, NimMinor, NimPatch) < (1, 2, 0):
      result = to[JBBPackage](readFile(file))
    else:
      try:
        result = to(readFile(file).parseJson(), JBBPackage)
      except:
        discard

proc saveJBBInfo*(pkg: JBBPackage, outdir: string) =
  ## Save downloaded package info to `outdir/jbbinfo.json`
  let
    file = fixRelPath(outdir) / jbbInfo

  when (NimMajor, NimMinor, NimPatch) < (1, 2, 0):
    writeFile(file, $$pkg)
  else:
    writeFile(file, $(%pkg))

proc dlJBBRequires*(pkg: JBBPackage, outdir: string)
proc downloadJBB*(pkg: JBBPackage, outdir: string, main = true) =
  ## Download `pkg` from BinaryBuilder.org to `outdir`
  ##
  ## High-level API that handles the end to end JBB process flow to find
  ## latest package binary and downloads and extracts it to `outdir`.
  let
    outdir = fixRelPath(outdir)

  if main:
    let
      cpkg = loadJBBInfo(outdir)

    if cpkg == pkg:
      return

    cleanDir(outdir)

  pkg.getJBBRepo(outdir)

  if pkg.url.Bl:
    # No url for deps means no package for that os/arch combo - e.g. Attr
    doAssert not main, &"Failed to download {pkg.name} info from BinaryBuilder.org"
    return

  let
    vstr =
      if pkg.version.nBl:
        &" v{pkg.version}"
      else:
        ""
    path = outdir / pkg.name
  gecho &"# Downloading {pkg.name}{vstr} from BinaryBuilder.org"
  downloadUrl(pkg.url, path, quiet = true)
  pkg.findJBBLibs(path)

  pkg.dlJBBRequires(outdir)

  if main:
    pkg.saveJBBInfo(outdir)

proc dlJBBRequires*(pkg: JBBPackage, outdir: string) =
  ## Download all required dependencies of this `pkg`
  let
    outdir = fixRelPath(outdir)
  for i in 0 ..< pkg.requires.len:
    let
      rpkg = pkg.requires[i]
    if gJBBRequires.hasKey(rpkg.name):
      # Reuse dep already downloaded
      pkg.requires[i] = gJBBRequires[rpkg.name]
    else:
      downloadJBB(rpkg, outdir, main = false)
      gJBBRequires[rpkg.name] = rpkg

proc getJBBLDeps*(pkg: JBBPackage, outdir: string, shared: bool, main = true): seq[string] =
  ## Get all BinaryBuilder.org libs - shared (.so|.dll) or static (.a|.lib) in pkg, including deps
  ## in descending order
  ##
  ## `outdir` is prefixed to each entry
  let
    libs = if shared: pkg.sharedLibs else: pkg.staticLibs
    str = if shared: "shared" else: "static"

  doAssert libs.nBl, &"No {str} libs found for {pkg.name} in {outdir}"

  if not main:
    for lib in libs:
      result.add lib

  for cpkg in pkg.requires:
    result.add cpkg.getJBBLDeps(outdir, shared, main = false)
