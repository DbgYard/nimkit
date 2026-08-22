# scripts

Cross-platform install / uninstall scripts for nimkit.

## Quick install

### Linux / macOS (sh)

```bash
# from the web (one-liner)
curl -fsSL https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.sh | sh

# local
sh scripts/install.sh
sh scripts/install.sh --from-source
sh scripts/install.sh --tag v0.1.0 --prefix /usr/local
```

### Windows (PowerShell)

```powershell
# from the web
irm https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.ps1 | iex

# local
powershell -ExecutionPolicy Bypass -File scripts/install.ps1
powershell -File scripts/install.ps1 -FromSource -Tag v0.1.0
```

## What the installers do

1. **Detect platform** (`uname -s` / `$env:PROCESSOR_ARCHITECTURE` → `nimkit-linux-amd64`, `nimkit-macos-arm64`, `nimkit-windows-amd64.exe`)
2. **Try download** from `https://github.com/DbgYard/nimkit/releases/download/<tag>/<asset>` (default `tag=nightly`)
   - uses `curl` or `wget` (sh) / `Invoke-WebRequest` (ps1), with TLS 1.2 on Windows
3. **Fallback to source build** if download fails or `--from-source` is given:
   - checks `nim >= 2.0.0` and `git`
   - `git clone --depth 1 https://github.com/DbgYard/nimkit.git` to a temp dir
   - `nim c --path:src -o:nimkit src/nimkit.nim` and copies to `~/.nimkit/bin` (`%USERPROFILE%\.nimkit\bin`)
4. **Add to PATH persistently**
   - **sh:** appends `export PATH="$HOME/.nimkit/bin:$PATH"` to `~/.bashrc`/`~/.zshrc`/`~/.profile`/`~/.bash_profile` (and `fish_add_path` to `~/.config/fish/config.fish`), idempotent
   - **ps1:** adds to user `Path` via `[Environment]::SetEnvironmentVariable("Path",…, "User")` and updates `$env:Path` for the current session

Install dir defaults to `~/.nimkit/bin` (`%USERPROFILE%\.nimkit\bin`). Override with `--prefix` / `-Prefix`.

## Uninstall

```bash
sh scripts/uninstall.sh
# or: curl -fsSL https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/uninstall.sh | sh
```
```powershell
powershell -File scripts/uninstall.ps1
# or: irm https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/uninstall.ps1 | iex
```

- Removes `~/.nimkit/bin/nimkit` (and empty `~/.nimkit/bin`, `~/.nimkit`)
- Cleans PATH entries from shell rcs (`# nimkit` block) on Unix
- Removes the dir from the user `Path` env var on Windows

Use `--prefix` / `-Prefix` if you installed elsewhere.

## Updating

Re-run the same installer — it **always overwrites** the existing binary:

```bash
# update to latest nightly
curl -fsSL https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.sh | sh
# update/downgrade to a specific tag
sh scripts/install.sh --tag v0.2.0
# force rebuild from source and overwrite
sh scripts/install.sh --from-source --tag v0.2.0
```
```powershell
irm https://raw.githubusercontent.com/DbgYard/nimkit/master/scripts/install.ps1 | iex  # update nightly
powershell -File scripts/install.ps1 -Tag v0.2.0                    # update to v0.2.0
powershell -File scripts/install.ps1 -FromSource -Force             # rebuild and overwrite
```

If a binary already exists at the install dir, the installer prints `Existing installation ... - updating to <tag>`, removes the old file, then downloads/builds the new version. `--force`/`-Force` is accepted but not required (overwrite is default).

## Options

| Flag | sh | ps1 | Description |
|------|----|-----|-------------|
| `--from-source` / `-FromSource` | ✅ | ✅ | Force source build |
| `--force` / `-Force` | ✅ | ✅ | Force overwrite (default: always overwrites, flag for explicitness) |
| `--tag <tag>` / `-Tag <tag>` | ✅ | ✅ | Release tag (default `nightly`) |
| `--prefix <dir>` / `-Prefix <dir>` | ✅ | ✅ | Install dir |
| `--help` / `-Help` | ✅ | ✅ | Help |

## Requirements for source build

- `nim >= 2.0.0` (`choosenim` recommended)
- `git`

If missing, the installer exits with a helpful message.

## Security

- Install scripts are plain `sh`/`ps1` — audit them before piping to `sh`/`iex`
- Download is over HTTPS from `github.com/DbgYard/nimkit/releases`
- Fallback build compiles from the cloned repo; no opaque binaries
