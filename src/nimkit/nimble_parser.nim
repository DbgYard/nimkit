import std/[os, strutils]
import nimkit/security

type
  NimbleTask* = object
    name*: string
    description*: string
    body*: seq[string]

  NimblePackage* = object
    name*: string
    version*: string
    author*: string
    description*: string
    license*: string
    srcDir*: string
    bin*: seq[string]
    requires*: seq[string]
    tasks*: seq[NimbleTask]
    skipDirs*: seq[string]
    skipFiles*: seq[string]
    skipExt*: seq[string]
    installFiles*: seq[string]
    installDirs*: seq[string]
    installExt*: seq[string]
    dim*: seq[string]

proc parseNimble*(path: string): NimblePackage =
  ## Parse a .nimble file (simple key=value format, not full NimScript).
  result = NimblePackage(
    srcDir: "src",
    requires: @[],
    bin: @[],
    tasks: @[],
    skipDirs: @["nimcache", "nimblecache"],
    skipFiles: @[],
    skipExt: @[],
    installFiles: @[],
    installDirs: @[],
    installExt: @[],
    dim: @[],
  )

  # Prevent DoS via huge .nimble
  let info = getFileInfo(path)
  if info.size > 1024 * 1024:
    # Too large, treat as empty
    return
  let content = readFile(path)
  let lines = content.splitLines()
  var i = 0
  while i < lines.len:
    var line = lines[i].strip()
    # Skip empty lines and comments
    if line.len == 0 or line.startsWith("#"):
      inc i
      continue
    # Remove inline comments
    let commentIdx = line.find(" #")
    if commentIdx >= 0:
      line = line[0..<commentIdx].strip()

    # Handle task definition: task name, "description":
    if line.startsWith("task "):
      # Parse: task <name>, "<description>":
      if line.len <= 5:
        inc i
        continue
      let rest = line[5..^1].strip()
      let commaIdx = rest.find(',')
      if commaIdx >= 0:
        let taskName = rest[0..<commaIdx].strip()
        # Validate task name - skip malicious/empty names
        if not isValidTaskName(taskName):
          inc i
          # Skip body lines of invalid task
          inc i
          while i < lines.len:
            let bodyLine = lines[i]
            if bodyLine.len > 0 and (bodyLine[0] == ' ' or bodyLine[0] == '\t'):
              inc i
            elif bodyLine.strip().len == 0:
              inc i
            else:
              break
          continue
        var desc = rest[(commaIdx + 1)..^1].strip()
        # Remove trailing colon and quotes
        if desc.endsWith(':'):
          desc = desc[0..^2].strip()
        desc = desc.strip(chars = {'"', '\''})
        # Limit description length
        if desc.len > 256:
          desc = desc[0..255]

        # Collect task body (indented lines following the task line)
        var body: seq[string] = @[]
        inc i
        while i < lines.len:
          let bodyLine = lines[i]
          # Task body lines are indented (start with space/tab) or empty
          if bodyLine.len > 0 and (bodyLine[0] == ' ' or bodyLine[0] == '\t'):
            # Limit body size to prevent DoS
            if body.len < 100 and bodyLine.len < 1024:
              body.add(bodyLine)
            else:
              discard
          elif bodyLine.strip().len == 0:
            body.add(bodyLine)
          else:
            break
          inc i

        result.tasks.add(NimbleTask(
          name: taskName,
          description: desc,
          body: body
        ))
        continue

    # Handle requires statement (no = sign)
    if line.startsWith("requires "):
      let val = line[9..^1].strip()
      result.requires.add(val.strip(chars = {'"', '\''}))
      inc i
      continue

    # Parse key = value or key = @[...]
    let eqIdx = line.find('=')
    if eqIdx < 0:
      inc i
      continue

    let key = line[0..<eqIdx].strip()
    var val = line[(eqIdx + 1)..^1].strip()

    # Remove trailing semicolons
    if val.endsWith(';'):
      val = val[0..^2].strip()

    case key
    of "name":
      let n = val.strip(chars = {'"', '\''})
      if isValidProjectName(n):
        result.name = n
    of "version":
      result.version = val.strip(chars = {'"', '\''})
    of "author":
      result.author = val.strip(chars = {'"', '\''})
    of "description":
      result.description = val.strip(chars = {'"', '\''})
    of "license":
      result.license = val.strip(chars = {'"', '\''})
    of "srcDir":
      let rawSrc = val.strip(chars = {'"', '\''})
      if isValidSrcDir(rawSrc):
        result.srcDir = rawSrc
      else:
        # Fallback to safe default; malicious srcDir is ignored
        discard
    of "bin":
      # Parse @["bin1", "bin2"] format
      if val.startsWith("@["):
        if val.len >= 3:
          var inner = val[2..^2]
          for item in inner.split(','):
            let b = item.strip(chars = {'"', ' ', '\''})
            if b.len > 0 and isValidBinName(b):
              result.bin.add(b)
      else:
        let b = val.strip(chars = {'"', '\''})
        if b.len > 0 and isValidBinName(b):
          result.bin.add(b)
    of "requires":
      result.requires.add(val.strip(chars = {'"', '\''}))
    of "skipDirs":
      if val.startsWith("@[") and val.len >= 3:
        var inner = val[2..^2]
        for item in inner.split(','):
          result.skipDirs.add(item.strip(chars = {'"', ' ', '\''}))
    of "skipFiles":
      if val.startsWith("@[") and val.len >= 3:
        var inner = val[2..^2]
        for item in inner.split(','):
          result.skipFiles.add(item.strip(chars = {'"', ' ', '\''}))
    of "skipExt":
      if val.startsWith("@[") and val.len >= 3:
        var inner = val[2..^2]
        for item in inner.split(','):
          result.skipExt.add(item.strip(chars = {'"', ' ', '\''}))
    of "installFiles":
      if val.startsWith("@[") and val.len >= 3:
        var inner = val[2..^2]
        for item in inner.split(','):
          result.installFiles.add(item.strip(chars = {'"', ' ', '\''}))
    of "installDirs":
      if val.startsWith("@[") and val.len >= 3:
        var inner = val[2..^2]
        for item in inner.split(','):
          result.installDirs.add(item.strip(chars = {'"', ' ', '\''}))
    of "installExt":
      if val.startsWith("@[") and val.len >= 3:
        var inner = val[2..^2]
        for item in inner.split(','):
          result.installExt.add(item.strip(chars = {'"', ' ', '\''}))
    of "dim":
      if val.startsWith("@[") and val.len >= 3:
        var inner = val[2..^2]
        for item in inner.split(','):
          result.dim.add(item.strip(chars = {'"', ' ', '\''}))
    inc i

proc findNimbleFile*(dir: string = ""): string =
  ## Find the .nimble file in the given directory or current directory.
  var searchDir = if dir.len > 0: dir else: getCurrentDir()
  for kind, path in walkDir(searchDir):
    if kind == pcFile and path.endsWith(".nimble"):
      return path
  return ""

proc getProjectRoot*(nimblePath: string): string =
  ## Get the project root directory from a .nimble file path.
  return parentDir(nimblePath)

proc getMainBinary*(pkg: NimblePackage): string =
  ## Get the main binary name from the package - validated.
  if pkg.bin.len > 0 and isValidBinName(pkg.bin[0]):
    return pkg.bin[0]
  if pkg.name.len > 0 and isValidBinName(pkg.name):
    return pkg.name
  return ""

proc getTestDir*(pkg: NimblePackage, projectRoot: string): string =
  ## Get the tests directory path.
  return projectRoot / "tests"

proc getSourceDir*(pkg: NimblePackage, projectRoot: string): string =
  ## Get the source directory path - validated to stay inside projectRoot.
  let candidate = projectRoot / pkg.srcDir
  if isPathInsideBase(projectRoot, candidate):
    return candidate
  return projectRoot / "src"
