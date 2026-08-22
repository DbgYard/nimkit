import std/[osproc, json, strutils, streams]
import nimkit/nimble_parser
import nimkit/security

proc isNimbleAvailable*(): bool =
  ## Check if nimble is in PATH.
  let (_, code) = execCmdEx("nimble --version")
  return code == 0

proc nimbleDumpJson*(projectRoot: string): JsonNode =
  ## Run `nimble dump --json` in projectRoot and return parsed JSON.
  ## Returns nil on failure.
  try:
    let p = startProcess("nimble", args = @["dump", "--json"],
      workingDir = projectRoot, options = {poUsePath, poStdErrToStdOut})
    let output = readAll(p.outputStream)
    let code = p.waitForExit()
    p.close()
    if code != 0:
      return nil
    # nimble dump may print warnings before JSON; find JSON start
    var jsonStart = output.find("{")
    if jsonStart < 0:
      return nil
    let jsonStr = output[jsonStart..^1]
    return parseJson(jsonStr)
  except:
    return nil

proc jsonToNimblePackage*(j: JsonNode, fallback: NimblePackage): NimblePackage =
  ## Convert nimble dump JSON to NimblePackage. Falls back for missing fields.
  result = fallback
  try:
    if j.hasKey("name") and j["name"].kind == JString:
      let n = j["name"].getStr()
      if isValidProjectName(n):
        result.name = n
    if j.hasKey("version") and j["version"].kind == JString:
      result.version = j["version"].getStr()
    if j.hasKey("author") and j["author"].kind == JString:
      result.author = j["author"].getStr()
    if j.hasKey("desc") and j["desc"].kind == JString:
      result.description = j["desc"].getStr()
    if j.hasKey("license") and j["license"].kind == JString:
      result.license = j["license"].getStr()
    if j.hasKey("srcDir") and j["srcDir"].kind == JString:
      let s = j["srcDir"].getStr()
      if s.len > 0 and isValidSrcDir(s):
        result.srcDir = s
    if j.hasKey("bin") and j["bin"].kind == JArray:
      result.bin = @[]
      for item in j["bin"]:
        if item.kind == JString:
          var b = item.getStr()
          # nimble may return "nimkit.exe" on Windows; strip .exe for validation
          if b.endsWith(".exe"):
            b = b[0..^5]
          if isValidBinName(b):
            result.bin.add(b)
    if j.hasKey("requires") and j["requires"].kind == JArray:
      result.requires = @[]
      for req in j["requires"]:
        if req.kind == JObject and req.hasKey("name"):
          let name = req["name"].getStr()
          var ver = ""
          if req.hasKey("str"):
            let s = req["str"].getStr()
            # s is like ">= 2.0.0", req name already known
            # reconstruct as "name ver"
            if s.len > 0 and s != "any version":
              ver = " " & s
          result.requires.add(name & ver)
        elif req.kind == JString:
          result.requires.add(req.getStr())
    # Preserve tasks from fallback (nimble dump doesn't include tasks)
  except:
    discard

proc getPackageInfo*(nimblePath: string): NimblePackage =
  ## Get package info, preferring nimble dump for full NimScript evaluation,
  ## falling back to manual parser.
  let fallback = parseNimble(nimblePath)
  let projectRoot = getProjectRoot(nimblePath)
  if not isNimbleAvailable():
    return fallback
  let j = nimbleDumpJson(projectRoot)
  if j == nil:
    return fallback
  return jsonToNimblePackage(j, fallback)

proc nimbleBuild*(projectRoot: string, release: bool = false, binName: string = ""): int =
  ## Delegate build to `nimble build`. Returns exit code.
  ## Returns -1 if nimble not available.
  if not isNimbleAvailable():
    return -1
  var args = @["build", "-y"]
  if release:
    args.add("-d:release")
    args.add("--opt:speed")
  if binName.len > 0 and isValidBinName(binName):
    args.add(binName)
  let p = startProcess("nimble", args = args, workingDir = projectRoot,
    options = {poUsePath, poParentStreams})
  result = p.waitForExit()
  p.close()

proc nimbleTest*(projectRoot: string): int =
  ## Delegate test to `nimble test -y`. Returns -1 if not available.
  if not isNimbleAvailable():
    return -1
  let p = startProcess("nimble", args = @["test", "-y"],
    workingDir = projectRoot, options = {poUsePath, poParentStreams})
  result = p.waitForExit()
  p.close()

proc nimbleTasksList*(projectRoot: string): seq[NimbleTask] =
  ## Get tasks via `nimble tasks`. Returns empty on failure.
  ## Nimble prints tasks as: "taskName    description" per line.
  if not isNimbleAvailable():
    return @[]
  try:
    let p = startProcess("nimble", args = @["tasks"],
      workingDir = projectRoot, options = {poUsePath, poStdErrToStdOut})
    let output = readAll(p.outputStream)
    let code = p.waitForExit()
    p.close()
    if code != 0:
      return @[]
    result = @[]
    for line in output.splitLines():
      let stripped = line.strip()
      if stripped.len == 0: continue
      # nimble tasks output is like "hello    Hello" or with color codes
      # Skip header lines if any
      if stripped.toLowerAscii().startsWith("warning"): continue
      # Split by 2+ spaces
      var parts = stripped.splitWhitespace()
      if parts.len == 0: continue
      let name = parts[0].strip()
      if not isValidTaskName(name): continue
      var desc = ""
      if parts.len > 1:
        # Reconstruct description (nimble separates with spaces)
        # Find where name ends in original line
        let nameIdx = stripped.find(name)
        if nameIdx >= 0:
          desc = stripped[(nameIdx + name.len)..^1].strip()
      result.add(NimbleTask(name: name, description: desc, body: @[]))
  except:
    return @[]
