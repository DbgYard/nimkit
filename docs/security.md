# Security

nimkit is designed with security as a primary concern. This document describes the threat model, protections, and security architecture.

## Threat model

nimkit operates on **user-authored project files** (.nimble, source code, test files). The primary threats are:

1. **Path traversal** — a malicious `.nimble` file or project name could cause nimkit to read/write/delete files outside the project directory
2. **Shell injection** — a malicious project name, binary name, or task command could execute arbitrary shell commands
3. **Input validation** — malformed or adversarial input could cause crashes, unexpected behavior, or security issues

## Protections

### Path traversal prevention

Every file operation in nimkit checks that the target path stays inside the project directory.

**Functions used:**

| Function | Purpose |
|----------|---------|
| `isPathInsideBase(base, target)` | Resolves both paths to absolute normalized form and checks that `target` starts with `base` (with trailing separator) |
| `safeJoin(base, child)` | Joins paths and returns empty string if result escapes base |

**Where it's checked:**

| Command | What's checked |
|---------|----------------|
| `new` | Project directory stays inside `cwd` or `--dir` |
| `build` | Source file stays inside project root |
| `run` | Binary path stays inside project root |
| `check` | Each source file stays inside project root |
| `test` | Each test file stays inside its discovery directory |
| `clean` | Every file/directory removed is validated |
| `task` | (Tasks execute arbitrary commands — see below) |

**Example:** If a `.nimble` file has `srcDir = "../../"`, nimkit detects the escape and either falls back to `"src"` or refuses to operate.

### Shell injection prevention

nimkit never constructs shell command strings from untrusted input. All external process invocations use `startProcess` with explicit argument arrays.

**Before (vulnerable):**
```nim
let cmd = "nim c --path:" & srcDir & " " & mainFile
execCmd(cmd)  # Shell interprets the string — injection possible
```

**After (secure):**
```nim
let args = @["c", "--path:" & srcDir, mainFile]
let p = startProcess("nim", args = args, options = {poUsePath})
let exitCode = p.waitForExit()
p.close()  # No shell involved
```

**What this prevents:**
- A `mainBin` of `"foo;calc"` would be executed as a command in a shell. With `startProcess`, it's passed as a single argument to `nim c` — which fails (no such file) instead of executing `calc`.

**Exception:** `nimkit task` executes task body lines through a shell by design (Nimble tasks are shell/NimScript commands). However:
- Task **names** are validated against `^[a-zA-Z][a-zA-Z0-9_-]*$`
- Body lines are length-limited (1024 chars) and count-limited (100 lines)
- Each command is printed before execution for transparency
- Null bytes in body lines are rejected

### Input validation

All user-facing inputs are validated through dedicated validators in `src/nimkit/security.nim`:

| Input | Validator | Rules |
|-------|-----------|-------|
| Project name | `isValidProjectName` | `^[a-zA-Z][a-zA-Z0-9_-]*$`, 1-64 chars, no reserved names, no shell metachars |
| Package name | `isValidPackageName` | Same as project name |
| Task name | `isValidTaskName` | Same as project name |
| Binary name | `isValidBinName` | Same as project name |
| Source directory | `isValidSrcDir` | Relative, no `..`, components match `[a-zA-Z0-9_.-]+` |
| Version constraint | `isValidVersionConstraint` | Whitelist charset, no `..`, no shell metachars |
| `--dir` parameter | `validateDirParam` | No null bytes, no shell metachars, max 512 chars |

**Windows reserved names** are explicitly blocked: `CON`, `PRN`, `AUX`, `NUL`, `COM1`-`COM9`, `LPT1`-`LPT9`.

**Shell metacharacters** blocked: `"`, `'`, `` ` ``, `$`, `&`, `|`, `;`, `<`, `>`, `(`, `)`, `*`, `?`, `!`, `~`, `#`, `%`, `^`.

### DoS protection

The `.nimble` parser enforces limits to prevent denial-of-service attacks via crafted config files:

| Limit | Value |
|-------|-------|
| Max `.nimble` file size | 1 MB |
| Max task body lines | 100 |
| Max task body line length | 1024 chars |
| Max task description | 256 chars |
| Max version constraint | 128 chars |
| Max source directory | 256 chars |
| Max project name | 64 chars |
| Max `--dir` value | 512 chars |

### File operation safety

The `clean` command uses additional protections:

- **Root directory protection:** Refuses to remove paths shorter than 4 characters (prevents accidentally removing `/`)
- **Project root protection:** Refuses to remove the project root itself
- **Binary validation:** Only removes files that match expected patterns (not `.nim` files)
- **Path containment:** Every removal is validated against `isPathInsideBase`

### Test file safety

The test runner validates discovered test files:

- Rejects filenames with shell metachars (`;`, `&`, `|`, `` ` ``, `$`)
- Validates each discovered path stays inside the test directory
- Validates filename against `isValidTaskName`
- Uses `startProcess` (not shell) for test execution

## Security audit checklist

For anyone reviewing nimkit's security:

- [x] No `execCmd` or `execCmdEx` with string interpolation (all process execution via `startProcess`)
- [x] No path operations without containment checks
- [x] All user input validated before use
- [x] Windows reserved names blocked
- [x] Shell metacharacters rejected in all identifiers
- [x] Null bytes rejected
- [x] Control characters rejected
- [x] File size limits on config parsing
- [x] Line count and length limits on task bodies
- [x] `clean` protects against root directory deletion
- [x] Test discovery validates paths and names
- [x] No command output used in shell interpolation

## Known limitations

1. **Task execution is not sandboxed.** Task body lines are executed through the system shell. If you run a malicious task from an untrusted `.nimble` file, it can execute arbitrary commands. This is by design — Nimble tasks are intended to run arbitrary commands.

2. **Source code is not sandboxed.** nimkit compiles and runs your Nim source code. If your source code is malicious, it will execute. This is also by design — nimkit is a development tool for your own code.

3. **The `.nimble` parser is simplified.** It doesn't evaluate NimScript. If a `.nimble` file uses advanced features (conditionals, exec calls, variable interpolation), the parser may not extract all fields correctly. This is a correctness limitation, not a security one — unparseable fields are ignored or fall back to defaults.

## Reporting security issues

If you discover a security vulnerability in nimkit, please report it responsibly. Do not open a public GitHub issue. Instead, email [your email] with:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will respond within 72 hours and work with you on a fix before public disclosure.
