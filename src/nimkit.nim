import std/[os, strutils, strformat, osproc, algorithm, streams]
import nimkit/[nimble_parser, new_project, build_project, test_runner, security, ide, nimble_integration]

proc printUsage() =
  echo """
nimkit - A cargo-like project lifecycle tool for Nim

Usage:
  nimkit <command> [options]
  nimkit              Interactive mode (no args)

Commands:
  new <name>         Create a new project
  build              Build the project
  build --release    Build with release optimizations
  test               Run all tests
  run [args]         Build and run the project
  check              Check main source file
  check --all        Check all source files in src/
  clean              Remove build artifacts
  clean --docs       Also remove documentation output
  deps               List dependencies
  deps --tree        Show dependency tree
  add <pkg> [ver]    Add a dependency to .nimble
  remove <pkg>       Remove a dependency from .nimble
  task               List available tasks
  task <name>        Run a task
  init               Initialize nimkit in current directory
  ide <ide>          Setup IDE (e.g. nimkit ide vscode)
  help               Show this help message

Options:
  --lib              Create a library project (with new)
  --release          Use release optimizations (with build/run)
  --verbose          Show detailed output (with test)
  --dir <path>       Create project in specified directory (with new)
"""

proc findNimbleFileInCwd(): string =
  ## Find .nimble file in current directory.
  let cwd = getCurrentDir()
  for kind, path in walkDir(cwd):
    if kind == pcFile:
      let (_, _, ext) = splitFile(path)
      if ext == ".nimble":
        return path
  return ""

proc cmdNew(args: seq[string]) =
  if args.len < 1:
    echo "Error: project name required"
    echo "Usage: nimkit new <name> [--lib]"
    quit(1)

  var name = ""
  var isLib = false
  var dir = ""

  var i = 0
  while i < args.len:
    case args[i]
    of "--lib":
      isLib = true
    of "--dir":
      if i + 1 < args.len:
        dir = args[i + 1]
        inc i
      else:
        echo "Error: --dir requires a path"
        quit(1)
    else:
      if name.len == 0:
        name = args[i]
      else:
        echo "Error: unexpected argument '", args[i], "'"
        quit(1)
    inc i

  if name.len == 0:
    echo "Error: project name required"
    quit(1)

  createProject(name, isLib, dir)

proc cmdBuild(args: seq[string]) =
  let nimblePath = findNimbleFileInCwd()
  if nimblePath.len == 0:
    echo "Error: no .nimble file found in current directory"
    echo "Run 'nimkit new <name>' to create a project, or 'nimkit init' to adapt an existing one."
    quit(1)

  var release = false
  for arg in args:
    if arg == "--release":
      release = true

  let exitCode = buildProject(nimblePath, release)
  if exitCode != 0:
    quit(exitCode)

proc cmdRun(args: seq[string]) =
  let nimblePath = findNimbleFileInCwd()
  if nimblePath.len == 0:
    echo "Error: no .nimble file found in current directory"
    quit(1)

  let pkg = getPackageInfo(nimblePath)
  let projectRoot = getProjectRoot(nimblePath)
  let mainBin = getMainBinary(pkg)

  if mainBin.len == 0:
    echo "Error: no binary name found in .nimble file"
    quit(1)

  if not isValidBinName(mainBin):
    echo "Error: invalid binary name: ", mainBin
    quit(1)

  # Check if release flag is passed
  var release = false
  for arg in args:
    if arg == "--release":
      release = true

  # Build first
  let buildExitCode = buildProject(pkg, projectRoot, release)
  if buildExitCode != 0:
    quit(buildExitCode)

  # Run the binary - check both project root and src directory (validated)
  var binaryPath = ""
  let candidates = [
    projectRoot / mainBin,
    projectRoot / "src" / mainBin,
    projectRoot / (mainBin & ".exe"),
    projectRoot / "src" / (mainBin & ".exe")
  ]
  for cand in candidates:
    if not isPathInsideBase(projectRoot, cand):
      continue
    if fileExists(cand):
      binaryPath = cand
      break
  if binaryPath.len == 0:
    echo "Error: binary not found for ", mainBin
    quit(1)

  var runArgs: seq[string] = @[]
  for arg in args:
    if arg != "--release":
      # Reject run args containing null bytes
      if '\0' in arg:
        echo "Error: invalid run argument"
        quit(1)
      runArgs.add(arg)

  echo fmt"Running {mainBin}..."
  # Shell-free execution via startProcess to prevent injection
  let p = startProcess(binaryPath, args = runArgs, options = {poUsePath, poParentStreams})
  let exitCode = p.waitForExit()
  p.close()
  if exitCode != 0:
    quit(exitCode)

