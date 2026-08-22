# Configuration

nimkit uses standard `.nimble` files as its configuration format. No new config files, no new syntax.

## What nimkit reads from .nimble

| Field | Type | Usage in nimkit |
|-------|------|-----------------|
| `name` | string | Project name, used as binary name fallback |
| `version` | string | Displayed in `deps --tree` |
| `srcDir` | string | Source directory for build/check (default: `src`) |
| `bin` | `@["name"]` | Primary binary target(s) |
| `requires` | string(s) | Dependencies shown by `nimkit deps` |
| `task` definitions | `task name, "desc":` | Executed by `nimkit task` |
| `skipDirs` | `@["..."]` | Parsed but not used by nimkit |
| `skipFiles` | `@["..."]` | Parsed but not used by nimkit |
| `skipExt` | `@["..."]` | Parsed but not used by nimkit |
| `installFiles` | `@["..."]` | Parsed but not used by nimkit |
| `installDirs` | `@["..."]` | Parsed but not used by nimkit |
| `installExt` | `@["..."]` | Parsed but not used by nimkit |
| `dim` | `@["..."]` | Parsed but not used by nimkit |

Fields like `author`, `description`, and `license` are parsed but not used by nimkit's commands.

## How nimkit reads .nimble (nimble-native)

nimkit **reuses Nimble** for package info — it doesn't reimplement NimScript.

1. **Primary path:** `nimble dump --json` is run in the project directory. Nimble evaluates the full NimScript (variables, `when defined(...)`, `exec`, procedures) and returns structured JSON. nimkit converts that JSON to its internal `NimblePackage` (`name`, `version`, `srcDir`, `bin`, `requires`, etc.).
2. **Fallback path:** If nimble isn't in `PATH` or `dump` fails, nimkit falls back to a fast manual parser.

This means NimScript features work out of the box when nimble is present, with no limitations. The manual parser is only a fallback for offline/CI environments without nimble.

### Manual parser (fallback)

When nimble isn't available, nimkit handles:

**Simple key = value:**
```nim
name = "myapp"
version = "1.0.0"
srcDir = "src"
```

**Array values:**
```nim
bin = @["myapp"]
skipDirs = @["nimcache", "tests"]
```

**Requires statements (no = sign):**
```nim
requires "nim >= 2.0.0"
requires "jsony >=1.0.0"
requires "unittest2"
```

**Task definitions:**
```nim
task build, "Build the project":
  nim c -d:release --path:src src/myapp.nim

task test, "Run tests":
  nim c -r --path:src tests/t_example.nim
```

**Inline comments, block comments (`#`), trailing semicolons (`;`).**

### What the fallback parser does NOT handle

These NimScript constructs are only handled via `nimble dump` (i.e., when nimble is installed):

**Conditional logic:**
```nim
when defined(windows):
  bin = @["myapp.exe"]
else:
  bin = @["myapp"]
```

**Variable interpolation:**
```nim
let myVersion = "1.0.0"
version = myVersion
```

**Multi-line strings, `exec` calls, procedures.**

### What this means in practice

- With nimble installed (default with Nim): all `.nimble` files work, including NimScript-heavy ones.
- Without nimble: simple `.nimble` files still work via the fallback parser; NimScript-heavy files fall back to defaults (`srcDir="src"`, etc.) and you can still use `nimkit add`/`remove` for simple edits.

## Security limits

The parser enforces safety limits on `.nimble` files:

| Limit | Value | Reason |
|-------|-------|--------|
| Max file size | 1 MB | Prevents memory exhaustion |
| Max task body lines | 100 | Prevents excessive execution |
| Max task body line length | 1024 chars | Prevents command injection |
| Max task description | 256 chars | Prevents display overflow |
| Max version constraint | 128 chars | Prevents injection |

## Project name rules

Project names (and binary names) must match:

```
^[a-zA-Z][a-zA-Z0-9_-]*$
```

Additionally:
- 1-64 characters
- No path separators (`/`, `\`, `:`)
- No `..` (path traversal)
- No Windows reserved names (`CON`, `NUL`, `PRN`, `COM1`-`COM9`, `LPT1`-`LPT9`)
- No shell metacharacters (`"`, `'`, `` ` ``, `$`, `&`, `|`, `;`, `<`, `>`, etc.)

## Source directory rules

The `srcDir` field is validated as a safe relative path:

- Must be relative (no absolute paths)
- No `..` components
- Each path component must match `[a-zA-Z0-9_.-]+`
- No colons, null bytes, or control characters

If the parser detects a malicious `srcDir`, it silently falls back to `"src"`.

## Version constraint rules

Version constraints in `nimkit add` are validated:

- Characters: alphanumeric, `.`, `-`, `_`, `,`, `>`, `<`, `=`, `!`, `~`, `^`, `*`, spaces
- No path separators, shell metachars, or quotes
- No `..` patterns
- Max 128 characters

Examples of valid constraints:
- `>=1.0.0`
- `>= 1.0.0 & < 2.0.0`
- `==1.2.3`
- `>= 2.0`
- `*` (any version)

## Migration from Nimble-only projects

If you already have a Nimble project, nimkit works with it immediately:

1. Place the `nimkit` binary in your PATH
2. `cd` into your project directory
3. Run `nimkit build`, `nimkit test`, etc.

You don't need to modify your `.nimble` file at all. nimkit reads the fields it understands and ignores the rest.
