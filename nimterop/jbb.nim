import marshal, os, strutils

type
  JBBPackage* = ref object
    ## JBBPackage type that stores package information
    name*: string
    version*: string

    url*: string

    sharedLibs*: seq[string]
    staticLibs*: seq[string]
    requires*: seq[JBBPackage]

const
  # JBB URLs
  jbbBaseUrl = "https://github.com/JuliaBinaryWrappers/$1_jll.jl"

  jbbInfo = "jbbinfo.json"
  jbbProject = "Project.toml"
  jbbArtifacts = "Artifacts.toml"

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
      if line.len != 0:
        if line.startsWith('['):
          if line == "[deps]":
            deps = true
          else:
            deps = false
        elif deps:
          let
            name = line.split()[0]
          if name.endsWith("_jll"):
            pkg.requires.add newJBBPackage(name[0 .. ^5], "")

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
      if line.len != 0:
        if line.startsWith("arch = ") and not found:
          let
            barch = line.split(" = ")[1].strip(chars = {'"'})
          if barch == arch:
            found = true
        elif line.startsWith("os = ") and found:
          let
            bos = line.split(" = ")[1].strip(chars = {'"'})
          if bos != os:
            found = false
        elif line.startsWith("url = ") and found:
          pkg.url = line.split(" = ")[1].strip(chars = {'"'})
          break

proc findJBBLibs(pkg: JBBPackage, outdir: string) =
  pkg.sharedLibs = findFiles("lib[\\\\/].*\\.(so|dylib)", outdir)
  pkg.sharedLibs.add findFiles("bin[\\\\/].*\\.(dll)", outdir)
  for i in 0 ..< pkg.sharedLibs.len:
    if pkg.sharedLibs[i].isAbsolute:
      pkg.sharedLibs[i] = pkg.sharedLibs[i][outdir.len+1 .. ^1]

  for lib in findFiles("lib[\\\\/].*\\.(a|lib)$", outdir):
    if not lib.endsWith(".dll.a"):
      if lib.isAbsolute:
        pkg.staticLibs.add lib[outdir.len+1 .. ^1]
      else:
        pkg.staticLibs.add lib

proc getJBBRepo*(pkg: JBBPackage, outdir: string) =
  ## Clone JBB package repo and checkout version tag if version is
  ## specified in package
  let
    path = outdir / "repos" / pkg.name

  gitPull(
    jbbBaseUrl % pkg.name,
    outdir = path,
    plist = "*.toml",
    "master",
    quiet = true
  )

  if pkg.version.len != 0:
    # Checkout correct tag
    let
      tags = gitTags(path)
    for i in tags.len - 1 .. 0:
      if pkg.version in tags[i] and i != tags.len - 1:
        gitCheckout(path, tags[i-1])

  pkg.parseJBBProject(path)
  pkg.parseJBBArtifacts(path)

proc loadJBBInfo*(outdir: string): JBBPackage =
  ## Load cached package info from `outdir/jbbinfo.json`
  fixOutDir()
  let
    file = outdir / jbbInfo

  if fileExists(file):
    result = to[JBBPackage](readFile(file))

proc saveJBBInfo*(pkg: JBBPackage, outdir: string) =
  ## Save downloaded package info to `outdir/jbbinfo.json`
  fixOutDir()
  let
    file = outdir / jbbInfo

  writeFile(file, $$pkg)

proc dlJBBRequires*(pkg: JBBPackage, outdir: string)
proc downloadJBB*(pkg: JBBPackage, outdir: string, clean = true) =
  ## Download `pkg` from BinaryBuilder.org to `outdir`
  ##
  ## High-level API that handles the end to end JBB process flow to find
  ## latest package binary and downloads and extracts it to `outdir`.
  fixOutDir()
  let
    cpkg = loadJBBInfo(outdir)

  if cpkg == pkg:
    return
  elif clean:
    cleanDir(outdir)

  pkg.getJBBRepo(outdir)

  doAssert pkg.url.len != 0, &"Failed to download {pkg.name} info from BinaryBuilder.org"

  let
    vstr =
      if pkg.version.len != 0:
        &" v{pkg.version}"
      else:
        ""
    path = outdir / "downloads" / pkg.name
  echo &"# Downloading {pkg.name}{vstr} from BinaryBuilder.org"
  downloadUrl(pkg.url, path, quiet = true)
  pkg.findJBBLibs(path)
  mvTree(path, outdir)

  pkg.dlJBBRequires(outdir)

  if clean:
    pkg.saveJBBInfo(outdir)

proc dlJBBRequires*(pkg: JBBPackage, outdir: string) =
  ## Download all required dependencies of this `pkg`
  fixOutDir()
  for rpkg in pkg.requires:
    downloadJBB(rpkg, outdir, clean = false)

proc getJBBLDeps*(pkg: JBBPackage, outdir: string, shared: bool, main = true): seq[string] =
  ## Get all BinaryBuilder.org libs - shared (.so|.dll) or static (.a|.lib) in pkg, including deps
  ## in descending order
  ##
  ## `outdir` is prefixed to each entry
  let
    libs = if shared: pkg.sharedLibs else: pkg.staticLibs
    str = if shared: "shared" else: "static"

  doAssert libs.len != 0, &"No {str} libs found for {pkg.name} in {outdir}"

  if not main:
    for lib in libs:
      result.add outdir / lib

  for cpkg in pkg.requires:
    result.add cpkg.getJBBLDeps(outdir, shared, main = false)
