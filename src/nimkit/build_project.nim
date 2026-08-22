import std/[os, strutils, strformat, osproc]
import nimkit/[nimble_parser, security, nimble_integration]

type
  BuildError* = object of CatchableError

proc runNimCompiler*(nimArgs: seq[string], projectRoot: string): int =
  ## Run the Nim compiler with the given arguments - shell-free via startProcess.
  var quoted: seq[string] = @[]
  for a in nimArgs:
    quoted.add(quoteShell(a))
  let cmdStr = "nim " & quoted.join(" ")
  echo "Running: ", cmdStr
  # Use startProcess to avoid shell injection
  let p = startProcess("nim", args = nimArgs, options = {poUsePath, poParentStreams})
  result = p.waitForExit()
  p.close()

proc buildProject*(pkg: NimblePackage, projectRoot: string,
    release: bool = false): int =
  ## Build the project. Reuses `nimble build` when available for full
  ## NimScript compatibility, falls back to direct `nim c`.
  if isNimbleAvailable():
    let binArg = if pkg.bin.len > 0: pkg.bin[0] else: ""
    let code = nimbleBuild(projectRoot, release, binArg)
    if code != -1:
      return code
    # fall through to manual build if nimble not available

  let srcDir = getSourceDir(pkg, projectRoot)
  let mainBin = getMainBinary(pkg)

  if mainBin.len == 0:
    echo "Error: no binary name found in .nimble file"
    return 1

  if not isValidBinName(mainBin):
    echo "Error: invalid binary name: ", mainBin
    return 1

  let mainFile = srcDir / (mainBin & ".nim")
  # Ensure mainFile is inside projectRoot to prevent traversal
  if not isPathInsideBase(projectRoot, mainFile):
    echo "Error: source file escapes project directory: ", mainFile
    return 1
  if not fileExists(mainFile):
    echo fmt"Error: source file '{mainFile}' not found"
    return 1

  var nimArgs = @["c"]

  if release:
    nimArgs.add("-d:release")
    nimArgs.add("--opt:speed")

  # Add source directory to path
  nimArgs.add("--path:" & srcDir)

  nimArgs.add(mainFile)

  return runNimCompiler(nimArgs, projectRoot)

proc buildProject*(nimblePath: string, release: bool = false): int =
  ## Build the project from a .nimble file path. Prefers nimble dump for
  ## accurate package info (handles NimScript), falls back to parser.
  let pkg = getPackageInfo(nimblePath)
  let projectRoot = getProjectRoot(nimblePath)
  return buildProject(pkg, projectRoot, release)