proc cmdTest(args: seq[string]) =
  let nimblePath = findNimbleFileInCwd()
  if nimblePath.len == 0:
    echo "Error: no .nimble file found in current directory"
    quit(1)

  var verbose = false
  for arg in args:
    if arg == "--verbose" or arg == "-v":
      verbose = true

  let exitCode = runAllTests(nimblePath, verbose)
  if exitCode != 0:
    quit(exitCode)

proc cmdCheck(args: seq[string]) =
  let nimblePath = findNimbleFileInCwd()
  if nimblePath.len == 0:
    echo "Error: no .nimble file found in current directory"
    quit(1)

  let pkg = getPackageInfo(nimblePath)
  let projectRoot = getProjectRoot(nimblePath)
  let srcDir = getSourceDir(pkg, projectRoot)

  var checkAll = false
  var showHints = false
  var arg: seq[string] = @[]

  for a in args:
    case a
    of "--all", "-a": checkAll = true
    of "--hints": showHints = true
    of "--help", "-h":
      echo "Usage: nimkit check [options]"
      echo ""
      echo "Options:"
      echo "  --all, -a     Check all .nim files in src/"
      echo "  --hints       Show hint messages"
      echo "  --help, -h    Show this help"
      return
    else:
      arg.add(a)

  # Validate srcDir is inside projectRoot
  if not isPathInsideBase(projectRoot, srcDir) and srcDir != projectRoot / "src":
    echo "Error: source directory escapes project root"
    quit(1)

  if checkAll:
    # Check all .nim files in src directory
    var nimFiles: seq[string] = @[]
    if not dirExists(srcDir):
      echo "No .nim files found in ", srcDir
      quit(1)
    for path in walkDirRec(srcDir):
      if not isPathInsideBase(projectRoot, path):
        continue
      if ';' in path or '&' in path or '|' in path or '`' in path:
        continue
      let (_, _, ext) = splitFile(path)
      if ext == ".nim":
        nimFiles.add(path)

    if nimFiles.len == 0:
      echo "No .nim files found in ", srcDir
      quit(1)

    nimFiles.sort()
    echo fmt"Checking {nimFiles.len} file(s)..."

    var errors = 0
    var warnings = 0

    for nimFile in nimFiles:
      # Validate nimFile still inside project
      if not isPathInsideBase(projectRoot, nimFile):
        echo fmt"[SKIP]  {nimFile} (outside project)"
        continue
      let relPath =
        if nimFile.startsWith(projectRoot):
          nimFile[(projectRoot.len + 1)..^1]
        else:
          nimFile
      # Shell-free nim check via startProcess
      let nimArgs = @["check", "--path:" & srcDir, nimFile]
      let p = startProcess("nim", args = nimArgs, options = {poUsePath, poStdErrToStdOut})
      let output = readAll(p.outputStream)
      let exitCode = p.waitForExit()
      p.close()
      if exitCode != 0:
        echo fmt"[ERROR] {relPath}"
        for line in output.splitLines():
          if line.len > 0 and not line.startsWith("Hint:"):
            echo "  ", line
        inc errors
      else:
        # Check for warnings in output
        var hasWarning = false
        for line in output.splitLines():
          if line.contains("Warning:"):
            hasWarning = true
            break
        if hasWarning:
          echo fmt"[WARN]  {relPath}"
          inc warnings
        else:
          echo fmt"[OK]    {relPath}"

    echo ""
    if errors > 0:
      echo fmt"Check failed: {errors} error(s), {warnings} warning(s)"
      quit(1)
    else:
      echo fmt"Check passed: {warnings} warning(s)"

  else:
    # Check only the main binary file
    let mainBin = getMainBinary(pkg)
    if mainBin.len == 0:
      echo "Error: no binary name found in .nimble file"
      quit(1)
    if not isValidBinName(mainBin):
      echo "Error: invalid binary name"
      quit(1)

    let mainFile = srcDir / (mainBin & ".nim")
    if not isPathInsideBase(projectRoot, mainFile):
      echo "Error: source file escapes project directory"
      quit(1)
    if not fileExists(mainFile):
      echo fmt"Error: source file '{mainFile}' not found"
      quit(1)

    echo fmt"Checking {mainBin}.nim..."
    let nimArgs = @["check", "--path:" & srcDir, mainFile]
    let p = startProcess("nim", args = nimArgs, options = {poUsePath, poParentStreams})
    let exitCode = p.waitForExit()
    p.close()
    if exitCode != 0:
      quit(exitCode)
    else:
      echo "Check passed."

