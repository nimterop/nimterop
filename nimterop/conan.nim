import json, marshal, os, strformat, strutils, tables

type
  ConanPackage* = ref object
    ## ConanPackage type that stores conan uri and recipes/builds/revisions
    name*: string
    version*: string
    user*: string
    channel*: string
    recipes*: OrderedTableRef[string, seq[ConanBuild]]

    bhash*: string
    shared*: bool
    headers*: seq[string]
    libs*: seq[string]
    requires*: seq[ConanPackage]

  ConanBuild* = ref object
    ## Build type that stores build specific info and revisions
    bhash*: string
    settings*: TableRef[string, string]
    options*: TableRef[string, string]
    requires*: seq[string]
    recipe_hash*: string
    revisions*: seq[string]

const
  # Conan API urls
  baseUrl = "https://conan.bintray.com/v2/conans"
  searchUrl = baseUrl & "/search?q=$query"
  pkgUrl = baseUrl & "/$name/$version/$user/$channel/search$query"
  cfgUrl = baseUrl & "/$name/$version/$user/$channel/revisions/$recipe/packages/$build/revisions"
  dlUrl = baseUrl & "/$name/$version/$user/$channel/revisions/$recipe/packages/$build/revisions/$revision/files/$file"

  # Bintray download sub-URL for explicit `user/channel` (not _/_)
  dlAltUrl = "/download_file?file_path=$user%2F$name%2F$version%2F$channel%2F0%2Fpackage%2F$build%2F0%2F$file"

  # Strings
  conanInfo = "conaninfo.json"
  conanPackage = "conan_package.tgz"
  conanManifest = "conanmanifest.txt"

# https://github.com/kdheepak/binary-builder-downloader/blob/master/src/bbd.nim
# https://bintray.com/conan/conan-center
# https://bintray.com/bincrafters/public-conan/

# https://docs.conan.io/en/latest/howtos/manage_shared_libraries.html#manage-shared

var
  # Bintray download URL for explicit `user/channel`
  baseAltUrl {.compiletime.} = {
    "bincrafters": "https://bintray.com/bincrafters/public-conan",
    "conan": "https://bintray.com/conan-community/conan"
  }.toTable()

template fixOutDir() {.dirty.} =
  let
    outdir = if outdir.isAbsolute(): outdir else: getProjectDir() / outdir

proc addAltBaseUrl*(name, url: string) =
  # Add an alternate base URL for a custom conan repo on bintray
  baseAltUrl[name] = url

proc jsonGet(url: string): JsonNode =
  # Make HTTP call and return content as JSON
  let
    temp = getTempDir()
    file = block:
      var
        file = temp / url.extractFilename()
      when defined(Windows):
        file = file.replace('?', '_')
      file

  downloadUrl(url, temp, quiet = true)
  result = readFile(file).parseJson()
  rmFile(file)

proc `==`*(pkg1, pkg2: ConanPackage): bool =
  ## Check if two ConanPackage objects are equal
  (not pkg1.isNil and not pkg2.isNil and
    pkg1.name == pkg2.name and
    pkg1.version == pkg2.version and
    pkg1.user == pkg2.user and
    pkg1.channel == pkg2.channel and

    pkg1.bhash == pkg2.bhash and
    pkg1.shared == pkg2.shared)

proc newConanPackage*(name, version, user = "_", channel = "_", bhash = "", shared = true): ConanPackage =
  ## Create a new ConanPackage with specified name and version
  result = new(ConanPackage)
  result.name = name
  result.version = version
  result.user = user
  result.channel = channel
  result.recipes = newOrderedTable[string, seq[ConanBuild]](2)

  result.bhash = bhash
  result.shared = shared

proc newConanPackageFromUri*(uri: string, shared = true): ConanPackage =
  ## Create a new ConanPackage from a conan uri typically formatted as name/version[@user/channel][:bhash]
  var
    name, version, user, channel, bhash: string

    spl = uri.split(":")

  if spl.len > 1:
    bhash = spl[1]

  spl = spl[0].split('/')

  name = spl[0]
  user = "_"
  channel = "_"

  if spl.len > 2:
    channel = spl[2]
  if spl.len > 1:
    spl = spl[1].split('@')

    version = spl[0]
    if spl.len > 1:
      user = spl[1]

  result = newConanPackage(name, version, user, channel, bhash, shared)

