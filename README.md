# nimkit

A cargo-like project lifecycle tool for Nim. Create, build, test, and manage Nim projects with a single CLI — no external dependencies, no Nimble overhead.

```
nimkit new myapp
cd myapp
nimkit build
nimkit test
nimkit run
```

## Why nimkit?

Nim already has Nimble for package management. nimkit fills a different role: **local project lifecycle**. Think of it as `cargo` (build/run/test) layered on top of `.nimble` files, without replacing or conflicting with Nimble itself.

- **Single binary, zero deps** — built from Nim stdlib only
- **`.nimble` is the config** — no new format to learn; works with existing projects
- **No publishing features** — focused entirely on local dev workflow
- **Safe by default** — path traversal prevention, shell injection protection, input validation everywhere

## Quick start

### Install from source

```bash
# Clone the repo
git clone https://github.com/yourname/nimkit.git
cd nimkit

# Build and install
nim c --path:src -o:nimkit src/nimkit.nim

# (Optional) Add to PATH
# Linux/macOS: cp nimkit /usr/local/bin/
# Windows: add the build directory to PATH
```

### Create your first project

```bash
nimkit new hello
cd hello
nimkit run
# → Hello from hello!
```

This creates:

```
hello/
  hello.nimble        # Package definition
  src/hello.nim       # Main source file
  tests/thello.nim    # Test file
  .gitignore
  README.md
```

### Build, test, run

```bash
nimkit build              # Compile debug build
nimkit build --release    # Compile with -d:release --opt:speed
nimkit test               # Discover and run tests in tests/
nimkit run                # Build then execute
nimkit run -- --flag val  # Pass arguments to the binary
nimkit check --all        # Type-check all source files
nimkit clean              # Remove nimcache, binaries
```

## Commands

| Command | Description |
|---------|-------------|
| `nimkit new <name>` | Create a new project |
| `nimkit build [--release]` | Compile the project |
| `nimkit run [args]` | Build and run |
| `nimkit test [-v]` | Run all tests |
| `nimkit check [-a]` | Type-check source files |
| `nimkit clean [-d]` | Remove build artifacts |
| `nimkit deps [-t]` | List dependencies |
| `nimkit add <pkg> [ver]` | Add a dependency |
| `nimkit remove <pkg>` | Remove a dependency |
| `nimkit task [name]` | List or run tasks |
| `nimkit init` | Initialize in current directory |

See [docs/commands.md](docs/commands.md) for the full reference.

## Tasks

Define tasks in your `.nimble` file:

```nim
task build, "Build the project":
  nim c --path:src src/myapp.nim

task test, "Run unit tests":
  nim c -r --path:src tests/t_example.nim

task bench, "Run benchmarks":
  nim c -r --path:src --d:release tests/bench.nim
```

Then:

```bash
nimkit task          # List available tasks
nimkit task bench    # Run a specific task
```

## Project structure

nimkit works alongside Nimble. It reads your existing `.nimble` file to determine the project name, source directory, binary targets, and dependencies. You don't need to change anything if you already have a `.nimble` file.

Key fields nimkit reads:

| Field | Usage |
|-------|-------|
| `name` | Project name (used as binary name fallback) |
| `srcDir` | Source directory (default: `src`) |
| `bin` | Binary target(s) |
| `requires` | Dependencies (displayed by `nimkit deps`) |
| `task` definitions | Executed by `nimkit task` |

## Security

nimkit validates all inputs and prevents common attack vectors:

- **Path traversal** — project names, binary names, and source directories are validated to prevent `../` escapes
- **Shell injection** — all external commands use `startProcess` with explicit arguments, never shell string concatenation
- **Input validation** — project names, package names, task names, and version constraints are checked against strict patterns
- **Reserved names** — Windows device names (CON, NUL, PRN, etc.) are blocked

See [docs/security.md](docs/security.md) for details.

## Nimble compatibility

nimkit **reads** `.nimble` files and **generates** `.nimble` files. It does not replace Nimble — you can still use `nimble install`, `nimble publish`, etc. nimkit adds its own task definitions and lifecycle commands on top.

**Parser note:** nimkit uses a simplified parser for `.nimble` files. It handles `key = value`, `requires`, `task` definitions, `@[]` arrays, and inline comments. It does not evaluate full NimScript. See [docs/configuration.md](docs/configuration.md) for what works and what doesn't.

## Documentation

- [Getting Started](docs/getting-started.md) — Installation and first project
- [Commands](docs/commands.md) — Full command reference
- [Configuration](docs/configuration.md) — .nimble file format and parser behavior
- [Security](docs/security.md) — Security features and threat model
- [Contributing](docs/contributing.md) — How to contribute

## License

MIT