proc cmdClean(args: seq[string]) =
  let nimblePath = findNimbleFileInCwd()
  if nimblePath.len == 0:
    echo "Error: no .nimble file found in current directory"
    quit(1)

  let pkg = getPackageInfo(nimblePath)
  let projectRoot = getProjectRoot(nimblePath)
  let mainBin = getMainBinary(pkg)

  var removeDocs = false
  var removeNimcache = true
  for arg in args:
    case arg
    of "--docs", "-d": removeDocs = true
    of "--all", "-a":
      removeDocs = true
      removeNimcache = true
    of "--help", "-h":
      echo "Usage: nimkit clean [options]"
      echo ""
      echo "Options:"
      echo "  --docs, -d    Also remove documentation output"
      echo "  --all, -a     Remove all build artifacts including docs"
      echo "  --help, -h    Show this help"
      return
    else:
      echo fmt"Unknown option: {arg}"
      echo "Run 'nimkit clean --help' for usage."
      quit(1)

  var cleanedCount = 0

  proc safeRemoveDir(path, display: string) =
    if not isPathInsideBase(projectRoot, path):
      echo fmt"Skipping {display} (outside project)"
      return
    if path == projectRoot or path == "/" or path.len < 4:
      echo fmt"Skipping {display} (protecting root)"
      return
    if dirExists(path):
      echo fmt"Removing {display}/"
      removeDir(path)
      inc cleanedCount

  proc safeRemoveFile(path: string) =
    if not isPathInsideBase(projectRoot, path):
      return
    if fileExists(path):
      echo fmt"Removing {extractFilename(path)}"
      removeFile(path)
      inc cleanedCount

  # Remove nimcache directory
  if removeNimcache:
    safeRemoveDir(projectRoot / "nimcache", "nimcache")
    safeRemoveDir(projectRoot / "src" / "nimcache", "src/nimcache")

  # Remove documentation output
  if removeDocs:
    safeRemoveDir(projectRoot / "doc", "doc")
    safeRemoveDir(projectRoot / "htmldocs", "htmldocs")

  # Remove binary files
  if mainBin.len > 0 and isValidBinName(mainBin):
    # Check multiple possible locations for the binary
    let possiblePaths = [
      projectRoot / mainBin,
      projectRoot / "src" / mainBin,
      projectRoot / "bin" / mainBin,
      projectRoot / (mainBin & ".exe"),
      projectRoot / "src" / (mainBin & ".exe"),
      projectRoot / "bin" / (mainBin & ".exe"),
    ]

    for binaryPath in possiblePaths:
      if isPathInsideBase(projectRoot, binaryPath):
        safeRemoveFile(binaryPath)

  # Remove test binaries
  let testDir = projectRoot / "tests"
  if dirExists(testDir) and isPathInsideBase(projectRoot, testDir):
    for kind, path in walkDir(testDir):
      if kind == pcFile:
        if not isPathInsideBase(projectRoot, path):
          continue
        let (_, name, ext) = splitFile(path)
        if ext == ".exe" or (ext == "" and name.startsWith("t")):
          # Check if it's an executable (no extension on Unix, .exe on Windows)
          when defined(windows):
            if ext == ".exe":
              # Extra check: don't delete .nim files
              if not path.endsWith(".nim"):
                safeRemoveFile(path)
          else:
            if ext == "" and not name.endsWith(".nim"):
              safeRemoveFile(path)

  if cleanedCount == 0:
    echo "Nothing to clean."
  else:
    echo fmt"Cleaned {cleanedCount} artifact(s)."

