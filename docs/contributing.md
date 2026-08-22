# Contributing to nimkit

Thanks for your interest in contributing. nimkit is a small, focused tool — contributions that improve correctness, security, or usability are always welcome.

## Getting started

### Prerequisites

- **Nim >= 2.0.0** (install via [choosenim](https://github.com/dom96/choosenim))
- **Git**

### Clone and build

```bash
git clone https://github.com/yourname/nimkit.git
cd nimkit
nim c --path:src -o:nimkit.exe src/nimkit.nim
```

The build produces a single binary. No external dependencies.

### Verify

```bash
.\nimkit.exe new testproj
cd testproj
..\nimkit.exe build
..\nimkit.exe test
..\nimkit.exe run
cd ..
rmdir /s /q testproj
```

## Project layout

```
src/
  nimkit.nim                # Entry point — CLI dispatch, all cmd* procs
  nimkit/
    nimble_parser.nim       # .nimble file parser (key=value, requires, tasks)
    new_project.nim         # Scaffolding templates and createProject()
    build_project.nim       # Build orchestration (nim c via startProcess)
    test_runner.nim         # Test discovery (t*.nim) and execution
    security.nim            # Input validators, path safety, reserved names
docs/                       # User-facing documentation
tests/                      # (empty — manual testing for now)
```

## Code conventions

### Style

- **No comments** in code unless the user explicitly requests them
- **No external dependencies** — Nim stdlib only
- **camelCase** for procs and variables
- **PascalCase** for types
- **snake_case** for file names
- Keep functions short and focused — each proc should do one thing

### Error handling

- Error messages start with `"Error: "` and go to **stdout** (not stderr)
- Use `quit(1)` for fatal errors
- Return exit codes from child processes directly when appropriate

### Security

- **Never** use `execCmd` or `execCmdEx` with string interpolation — always `startProcess` with explicit args
- **Always** validate paths with `isPathInsideBase` before file operations
- **Always** validate user input (project names, package names, etc.) through `security.nim` validators
- Reject shell metacharacters (`"`, `'`, `` ` ``, `$`, `&`, `|`, `;`, `<`, `>`) in all identifiers
- Reject null bytes and control characters in all strings

### Parser

The `.nimble` parser is intentionally simplified. It handles:
- `key = value` and `key = @[...]` assignments
- `requires` statements (no `=` sign)
- `task name, "desc":` definitions with indented body
- Inline comments (` #`) and block comments (`#`)
- Trailing semicolons

It does **not** handle NimScript features (conditionals, exec, variables, multi-line strings). This is by design.

## What to work on

### High priority

- Bug fixes
- Security improvements
- Test coverage (unit tests for the parser, validators, etc.)
- Cross-platform compatibility fixes

### Medium priority

- New commands (if they fit the "local dev lifecycle" scope)
- Better error messages
- Documentation improvements

### Out of scope

- Package publishing features (Nimble already does this)
- Package registry integration
- Features that would require external dependencies

## Submitting changes

### Branch naming

- `fix/description` — bug fixes
- `feat/description` — new features
- `docs/description` — documentation changes
- `refactor/description` — code improvements without behavior changes

### Commit messages

Keep them short and descriptive:

```
fix: prevent path traversal via srcDir in .nimble
feat: add --filter flag to nimkit test
docs: update command reference for task command
refactor: extract validation into security module
```

### Pull request process

1. Fork the repository
2. Create a branch from `main`
3. Make your changes
4. Build and test manually (there are no automated tests yet)
5. Ensure `nim c --path:src -o:nimkit.exe src/nimkit.nim` compiles with **zero warnings**
6. Push and open a PR with a clear description of what changed and why

### PR description template

```markdown
## What

Brief description of the change.

## Why

Why this change is needed.

## How

How it works (if non-obvious).

## Testing

How you verified it works.
```

## Reporting bugs

Open a GitHub issue with:

1. **What you did** — steps to reproduce
2. **What happened** — actual output or error
3. **What you expected** — desired behavior
4. **Environment** — OS, Nim version (`nim --version`), nimkit version

## Security issues

Do **not** open a public issue for security vulnerabilities.

Instead, email [your email] or use GitHub's private vulnerability reporting. Include:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

We will respond within 72 hours and coordinate a fix before public disclosure.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
