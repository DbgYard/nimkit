import std/[os, strutils, strformat, json]
import nimkit/nimble_parser

const
  nimExtensions = [
    "nimsaem.nimvscode",
  ]

  nimSettingsJson = """{
  "files.associations": {
    "*.nim": "nim",
    "*.nims": "nims",
    "*.nimble": "nimble"
  },
  "nim.path": ["nim"],
  "nim.nimblePath": "~/.nimble/pkgs2",
  "editor.tabSize": 2,
  "editor.insertSpaces": true,
  "files.trimTrailingWhitespace": true,
  "files.insertFinalNewline": true,
  "[nim]": {
    "editor.tabSize": 2,
    "editor.formatOnSave": true
  }
}"""

proc jsonPretty*(j: JsonNode): string =
  result = ""
  proc aux(n: JsonNode, indent: int) =
    case n.kind
    of JNull: result &= "null"
    of JBool: result &= $n.getBool()
    of JFloat: result &= $n.getFloat()
    of JInt: result &= $n.getInt()
    of JString: result &= "\"" & n.getStr().replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t") & "\""
    of JArray:
      if n.len == 0:
        result &= "[]"
        return
      result &= "[\n"
      var idx = 0
      for item in n:
        result &= " ".repeat(indent + 2) & $item
        if idx < n.len - 1: result &= ","
        result &= "\n"
        inc idx
      result &= " ".repeat(indent) & "]"
    of JObject:
      if n.len == 0:
        result &= "{}"
        return
      result &= "{\n"
      var first = true
      for key, val in n:
        if not first: result &= ",\n"
        first = false
        result &= " ".repeat(indent + 2) & "\"" & key & "\": " & $val
      result &= "\n" & " ".repeat(indent) & "}"
  aux(j, 0)

proc mergeJson*(base, overlay: JsonNode): JsonNode =
  result = base
  if overlay.kind == JObject:
    if result.kind != JObject:
      result = overlay
    else:
      for key, val in overlay:
        if key in result and result[key].kind == JObject and val.kind == JObject:
          result[key] = mergeJson(result[key], val)
        else:
          result[key] = val

proc buildTaskLabel(taskName, description: string): string =
  result = taskName
  if description.len > 0:
    result &= " (" & description & ")"

proc nimbleTasksToVSCodeTasks(tasks: seq[NimbleTask]): JsonNode =
  result = newJObject()
  result["version"] = newJString("2.0.0")
  var taskArray = newJArray()
  for task in tasks:
    let label = buildTaskLabel(task.name, task.description)
    var shellCmd = ""
    for line in task.body:
      let stripped = line.strip()
      if stripped.len > 0:
        if shellCmd.len > 0: shellCmd &= " && "
        shellCmd &= stripped
    if shellCmd.len == 0:
      shellCmd = "echo No commands in task '" & task.name & "'"
    var taskObj = newJObject()
    taskObj["label"] = newJString(label)
    taskObj["type"] = newJString("shell")
    taskObj["command"] = newJString(shellCmd)
    taskObj["group"] = newJString("build")
    taskObj["presentation"] = %*{
      "reveal": "always",
      "panel": "shared"
    }
    taskArray.add(taskObj)
  result["tasks"] = taskArray

proc syncVSCodeExtensions(dir: string, force: bool = false) =
  let extPath = dir / "extensions.json"
  var existingExts: seq[string] = @[]
  if fileExists(extPath):
    try:
      let content = readFile(extPath)
      let parsed = parseJson(content)
      if parsed.hasKey("recommendations"):
        for ext in parsed["recommendations"]:
          existingExts.add(ext.getStr())
    except:
      discard

  var merged: seq[string] = @[]
  for ext in nimExtensions:
    if ext notin merged:
      merged.add(ext)
  for ext in existingExts:
    if ext notin merged:
      merged.add(ext)

  var recommendations = newJArray()
  for ext in merged:
    recommendations.add(newJString(ext))

  var extJson = newJObject()
  extJson["recommendations"] = recommendations
  writeFile(extPath, extJson.pretty())
  echo fmt"  Updated extensions.json ({merged.len} extensions)"

proc syncVSCodeSettings(dir: string) =
  let settingsPath = dir / "settings.json"
  let nimSettings = parseJson(nimSettingsJson)
  var baseSettings = nimSettings

  if fileExists(settingsPath):
    try:
      let content = readFile(settingsPath)
      let parsed = parseJson(content)
      baseSettings = mergeJson(parsed, nimSettings)
    except:
      baseSettings = mergeJson(baseSettings, nimSettings)

  writeFile(settingsPath, baseSettings.pretty())
  echo "  Updated settings.json"

proc syncVSCodeTasks(dir: string, tasks: seq[NimbleTask]) =
  let tasksPath = dir / "tasks.json"
  var tasksJson = nimbleTasksToVSCodeTasks(tasks)

  if fileExists(tasksPath):
    try:
      let content = readFile(tasksPath)
      let existing = parseJson(content)
      if existing.hasKey("tasks") and existing["tasks"].kind == JArray:
        var existingLabels: seq[string] = @[]
        for t in existing["tasks"]:
          if t.hasKey("label"):
            existingLabels.add(t["label"].getStr())
        var mergedTasks = newJArray()
        for t in tasksJson["tasks"]:
          let label = t["label"].getStr()
          if label notin existingLabels:
            mergedTasks.add(t)
        for t in existing["tasks"]:
          mergedTasks.add(t)
        tasksJson["tasks"] = mergedTasks
    except:
      discard

  writeFile(tasksPath, tasksJson.pretty())
  let taskCount = tasksJson["tasks"].len
  echo "  Updated tasks.json (" & $taskCount & " tasks)"

proc setupIDE*(nimblePath: string, ide: string) =
  if ide != "vscode":
    echo fmt"Error: unsupported IDE '{ide}'"
    echo "Supported: vscode"
    quit(1)

  let pkg = parseNimble(nimblePath)
  let projectRoot = getProjectRoot(nimblePath)
  let vscodeDir = projectRoot / ".vscode"

  echo "Setting up VS Code for ", pkg.name, "..."

  if not dirExists(vscodeDir):
    createDir(vscodeDir)
    echo "  Created .vscode/"

  syncVSCodeSettings(vscodeDir)
  syncVSCodeExtensions(vscodeDir)
  syncVSCodeTasks(vscodeDir, pkg.tasks)

  echo ""
  echo "Done! VS Code is configured."
  echo "  Open the project with: code ", projectRoot