proc cmdDeps(args: seq[string]) =
  let nimblePath = findNimbleFileInCwd()
  if nimblePath.len == 0:
    echo "Error: no .nimble file found in current directory"
    quit(1)

  let pkg = getPackageInfo(nimblePath)

  var showTree = false
  var showVersions = false
  for arg in args:
    case arg
    of "--tree", "-t": showTree = true
    of "--versions", "-v": showVersions = true
    else:
      echo "Unknown option: ", arg
      echo "Usage: nimkit deps [--tree] [--versions]"
      quit(1)

  # Filter out nim itself from display
  var deps: seq[string] = @[]
  for dep in pkg.requires:
    if not dep.startsWith("nim ") and dep != "nim":
      deps.add(dep)

  if deps.len == 0:
    echo "No dependencies found."
    return

  if showTree:
    # Show dependency tree
    let displayName = if pkg.name.len > 0: pkg.name else: extractFilename(nimblePath).replace(".nimble", "")
    echo fmt"{displayName} v{pkg.version}"
    for i, dep in deps:
      let prefix = if i == deps.len - 1: "└── " else: "├── "
      echo prefix & dep
  else:
    # Show simple list
    echo fmt"Dependencies ({deps.len}):"
    for dep in deps:
      echo fmt"  {dep}"

proc cmdAdd(args: seq[string]) =
  if args.len < 1:
    echo "Error: package name required"
    echo "Usage: nimkit add <pkg> [version]"
    echo ""
    echo "Examples:"
    echo "  nimkit add jsony"
    echo "  nimkit add jsony >=1.1.0"
    echo "  nimkit add jsony ==1.2.0"
    quit(1)

  let nimblePath = findNimbleFileInCwd()
  if nimblePath.len == 0:
    echo "Error: no .nimble file found in current directory"
    quit(1)

  let pkgName = args[0]
  if not isValidPackageName(pkgName):
    echo fmt"Error: invalid package name '{pkgName}'"
    echo "Package name must match ^[a-zA-Z][a-zA-Z0-9_-]*$, 1-64 chars."
    quit(1)

  var versionConstraint = ""
  if args.len > 1:
    versionConstraint = " " & args[1..^1].join(" ")
    if not isValidVersionConstraint(versionConstraint):
      echo "Error: invalid version constraint"
      quit(1)

  let pkg = getPackageInfo(nimblePath)

  # Check if dependency already exists (exact match or same name with any version)
  for dep in pkg.requires:
    let depName = dep.split(" ")[0].strip()
    if depName == pkgName:
      echo fmt"Dependency '{pkgName}' already exists: {dep}"
      return

  # Read the file and find where to insert
  var lines = readFile(nimblePath).splitLines()
  var insertIdx = -1

  # Find the last requires line or the # Dependencies comment
  for i, line in lines:
    let stripped = line.strip()
    if stripped.startsWith("requires "):
      insertIdx = i + 1
    elif stripped == "# Dependencies":
      insertIdx = i + 1

  # If no requires line found, find the end of the file
  if insertIdx == -1:
    insertIdx = lines.len

  # Build the new requires line
  let newDep = "requires \"" & pkgName & versionConstraint & "\""

  # Insert at the correct position
  lines.insert(newDep, insertIdx)

  # Clean up any empty lines around the insertion
  var cleanedLines: seq[string] = @[]
  var prevWasEmpty = false
  for line in lines:
    let stripped = line.strip()
    if stripped.len == 0:
      if not prevWasEmpty:
        cleanedLines.add(line)
      prevWasEmpty = true
    else:
      cleanedLines.add(line)
      prevWasEmpty = false

  writeFile(nimblePath, cleanedLines.join("\n"))
  echo fmt"Added dependency: {pkgName}{versionConstraint}"

