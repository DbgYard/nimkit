import std/[os, strutils]

const
  WindowsReservedNames = [
    "con", "prn", "aux", "nul",
    "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
    "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"
  ]

proc isAlphaAscii(c: char): bool =
  (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')

proc isAlphaNumAscii(c: char): bool =
  isAlphaAscii(c) or (c >= '0' and c <= '9')

proc matchesProjectPattern(s: string): bool =
  if s.len == 0: return false
  if not isAlphaAscii(s[0]): return false
  for c in s:
    if not (isAlphaNumAscii(c) or c == '_' or c == '-'):
      return false
  return true

proc matchesSrcComponent(s: string): bool =
  if s.len == 0: return false
  for c in s:
    if not (isAlphaNumAscii(c) or c == '_' or c == '-' or c == '.'):
      return false
  # Must not be "." or ".." and must not start with dot? Allow dot for extensions but not hidden?
  if s == "." or s == "..": return false
  return true

proc matchesVersionCharset(s: string): bool =
  for c in s:
    if c == ' ' or c == '\t': continue
    if isAlphaNumAscii(c) or c == '.' or c == '-' or c == '_' or c == ',' or c == '>' or c == '<' or c == '=' or c == '!' or c == '~' or c == '^' or c == '*':
      continue
    return false
  return true

proc isValidProjectName*(name: string): bool =
  if name.len == 0 or name.len > 64:
    return false
  if '/' in name or '\\' in name or ':' in name:
    return false
  if name == "." or name == "..":
    return false
  if ".." in name:
    return false
  if not matchesProjectPattern(name):
    return false
  let lower = name.toLowerAscii()
  for reserved in WindowsReservedNames:
    if lower == reserved:
      return false
  for c in ['"', '\'', '`', '$', '&', '|', ';', '<', '>', '(', ')', '*', '?', '!', '~', '#', '%', '^']:
    if c in name:
      return false
  return true

proc isValidPackageName*(name: string): bool =
  return isValidProjectName(name)

proc isValidTaskName*(name: string): bool =
  if name.len == 0 or name.len > 64:
    return false
  if not matchesProjectPattern(name):
    return false
  return true

proc isValidSrcDir*(srcDir: string): bool =
  if srcDir.len == 0 or srcDir.len > 256:
    return false
  if isAbsolute(srcDir):
    return false
  for c in srcDir:
    if c.ord < 32 or c.ord == 127:
      return false
  let normalized = normalizedPath(srcDir)
  for part in normalized.split({'/', '\\'}):
    if part == "..":
      return false
    if part.len == 0:
      continue
    if part == ".":
      continue
    if not matchesSrcComponent(part):
      return false
  if ".." in srcDir:
    return false
  if ":" in srcDir:
    return false
  return true

proc isValidBinName*(name: string): bool =
  return isValidProjectName(name)

proc isValidVersionConstraint*(s: string): bool =
  if s.len == 0:
    return true
  if s.len > 128:
    return false
  for c in s:
    if c.ord < 32 or c.ord == 127:
      return false
  if not matchesVersionCharset(s):
    return false
  if ".." in s or "/" in s or "\\" in s:
    return false
  # Reject shell metachars that slipped through charset
  if '"' in s or '\'' in s or '`' in s or '$' in s or '&' in s or '|' in s or ';' in s:
    return false
  return true

proc isPathInsideBase*(base, target: string): bool =
  let baseAbs = absolutePath(base)
  let targetAbs = absolutePath(target)
  let baseNorm = normalizedPath(baseAbs)
  let targetNorm = normalizedPath(targetAbs)
  let baseWithSep =
    if baseNorm.endsWith(DirSep): baseNorm else: baseNorm & DirSep
  return targetNorm == baseNorm or targetNorm.startsWith(baseWithSep)

proc safeJoin*(base, child: string): string =
  if child.len == 0:
    return ""
  if isAbsolute(child):
    return ""
  if ".." in child:
    let joined = base / child
    if not isPathInsideBase(base, joined):
      return ""
    return ""
  let joined = base / child
  if not isPathInsideBase(base, joined):
    return ""
  return joined

proc quoteShellArg*(arg: string): string =
  return quoteShell(arg)

proc validateDirParam*(dir: string): bool =
  if dir.len == 0:
    return true
  if dir.len > 512:
    return false
  for c in dir:
    if c.ord < 32 or c.ord == 127:
      return false
  if '"' in dir or '\'' in dir or '`' in dir or '$' in dir or '|' in dir or ';' in dir or '&' in dir:
    return false
  if dir.contains('\0'):
    return false
  return true
