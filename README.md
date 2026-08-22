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

- **Single binary, zero deps** — built from Nim stdlib only (nimble is reused at runtime, not bundled)
- **`.nimble` is the config** — no new format to learn; works with existing projects
- **Nimble-native** — delegates `build`/`test`/`task`/`dump` to nimble for full NimScript support
- **No publishing features** — focused entirely on local dev workflow
- **Safe by default** — path traversal prevention, shell injection protection, input validation everywhere

## Quick start

### Install (one-liner)

**Linux / macOS:**

```bash
curl -fsSL https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.sh | sh
```

**Windows (PowerShell):**

```powershell
irm https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.ps1 | iex
```

Both add `~/.nimkit/bin` (`%USERPROFILE%\.nimkit\bin` on Windows) to your PATH so `nimkit` is available in new terminals. They try to download a pre-built `nightly` binary first, then fall back to building from source (requires `nim >= 2.0.0` + `git`).

**Options:**

```bash
# Build from source even if a binary exists
curl -fsSL https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.sh | sh -s -- --from-source

# Install a specific release tag
curl -fsSL https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.sh | sh -s -- --tag v0.1.0
```

```powershell
# Windows equivalents
irm https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.ps1 | iex; Install-Nimkit -FromSource
iex "& { $(irm https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.ps1) } -Tag v0.1.0"
```

**Uninstall:**

```bash
curl -fsSL https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/uninstall.sh | sh
# Windows:
irm https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/uninstall.ps1 | iex
```

See `scripts/` for local usage.

### Install from source (manual)

```bash
git clone https://github.com/DbgYard/nimkit.git
cd nimkit
nim c --path:src -o:nimkit src/nimkit.nim

# Add to PATH
# Linux/macOS: cp nimkit ~/.nimkit/bin/  (or /usr/local/bin/)
# Windows: copy nimkit.exe %USERPROFILE%\.nimkit\bin\
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
| `nimkit ide vscode` | Setup VS Code (settings, extensions, tasks) |

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

## IDE support

Set up VS Code with one command:

```bash
nimkit ide vscode
```

This creates `.vscode/` with:

- **`settings.json`** — Nim file associations, tab size, format-on-save
- **`extensions.json`** — Recommends the Nim VS Code extension
- **`tasks.json`** — Exports your `.nimble` tasks as VS Code build tasks

Existing `.vscode` files are synced (merged), not overwritten. New tasks from `.nimble` are appended to `tasks.json`.

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

nimkit **reuses Nimble** where it matters and doesn't reinvent the wheel:

- **Package info** (`name`, `version`, `srcDir`, `bin`, `requires`) is read via `nimble dump --json` for full NimScript evaluation (variables, conditionals, `when` branches). Falls back to a fast manual parser when nimble isn't available.
- **`nimkit build` / `test`** delegate to `nimble build` / `nimble test` when nimble is in PATH, so your NimScript `before build` hooks, backends (`c`/`cpp`/`js`), and `binDir` are respected. Falls back to direct `nim c` otherwise.
- **`nimkit task`** is `nimble <task>` under the hood — full NimScript `exec`, variables, and platform conditionals work out of the box.
- **`nimkit deps`** shows the evaluated `requires` list from nimble; `nimkit add`/`remove` still edits the `.nimble` file directly.

You can still use `nimble install`, `nimble publish`, etc. alongside nimkit. See [docs/configuration.md](docs/configuration.md) for parser details and fallback behaviour.

## Documentation

- [Getting Started](docs/getting-started.md) — Installation and first project
- [Commands](docs/commands.md) — Full command reference
- [Configuration](docs/configuration.md) — .nimble file format and parser behavior
- [Security](docs/security.md) — Security features and threat model
- [Contributing](docs/contributing.md) — How to contribute

## License

MIT
