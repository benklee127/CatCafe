# DEPLOY (Local Run + Test Guide)

This project is local-first and currently targets Windows + Godot 4.x.

## 1. Prerequisites

- Windows 10/11
- Git
- Godot 4.6 (or 4.3+)
- PowerShell
- VS Code (optional, recommended)

## 2. Install Dependencies

### 2.1 Git
```powershell
winget install -e --id Git.Git
```

Verify:
```powershell
git --version
```

### 2.2 Godot
```powershell
winget install -e --id GodotEngine.GodotEngine
```

If `godot` command is not found after install, run this once:
```powershell
New-Item -ItemType Directory -Force -Path "$env:APPDATA\npm" | Out-Null

$exe = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -File -Filter "Godot*_win64.exe" |
  Sort-Object LastWriteTime -Descending |
  Select-Object -First 1 -ExpandProperty FullName

$shim = "$env:APPDATA\npm\godot.cmd"
Set-Content -Path $shim -Encoding Ascii -Value "@echo off`r`n`"$exe`" %*"

$env:Path += ";$env:APPDATA\npm"
godot --version
```

## 3. Clone / Open Project

```powershell
cd C:\workspace
# If not already cloned:
# git clone git@github.com:benklee127/CatCafe.git
cd C:\workspace\CatCafe
```

## 4. Run the Project

### 4.1 GUI Run
```powershell
godot --path C:\workspace\CatCafe
```

### 4.2 Headless Parse/Boot Check (fast sanity)
```powershell
godot --headless --path C:\workspace\CatCafe --quit
```

If `godot` is still not found, run with the full exe path:
```powershell
& "C:\Users\benkl\AppData\Local\Microsoft\WinGet\Packages\GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe\Godot_v4.6-stable_win64.exe" --path C:\workspace\CatCafe
```

## 5. VS Code + GDScript Language Server

Project settings are already configured in `.vscode/settings.json`:
- `godotTools.editorPath.godot4`
- `godotTools.lsp.serverPort = 6005`

If you still see:
`Couldn't connect to the GDScript language server at 127.0.0.1:6005`

Do this in order:
1. Open project in Godot editor first (`godot --editor --path C:\workspace\CatCafe`).
2. Keep Godot editor running.
3. In VS Code: `Ctrl+Shift+P` -> `Developer: Reload Window`.
4. Ensure Godot Tools extension is enabled for this workspace.
5. Confirm no firewall rule is blocking localhost port 6005.

## 6. Data Validation

Run validation script:
```powershell
godot --headless --path C:\workspace\CatCafe --script res://Tools/validate_data.gd
```

Expected result:
- `Data validation completed.`

## 7. Manual Test Pass (Current Milestones)

Run scene, then execute manual scripts:
- `Tests/M1_core_loop.md`
- `Tests/M2_data_and_generation.md`

Minimum pass checklist:
1. Cats wander on floor.
2. Overstimulation climbs during interactions.
3. At 100, cat retreats to rest area.
4. Save/load produces no parse errors.

## 8. Common Errors + Fixes

### `error: src refspec main does not match any`
No initial commit exists yet.
```powershell
git add .
git commit -m "Initial commit"
git push -u origin main
```

### `Expected '['` parsing `.tscn`
Usually caused by UTF-8 BOM in scene text.
- Re-save file as UTF-8 (no BOM).

### `Could not preload resource script ...`
- Check script syntax errors first with:
```powershell
godot --headless --path C:\workspace\CatCafe --quit
```
- Fix first script parse error shown in output, then rerun.

## 9. Recommended Daily Dev Loop

```powershell
cd C:\workspace\CatCafe
git checkout dev
git pull

godot --headless --path C:\workspace\CatCafe --script res://Tools/validate_data.gd
godot --path C:\workspace\CatCafe
```

After changes:
```powershell
git add .
git commit -m "m1: <what changed>"
git push
```

## 10. Current Entry Scene

Project boots from:
- `Scenes/MainLevel.tscn`

Configured at:
- `project.godot` -> `run/main_scene="res://Scenes/MainLevel.tscn"`