proc getUriFromConanPackage*(pkg: ConanPackage): string =
  ## Convert a ConanPackage to a conan uri
  result = pkg.name
  if pkg.version.len != 0:
    result &= "/" & pkg.version
  if pkg.user.len != 0:
    result &= "@" & pkg.user
  if pkg.channel.len != 0:
    result &= "/" & pkg.channel
  if pkg.bhash.len != 0:
    result &= ":" & pkg.bhash

proc searchConan*(name: string, version = "", user = "", channel = ""): ConanPackage =
  ## Search for package by `name` and optional `version`, `user` and `channel`
  ## 
  ## Search is quite slow so it is preferable to specify a version and use `getConanBuilds()`
  var
    query = name
  if version.len != 0:
    query &= "/" & version
    if user.len != 0:
      query &= "@" & user
      if channel.len != 0:
        query &= "/" & channel

  let
    j1 = jsonGet(searchUrl % ["query", query])
    res = j1.getOrDefault("results").getElems()

  if res.len != 0:
    # Return last entry - latest
    result = newConanPackageFromUri(res[^1].getStr())

proc searchConan*(pkg: ConanPackage): ConanPackage =
  ## Search for latest package based on incomplete package info
  result = searchConan(pkg.name, pkg.version, pkg.user, pkg.channel)

proc getConanBuilds*(pkg: ConanPackage, filter = "") =
  ## Get all builds for a package based on the C compiler's target OS/arch info
  ##
  ## `filter` can be used to tweak search terms
  ##    e.g. build_type=Debug&compiler=clang
  let
    (arch, os, compiler, version) = getGccInfo()

    vsplit = version.split('.')

    vfilter =
      when defined(OSX):
        vsplit[0 .. 1].join(".")
      else:
        vsplit[0]

    query =
      if pkg.bhash.len == 0:
        block:
          var
            query = &"?q=arch={arch}&os={os.capitalizeAscii()}"
          if "build_type" notin filter:
            query &= "&build_type=Release"
          if "shared=" notin filter:
            query &= &"&options.shared={($pkg.shared).capitalizeAscii()}"
          if filter.len != 0:
            query &= &"&{filter}"
          if "compiler=" notin filter and os != "windows":
            query &= &"&compiler={compiler}&compiler.version=" & vfilter

          query.replace("&", "%20and%20")
      else: ""

    url = pkgUrl % [
      "name", pkg.name,
      "version", pkg.version,
      "user", pkg.user,
      "channel", pkg.channel,
      "query", query
    ]

    j1 = jsonGet(url)

  if not j1.isNil:
    for bhash, bdata in j1.getFields():
      if pkg.bhash.len == 0 or pkg.bhash == bhash:
        let
          bld = new(ConanBuild)
          settings = bdata.getOrDefault("settings")
          options = bdata.getOrDefault("options")
          requires = bdata.getOrDefault("requires")
        bld.bhash = bhash
        if not settings.isNil:
          bld.settings = newTable[string, string](8)
          for key, value in settings.getFields():
            bld.settings[key] = value.getStr()
        if not options.isNil:
          bld.options = newTable[string, string](8)
          for key, value in options.getFields():
            bld.options[key] = value.getStr()
        bld.requires = requires.to(seq[string])
        bld.recipe_hash = bdata.getOrDefault("recipe_hash").getStr()

        if pkg.recipes.hasKey(bld.recipe_hash):
          pkg.recipes[bld.recipe_hash].add bld
        else:
          pkg.recipes[bld.recipe_hash] = @[bld]

        # Only need first or matching build
        break

proc getConanRevisions*(pkg: ConanPackage, bld: ConanBuild) =
  ## Get all revisions of a build
  let
    url = cfgUrl % [
      "name", pkg.name,
      "version", pkg.version,
      "user", pkg.user,
      "channel", pkg.channel,
      "recipe", bld.recipe_hash,
      "build", bld.bhash
    ]

    j1 = jsonGet(url)

  if not j1.isNil:
    let
      revs = j1.getOrDefault("revisions")
    for i in revs:
      bld.revisions.add i.getOrDefault("revision").getStr()

