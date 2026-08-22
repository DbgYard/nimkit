# Command Reference

All commands require a `.nimble` file in the current directory (except `new`, `init`, and `help`).

---

## `new` (aliases: `create`, `n`)

Create a new project.

```
nimkit new <name> [--lib] [--dir <path>]
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `<name>` | yes | Project name. Must match `^[a-zA-Z][a-zA-Z0-9_-]*$`, 1-64 characters. |

**Flags:**

| Flag | Description |
|------|-------------|
| `--lib` | Create a library project (description says "library" instead of "application") |
| `--dir <path>` | Create the project inside the given directory instead of the current directory |

**Examples:**

```bash
nimkit new myapp                    # Create app in ./myapp/
nimkit new mylib --lib              # Create library in ./mylib/
nimkit new myapp --dir /tmp         # Create app in /tmp/myapp/
```

**Files created:**

- `<name>.nimble` — Package definition
- `src/<name>.nim` — Main source file with hello-world
- `tests/t<name>.nim` — Test file with one basic test
- `tests/config.nims` — Sets `--path` for test imports
- `.gitignore` — Ignores build artifacts
- `README.md` — Minimal readme

---

## `build` (alias: `b`)

Compile the project's main binary.

```
nimkit build [--release]
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--release` | Build with `-d:release --opt:speed` (optimized) |

**How it works:**

- If `nimble` is available: runs `nimble build -y` (with `-d:release --opt:speed` for `--release`). This respects NimScript `srcDir`, `bin`, `binDir`, backend, and `before build` hooks for full compatibility.
- Otherwise: reads `srcDir`/`bin` from `.nimble` (fallback parser) and compiles `<srcDir>/<bin>.nim` with `nim c`.
- On success, the binary is placed in the project root (or `src/`/`bin/` depending on nim/nimble defaults)

**Exit code:** The Nim/nimble compiler's exit code.

---

## `run` (alias: `r`)

Build and execute the project binary.

```
nimkit run [--release] [-- <args>]
```

**Flags:**

| Flag | Description |
|------|-------------|
| `--release` | Build with release optimizations before running |
| `-- <args>` | Arguments passed to the built binary (everything after `--`) |

**Examples:**

```bash
nimkit run                         # Build + run
nimkit run --release               # Build release + run
nimkit run -- --config prod.yml    # Pass arguments to the binary
nimkit run -- --port 8080 --host localhost
```

---

## `test` (alias: `t`)

Discover and run tests.

```
nimkit test [--verbose]
```

**Flags:**

| Flag | Short | Description |
|------|-------|-------------|
| `--verbose` | `-v` | Print full output of failing tests |

**How it works:**

- If `nimble` is available: runs `nimble test -y` (full NimScript support).
- Otherwise: discovers tests manually:

**Test discovery (fallback):**

- Scans the `tests/` directory (non-recursive)
- Matches files: `t*.nim` where the name has at least 2 characters
- Examples: `tests/thello.nim`, `tests/t_my_module.nim`, `tests/test_stuff.nim`
- Non-matching files are silently ignored

**Output:**

```
Running 3 test(s)...

[PASS] thello.nim (0.123s)
[PASS] t_parser.nim (0.456s)
[FAIL] t_network.nim (1.234s)
  Error: connection refused

Results: 2 passed, 1 failed, 3 total (1.813s)
```

**Exit code:** 0 if all tests pass, 1 if any fail.

---

## `check`

Run `nim check` (type-checking without code generation).

```
nimkit check [--all] [--hints]
```

**Flags:**

| Flag | Short | Description |
|------|-------|-------------|
| `--all` | `-a` | Check all `.nim` files in `src/` recursively |
| `--hints` | -- | Show hint messages (accepted for compatibility; hints are filtered by default) |

**Default mode:** Checks only the main source file.

**`--all` mode:**

```
Checking 4 file(s)...
[OK]    src/parser.nim
[WARN]  src/utils.nim
[OK]    src/main.nim
[ERROR] src/broken.nim
  Error: type mismatch

