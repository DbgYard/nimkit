import std/[os, strutils, strformat, osproc, times, algorithm, streams]
import nimkit/[nimble_parser, security]

type
  TestResult = object
    name: string
    passed: bool
    duration: float
    output: string

proc discoverTests*(testDir: string): seq[string] =
  ## Discover test files matching t*.nim pattern - with validation.
  result = @[]
  if not dirExists(testDir):
    return
  # Ensure testDir is not escaping - must be inside its parent project; caller ensures.
  for kind, path in walkDir(testDir):
    if kind == pcFile:
      # Reject paths with suspicious characters to prevent injection via filename
      if ';' in path or '&' in path or '|' in path or '`' in path or '$' in path or '\n' in path:
        continue
      # Ensure discovered file is actually inside testDir after normalization
      if not isPathInsideBase(testDir, path):
        continue
      let (_, name, ext) = splitFile(path)
      if ext == ".nim" and name.startsWith("t") and name.len > 1:
        # Validate name is safe (no shell metachars, must be valid)
        if not isValidTaskName(name):
          # Fallback: allow t + alnum_- but isValidTaskName already covers that, so skip
          continue
        result.add(path)
  result.sort(proc(a, b: string): int = cmp(a, b))

proc runSingleTest*(testFile: string, pkg: NimblePackage, projectRoot: string): TestResult =
  ## Run a single test file and return the result - shell-free.
  let startTime = epochTime()
  let srcDir = getSourceDir(pkg, projectRoot)
  # Validate testFile is inside projectRoot
  if not isPathInsideBase(projectRoot, testFile):
    return TestResult(name: extractFilename(testFile), passed: false, duration: epochTime() - startTime, output: "Error: test file escapes project directory")

  var nimArgs = @["c", "-r"]
  nimArgs.add("--path:" & srcDir)
  nimArgs.add(testFile)

  let p = startProcess("nim", args = nimArgs, options = {poUsePath, poStdErrToStdOut})
  let output = readAll(p.outputStream)
  let exitCode = p.waitForExit()
  p.close()

  TestResult(
    name: extractFilename(testFile),
    passed: exitCode == 0,
    duration: epochTime() - startTime,
    output: output
  )

proc runAllTests*(pkg: NimblePackage, projectRoot: string, verbose: bool = false): int =
  ## Run all tests and return the exit code (0 = all passed).
  let testDir = getTestDir(pkg, projectRoot)
  let tests = discoverTests(testDir)

  if tests.len == 0:
    echo "No tests found in ", testDir
    return 0

  echo fmt"Running {tests.len} test(s)..."
  echo ""

  var totalPassed = 0
  var totalFailed = 0
  var totalTime = 0.0

  for testFile in tests:
    let testResult = runSingleTest(testFile, pkg, projectRoot)
    totalTime += testResult.duration

    if testResult.passed:
      inc totalPassed
      echo fmt"[PASS] {testResult.name} ({testResult.duration:.3f}s)"
    else:
      inc totalFailed
      echo fmt"[FAIL] {testResult.name} ({testResult.duration:.3f}s)"
      if verbose:
        echo testResult.output

  echo ""
  echo fmt"Results: {totalPassed} passed, {totalFailed} failed, {tests.len} total ({totalTime:.3f}s)"

  if totalFailed > 0:
    return 1
  return 0

proc runAllTests*(nimblePath: string, verbose: bool = false): int =
  ## Run all tests from a .nimble file path.
  let pkg = parseNimble(nimblePath)
  let projectRoot = getProjectRoot(nimblePath)
  return runAllTests(pkg, projectRoot, verbose)