proc cmdRemove(args: seq[string]) =
  if args.len < 1:
    echo "Error: package name required"
    echo "Usage: nimkit remove <pkg>"
    quit(1)

  let nimblePath = findNimbleFileInCwd()
  if nimblePath.len == 0:
    echo "Error: no .nimble file found in current directory"
    quit(1)

  let pkgName = args[0]
  if not isValidPackageName(pkgName):
    echo fmt"Error: invalid package name '{pkgName}'"
    quit(1)
  let lines = readFile(nimblePath).splitLines()
  var newLines: seq[string] = @[]
  var found = false
  var foundDep = ""

  for line in lines:
    let stripped = line.strip()
    # Check if this is a requires line that matches the package name
    if stripped.startsWith("requires "):
      # Extract the package name from the requires line
      let depContent = stripped[9..^1].strip(chars = {'"'})
      let depName = depContent.split(" ")[0].strip()
      if depName == pkgName:
        found = true
        foundDep = depContent
        continue  # Skip this line (remove it)
    newLines.add(line)

  if not found:
    echo fmt"Dependency '{pkgName}' not found."
    return

  # Clean up any resulting empty lines
  var cleanedLines: seq[string] = @[]
  var prevWasEmpty = false
  for line in newLines:
    let stripped = line.strip()
    if stripped.len == 0:
      if not prevWasEmpty:
        cleanedLines.add(line)
      prevWasEmpty = true
    else:
      cleanedLines.add(line)
      prevWasEmpty = false

  writeFile(nimblePath, cleanedLines.join("\n"))
  echo fmt"Removed dependency: {foundDep}"

proc cmdTask(args: seq[string]) =
  let nimblePath = findNimbleFileInCwd()
  if nimblePath.len == 0:
    echo "Error: no .nimble file found in current directory"
    quit(1)

  let pkg = getPackageInfo(nimblePath)

  if args.len == 0:
    # List available tasks - prefer nimble for full NimScript evaluation
    var tasksToShow = pkg.tasks
    if isNimbleAvailable():
      let projectRoot = getProjectRoot(nimblePath)
      let nimbleTasks = nimbleTasksList(projectRoot)
      if nimbleTasks.len > 0:
        tasksToShow = nimbleTasks
    if tasksToShow.len == 0:
      echo "No tasks defined in .nimble file."
      echo ""
      echo "Add tasks to your .nimble file like:"
      echo "  task build, \"Build the project\":"
      echo "    exec \"nim c src/myapp.nim\""
      return

    echo fmt"Tasks ({tasksToShow.len}):"
    for task in tasksToShow:
      echo fmt"  {task.name:12s} {task.description}"
    return

  let taskName = args[0]
  if not isValidTaskName(taskName):
    echo fmt"Error: invalid task name '{taskName}'"
    quit(1)

  # Delegate to nimble for full NimScript evaluation (exec, variables, conditionals)
  echo fmt"Running task '{taskName}' via nimble..."
  let p = startProcess("nimble", args = @[taskName], options = {poUsePath, poParentStreams})
  let exitCode = p.waitForExit()
  p.close()
  if exitCode != 0:
    quit(exitCode)