Check failed: 1 error(s), 1 warning(s)
```

**Exit code:** 0 on success, 1 if any file had errors.

---

## `clean`

Remove build artifacts.

```
nimkit clean [--docs] [--all]
```

**Flags:**

| Flag | Short | Description |
|------|-------|-------------|
| `--docs` | `-d` | Also remove `doc/` and `htmldocs/` directories |
| `--all` | `-a` | Remove everything: nimcache, docs, binaries, test binaries |

**What gets cleaned:**

| Artifact | `clean` | `clean --docs` | `clean --all` |
|----------|---------|----------------|---------------|
| `nimcache/` | yes | yes | yes |
| `src/nimcache/` | yes | yes | yes |
| `doc/` | no | yes | yes |
| `htmldocs/` | no | yes | yes |
| Main binary (6 candidate paths) | yes | yes | yes |
| Test binaries (`tests/*.exe` etc.) | yes | yes | yes |

---

## `deps`

List project dependencies from the `.nimble` file.

```
nimkit deps [--tree]
```

**Flags:**

| Flag | Short | Description |
|------|-------|-------------|
| `--tree` | `-t` | Display dependencies in tree format |

**Simple list:**

```
Dependencies (3):
  jsony >=1.0.0
  unittest2
  asynctools
```

**Tree format:**

```
myapp v0.1.0
├── jsony >=1.0.0
├── unittest2
└── asynctools
```

Note: `nim` itself is filtered out. When `nimble` is available, dependencies are shown from `nimble dump --json` (evaluated NimScript); otherwise from the manual parser.

---

## `add`

Add a dependency to the `.nimble` file.

```
nimkit add <pkg> [version]
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `<pkg>` | yes | Package name |
| `[version]` | no | Version constraint (e.g., `>=1.1.0`, `==1.2.0`, `>= 2.0`) |

**Examples:**

```bash
nimkit add jsony
nimkit add jsony >=2.0.0
nimkit add unittest2 ==1.0.0
nimkit add "asynctools >= 0.1.0 & < 1.0"
```

If the package already exists, it prints the existing entry and does nothing.

**Version constraint syntax:**

- Characters allowed: `a-z`, `A-Z`, `0-9`, `.`, `-`, `_`, `,`, `>`, `<`, `=`, `!`, `~`, `^`, `*`, spaces
- Max 128 characters
- No path separators, shell metachars, or quotes

---

## `remove` (alias: `rm`)

Remove a dependency from the `.nimble` file.

```
nimkit remove <pkg>
```

**Arguments:**

| Argument | Required | Description |
|----------|----------|-------------|
| `<pkg>` | yes | Package name to remove |

The entire matching `requires` line is removed. If the package is not found, a message is printed but no error occurs.

---

## `task` (alias: `tasks`)

List or execute tasks defined in the `.nimble` file.

```
nimkit task [name]
```

**No arguments:** Lists all tasks with descriptions.

```
Tasks (3):
  build        Build the project
  test         Run unit tests
  bench        Run benchmarks
```

**With `<name>`:** Delegates to `nimble <task>` (full NimScript — `exec`, variables, `when` branches work). Falls back to manual listing only.

```bash
nimkit task bench
# Running task 'bench' via nimble...
# ...
```

**Exit code:** The task's exit code.

---

## `init`

Initialize nimkit in the current directory. For existing projects that don't have a `.nimble` file yet.

```
nimkit init
```

Creates:
- `<dirname>.nimble` — Basic package definition
- `src/` directory
- `tests/` directory
- `src/<dirname>.nim` — Hello world

If a `.nimble` file already exists, prints a message and does nothing.

---

## `help` (aliases: `-h`, `--help`)

Print the usage message and exit.

```
nimkit help
nimkit -h
nimkit --help
```

Running `nimkit` with no arguments also prints the usage message.
