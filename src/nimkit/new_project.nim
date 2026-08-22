import std/[os, strutils]
import nimkit/security

const
  defaultNimbleTemplate = """# Package
version       = "$1"
author        = "$2"
description   = "$3"
license       = "$4"
srcDir        = "src"
bin           = @["$5"]

# Dependencies
requires "nim >= 2.0.0"
"""

  defaultMainTemplate = """import std/[strutils]

proc main() =
  echo "Hello from $1!"

when isMainModule:
  main()
"""

  defaultTestTemplate = """import std/unittest
import $1

suite "$1":
  test "basic":
    check 1 + 1 == 2
"""

  defaultConfigNimsTemplate = """--path:"../$1/src"
"""

  defaultGitignoreTemplate = """# Nimble
nimcache/
nimblecache/

# Binaries
*.exe
*.out
*.app
bin/
build/

# IDE
.vscode/
.idea/

# OS
.DS_Store
Thumbs.db
"""

proc createProject*(name: string, isLib: bool = false, dir: string = "") =
  ## Create a new nimkit project.
  # Validate project name strictly
  if not isValidProjectName(name):
    echo "Error: invalid project name '", name, "'"
    echo "Name must match ^[a-zA-Z][a-zA-Z0-9_-]*$, 1-64 chars, no path separators or reserved names."
    quit(1)

  if dir.len > 0 and not validateDirParam(dir):
    echo "Error: invalid --dir value '", dir, "'"
    quit(1)

  let baseDir = if dir.len > 0: dir else: getCurrentDir()
  # For --dir, ensure baseDir doesn't contain shell metachars and is a plausible path
  let projectDir = baseDir / name

  # Path traversal check: projectDir must be inside baseDir after normalization
  let baseAbs = absolutePath(baseDir)
  let projAbs = absolutePath(projectDir)
  if not isPathInsideBase(baseAbs, projAbs):
    echo "Error: project path escapes base directory: ", projectDir
    quit(1)

  if dirExists(projectDir):
    echo "Error: directory '", projectDir, "' already exists"
    quit(1)

  echo "Creating project '", name, "'..."

  # Create directory structure
  createDir(projectDir)
  createDir(projectDir / "src")
  createDir(projectDir / "tests")

  # Write .nimble file
  let nimbleContent = defaultNimbleTemplate % [
    "0.1.0",
    "Author",
    (if isLib: "A new Nim library" else: "A new Nim application"),
    "MIT",
    name
  ]
  writeFile(projectDir / (name & ".nimble"), nimbleContent)

  # Write main source file
  let mainContent = defaultMainTemplate % [name]
  writeFile(projectDir / "src" / (name & ".nim"), mainContent)

  # Write test file
  let testContent = defaultTestTemplate % [name]
  writeFile(projectDir / "tests" / ("t" & name & ".nim"), testContent)

  # Write test config.nims
  let configContent = defaultConfigNimsTemplate % [name]
  writeFile(projectDir / "tests" / "config.nims", configContent)

  # Write .gitignore
  writeFile(projectDir / ".gitignore", defaultGitignoreTemplate)

  # Write basic README
  let readmeContent = "# " & name & "\n\nA new Nim project.\n\n## Build\n\n```\nnimkit build\n```\n\n## Test\n\n```\nnimkit test\n```\n"
  writeFile(projectDir / "README.md", readmeContent)

  echo "Done! Project created at: ", projectDir
  echo ""
  echo "Next steps:"
  echo "  cd ", name
  echo "  nimkit build"
  echo "  nimkit run"