proc cmdInit() =
  # Check if there's already a .nimble file
  let existing = findNimbleFileInCwd()
  if existing.len > 0:
    echo "Found existing .nimble file: ", existing
    echo "nimkit is already initialized."
    return

  # Create a basic .nimble file from directory name - validate
  var dirName = extractFilename(getCurrentDir())
  if not isValidProjectName(dirName):
    # Sanitize: fallback to safe name
    echo fmt"Warning: directory name '{dirName}' is not a valid project name, using 'myproject'"
    dirName = "myproject"
  echo "Initializing nimkit project for: ", dirName

  let nimbleContent = fmt"""# Package
version       = "0.1.0"
author        = "Author"
description   = "A new Nim application"
license       = "MIT"
srcDir        = "src"
bin           = @["{dirName}"]

# Dependencies
requires "nim >= 2.0.0"
"""
  writeFile(dirName & ".nimble", nimbleContent)

  # Create basic structure if not exists
  if not dirExists("src"):
    createDir("src")
  if not dirExists("tests"):
    createDir("tests")

  # Create basic main file if not exists
  let mainFile = "src" / (dirName & ".nim")
  if not fileExists(mainFile):
    writeFile(mainFile, "echo \"Hello from " & dirName & "!\"\n")

  echo "Created: ", dirName & ".nimble"
  echo "Created: src/", dirName, ".nim"
  echo "Created: tests/"
  echo ""
  echo "nimkit initialized!"

proc cmdIDE(args: seq[string]) =
  let nimblePath = findNimbleFileInCwd()
  if nimblePath.len == 0:
    echo "Error: no .nimble file found in current directory"
    echo "Run 'nimkit new <name>' or 'nimkit init' first."
    quit(1)

  if args.len == 0:
    echo "Usage: nimkit ide <ide>"
    echo ""
    echo "Supported IDEs:"
    echo "  vscode    Visual Studio Code"
    quit(1)

  setupIDE(nimblePath, args[0])

proc printMenu() =
  let nimblePath = findNimbleFileInCwd()
  let hasNimble = nimblePath.len > 0

  echo "nimkit - A cargo-like project lifecycle tool for Nim"
  echo ""

  if hasNimble:
    let pkg = getPackageInfo(nimblePath)
    let displayName = if pkg.name.len > 0: pkg.name else: extractFilename(nimblePath).replace(".nimble", "")
    echo fmt"Project: {displayName}"
    if pkg.version.len > 0: echo fmt"Version: {pkg.version}"
    if pkg.description.len > 0: echo fmt"Description: {pkg.description}"
    echo ""

  echo "Commands:"
  echo ""
  echo "  [1]  new              Create a new project"
  echo "  [2]  init             Initialize nimkit in current directory"
  echo ""

  if hasNimble:
    echo "  [3]  build            Build the project"
    echo "  [4]  build --release  Build with release optimizations"
    echo "  [5]  run              Build and run the project"
    echo "  [6]  test             Run all tests"
    echo "  [7]  check            Check source file(s)"
    echo "  [8]  clean            Remove build artifacts"
    echo ""
    echo "  [9]  deps             List dependencies"
    echo "  [10] add              Add a dependency"
    echo "  [11] remove           Remove a dependency"
    echo "  [12] task             List or run tasks"
    echo ""
    echo "  [13] ide              Setup IDE (VS Code)"
  else:
    echo "  (No .nimble file found — create or init a project first)"

  echo ""
  echo "  [h]  help             Show full help"
  echo "  [q]  quit"
  echo ""

proc prompt(question: string): string =
  stdout.write question
  result = stdin.readLine().strip()

proc promptChoice(max: int): string =
  while true:
    let input = prompt("Choose> ")
    if input.len == 0: continue
    if input == "q" or input == "quit" or input == "exit":
      echo "Goodbye!"
      quit(0)
    if input == "h" or input == "help":
      printUsage()
      return ""
    # Check if it's a number
    var isNum = true
    for c in input:
      if c < '0' or c > '9':
        isNum = false
        break
    if isNum:
      let num = parseInt(input)
      if num >= 1 and num <= max:
        return $num
      else:
        echo fmt"Invalid choice (1-{max})"
    else:
      echo "Invalid choice. Enter a number, 'h' for help, or 'q' to quit."

