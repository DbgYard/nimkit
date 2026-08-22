# Getting Started

## Prerequisites

- **Nim >= 2.0.0** — install via [choosenim](https://github.com/dom96/choosenim)

That's it. nimkit has zero external dependencies.

## Installation

### One-liner (recommended)

**Linux / macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.sh | sh
# or: sh scripts/install.sh --from-source --tag nightly
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.ps1 | iex
# or with flags:  powershell -File scripts/install.ps1 -FromSource -Tag nightly
```

Installs to `~/.nimkit/bin` (`%USERPROFILE%\.nimkit\bin` on Windows) and adds it to your PATH persistently (shell rcs on Unix, user `Path` env var on Windows). Tries a pre-built `nightly` binary first, falls back to `nim c` from source.

To uninstall:

```bash
curl -fsSL https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/uninstall.sh | sh
# Windows: irm https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/uninstall.ps1 | iex
```

### From source (manual)

```bash
git clone https://github.com/DbgYard/nimkit.git
cd nimkit
nim c --path:src -o:nimkit src/nimkit.nim
```

The resulting `nimkit` binary (or `nimkit.exe` on Windows) can be placed anywhere on your PATH.

### Verify installation

```bash
nimkit help
```

## Your first project

### Option A: Create a new project

```bash
nimkit new hello
cd hello
```

This scaffolds:

```
hello/
├── hello.nimble        # Package definition (version 0.1.0, MIT)
├── src/
│   └── hello.nim       # Main source with echo "Hello from hello!"
├── tests/
│   ├── thello.nim      # Basic test suite
│   └── config.nims     # Sets --path for test imports
├── .gitignore          # Ignores nimcache, binaries, IDE files
└── README.md           # Minimal readme
```

### Option B: Initialize an existing directory

```bash
cd my-existing-project
nimkit init
```

Creates a `.nimble` file named after the directory and the `src/`/`tests/` structure.

### Option C: Adapt an existing project

If you already have a `.nimble` file, nimkit works with it immediately — no migration needed.

## Build and run

```bash
nimkit build              # Debug build → produces src/hello.exe (or ./hello on Unix)
nimkit build --release    # Release build → -d:release --opt:speed
nimkit run                # Build + execute
nimkit run -- --name world   # Pass args to the binary
```

## Run tests

Place test files in `tests/` with names starting with `t`:

```bash
nimkit test               # Run all tests (tests/t*.nim)
nimkit test -v            # Verbose: print output of failed tests
```

## Check your code

```bash
nimkit check              # Type-check the main source file only
nimkit check --all        # Type-check every .nim in src/
```

Output is color-coded: `[OK]`, `[WARN]`, or `[ERROR]` for each file.

## Manage dependencies

```bash
nimkit deps               # List dependencies from .nimble
nimkit deps --tree        # Tree view with box-drawing characters
nimkit add jsony          # Add dependency (no version)
nimkit add jsony >=1.1.0  # Add with version constraint
nimkit remove jsony       # Remove a dependency
```

## Clean up

```bash
nimkit clean              # Remove nimcache/ and binaries
nimkit clean --docs       # Also remove doc/ and htmldocs/
nimkit clean --all        # Remove everything (nimcache + docs + binaries + test binaries)
```

## Define and run tasks

Add tasks to your `.nimble` file:

```nim
task greet, "Say hello":
  echo "Hello from the task!"

task bench, "Run benchmarks":
  nim c -r --d:release --path:src tests/bench.nim
```

Then:

```bash
nimkit task          # List all tasks
nimkit task greet    # Run a specific task
```

## Workflow example

```bash
# Create project
nimkit new mylib --lib
cd mylib

# Add a dependency
nimkit add jsony >=2.0.0

# Write code
cat > src/mylib.nim << 'EOF'
import jsony

proc toJson*[T](val: T): string =
  val.toJson()
EOF

# Check, build, test
nimkit check --all
nimkit build
nimkit test

# Clean and rebuild for release
nimkit clean
nimkit build --release
```