proc loadConanInfo*(outdir: string): ConanPackage =
  ## Load cached package info from `outdir/conaninfo.json`
  fixOutDir()
  let
    file = outdir / conanInfo

  if fileExists(file):
    result = to[ConanPackage](readFile(file))

proc saveConanInfo*(pkg: ConanPackage, outdir: string) =
  ## Save downloaded package info to `outdir/conaninfo.json`
  fixOutDir()
  let
    file = outdir / conanInfo

  writeFile(file, $$pkg)

proc parseConanManifest(pkg: ConanPackage, outdir: string) =
  # Get all header and library info from downloaded conan package
  let
    file = outdir / conanManifest
  
  if fileExists(file):
    let
      data = readFile(file)
    for line in data.splitLines():
      let
        line = line.split(':')[0]
      if line.startsWith("include/"):
        pkg.headers.add line
      elif line.startsWith("lib/"):
        pkg.libs.add line
      elif line.startsWith("bin/") and line.endsWith("dll"):
        pkg.libs.add line

proc dlConanBuild*(pkg: ConanPackage, bld: ConanBuild, outdir: string, revision = "") =
  ## Download specific `revision` of `bld` to `outdir`
  ##
  ## If omitted, the latest revision (first) is downloaded
  fixOutDir()
  let
    revision =
      if revision.len != 0:
        revision
      else:
        bld.revisions[0]

    url =
      if pkg.user == "_":
        dlUrl % [
          "name", pkg.name,
          "version", pkg.version,
          "user", pkg.user,
          "channel", pkg.channel,
          "recipe", bld.recipe_hash,
          "build", bld.bhash,
          "revision", revision,
          "file", conanPackage
        ]
      else:
        baseAltUrl[pkg.user] & dlAltUrl % [
          "name", pkg.name,
          "version", pkg.version,
          "user", pkg.user,
          "channel", pkg.channel,
          "build", bld.bhash,
          "file", conanPackage
        ]

  downloadUrl(url, outdir, quiet = true)
  downloadUrl(url.replace(conanPackage, conanManifest), outdir, quiet = true)

  pkg.parseConanManifest(outdir)

  rmFile(outdir / url.extractFilename())
  rmFile(outdir / conanManifest)

proc dlConanRequires*(pkg: ConanPackage, bld: ConanBuild, outdir: string)
proc downloadConan*(pkg: ConanPackage, outdir: string, clean = true) =
  ## Download latest recipe/build/revision of `pkg` to `outdir`
  ## 
  ## High-level API that handles the end to end Conan process flow to find
  ## latest package binary and downloads and extracts it to `outdir`.
  fixOutDir()
  let
    pkg =
      if pkg.version.len == 0:
        searchConan(pkg)
      else:
        pkg

    cpkg = loadConanInfo(outdir)

  if cpkg == pkg:
    return
  elif clean:
    cleanDir(outdir)

  echo &"# Downloading {pkg.name} v{pkg.version} from Conan"

  pkg.getConanBuilds()

  for recipe, builds in pkg.recipes:
    for build in builds:
      if pkg.bhash.len == 0 or pkg.bhash == build.bhash:
        pkg.getConanRevisions(build)
        pkg.dlConanBuild(build, outdir)
        pkg.dlConanRequires(build, outdir)
        break
    break

  if clean:
    pkg.saveConanInfo(outdir)

proc dlConanRequires*(pkg: ConanPackage, bld: ConanBuild, outdir: string) =
  ## Download all required dependencies of this `bld`
  ##
  ## This is not required for shared libs since conan builds them
  ## with all dependencies statically linked in
  fixOutDir()
  if bld.options["shared"] == "False":
    for req in bld.requires:
      let
        rpkg = newConanPackageFromUri(req)

      downloadConan(rpkg, outdir, clean = false)
      pkg.requires.add rpkg

proc getConanLibs*(pkg: ConanPackage, outdir: string): seq[string] =
  ## Get all Conan libs (.so|.a|.lib|.dll) in pkg, including deps
  ## in descending order
  ## 
  ## `outdir` is prefixed to each entry
  for lib in pkg.libs:
    result.add outdir / lib

  for cpkg in pkg.requires:
    result.add cpkg.getConanLibs(outdir)