proc runInteractive() =
  printMenu()

  let nimblePath = findNimbleFileInCwd()
  let hasNimble = nimblePath.len > 0
  let maxChoice = if hasNimble: 13 else: 2

  let choice = promptChoice(maxChoice)
  if choice.len == 0: return

  case choice
  of "1":
    # new project
    let name = prompt("Project name: ")
    if name.len == 0:
      echo "Cancelled."
      return
    let libInput = prompt("Library project? (y/N): ")
    let isLib = libInput == "y" or libInput == "Y"
    cmdNew(@[name] & (if isLib: @["--lib"] else: @[]))

  of "2":
    # init
    cmdInit()

  of "3":
    # build
    cmdBuild(@[])

  of "4":
    # build --release
    cmdBuild(@["--release"])

  of "5":
    # run
    cmdRun(@[])

  of "6":
    # test
    let verbose = prompt("Verbose output? (y/N): ")
    cmdTest((if verbose == "y" or verbose == "Y": @["-v"] else: @[]))

  of "7":
    # check
    let all = prompt("Check all files? (y/N): ")
    cmdCheck((if all == "y" or all == "Y": @["--all"] else: @[]))

  of "8":
    # clean
    let docs = prompt("Also remove docs? (y/N): ")
    cmdClean((if docs == "y" or docs == "Y": @["--docs"] else: @[]))

  of "9":
    # deps
    let tree = prompt("Show as tree? (y/N): ")
    cmdDeps((if tree == "y" or tree == "Y": @["--tree"] else: @[]))

  of "10":
    # add dependency
    let pkgName = prompt("Package name: ")
    if pkgName.len == 0:
      echo "Cancelled."
      return
    let version = prompt("Version constraint (optional): ")
    var args = @[pkgName]
    if version.len > 0:
      args.add(version)
    cmdAdd(args)

  of "11":
    # remove dependency
    let pkgName = prompt("Package name to remove: ")
    if pkgName.len == 0:
      echo "Cancelled."
      return
    cmdRemove(@[pkgName])

  of "12":
    # task
    let pkg = getPackageInfo(nimblePath)
    if pkg.tasks.len == 0:
      echo "No tasks defined in .nimble file."
      return
    echo ""
    for i, task in pkg.tasks:
      echo fmt"  [{i+1}] {task.name:12s} {task.description}"
    echo ""
    let taskChoice = prompt("Task number (or name): ")
    if taskChoice.len == 0:
      echo "Cancelled."
      return
    # Check if it's a number
    var isNum = true
    for c in taskChoice:
      if c < '0' or c > '9':
        isNum = false
        break
    if isNum:
      let num = parseInt(taskChoice)
      if num >= 1 and num <= pkg.tasks.len:
        cmdTask(@[pkg.tasks[num-1].name])
      else:
        echo "Invalid task number."
    else:
      cmdTask(@[taskChoice])

  of "13":
    # ide
    cmdIDE(@["vscode"])

  else:
    echo "Unknown choice."

proc main() =
  let args = commandLineParams()

  if args.len == 0:
    runInteractive()
    return

  let cmd = args[0]
  let cmdArgs = args[1..^1]

  case cmd
  of "new", "create", "n":
    cmdNew(cmdArgs)
  of "build", "b":
    cmdBuild(cmdArgs)
  of "run", "r":
    cmdRun(cmdArgs)
  of "test", "t":
    cmdTest(cmdArgs)
  of "check":
    cmdCheck(cmdArgs)
  of "clean":
    cmdClean(cmdArgs)
  of "deps":
    cmdDeps(cmdArgs)
  of "add":
    cmdAdd(cmdArgs)
  of "remove", "rm":
    cmdRemove(cmdArgs)
  of "task", "tasks":
    cmdTask(cmdArgs)
  of "init":
    cmdInit()
  of "ide":
    cmdIDE(cmdArgs)
  of "help", "-h", "--help":
    printUsage()
  else:
    echo "Unknown command: ", cmd
    echo "Run 'nimkit help' for usage information."
    quit(1)

when isMainModule:
  main()
