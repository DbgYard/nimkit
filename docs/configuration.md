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

## Parser behavior

nimkit uses a **simplified parser**, not a full NimScript evaluator. It handles:

### Supported syntax

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

**Inline comments:**
```nim
name = "myapp" # This is a comment
```

**Block comments:**
```nim
# This entire line is skipped
```

**Trailing semicolons:**
```nim
name = "myapp";  # Semicolon is stripped
```

### What the parser does NOT handle

Since nimkit's parser is not a NimScript evaluator, these constructs will not work:

**Conditional logic:**
```nim
# NOT SUPPORTED
when defined(windows):
  bin = @["myapp.exe"]
else:
  bin = @["myapp"]
```

**Variable interpolation:**
```nim
# NOT SUPPORTED
let myVersion = "1.0.0"
version = myVersion
```

**Multi-line strings:**
```nim
# NOT SUPPORTED
description = """
  A very long
  description
"""
```

**exec calls:**
```nim
# NOT SUPPORTED
exec "nim c src/myapp.nim"
```

**Procedures and functions:**
```nim
# NOT SUPPORTED
proc getBinName(): string =
  return "myapp"

bin = @[getBinName()]
```

### What this means in practice

Most standard `.nimble` files work fine. Nimble files are typically simple key-value assignments. The parser handles all the common patterns you'll encounter.

If your `.nimble` file uses advanced NimScript features, nimkit may not parse it correctly. In that case, you can:

1. Keep using nimble for publishing and advanced features
2. Use nimkit for local development commands
3. Both tools read the same `.nimble` file — simple fields will work with both

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
