# Claude Code Best launcher — ps2exe compatible
# No #Requires, no <# #> blocks — both break ps2exe

param([Parameter(ValueFromRemainingArguments=$true)][string[]]$PassArgs)

$WindowTitle = 'Claude Code Best'

# Resolve directory of this EXE (ps2exe sets $PSScriptRoot to the EXE dir)
if ($PSScriptRoot -and $PSScriptRoot -ne '') {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}

$CoreExe = Join-Path $ScriptDir 'claude-core.exe'

# Validate
if (-not (Test-Path $CoreExe -PathType Leaf)) {
    $msg = "claude-core.exe not found at:`n$CoreExe`n`nPlease re-install Claude Code Best."
    [System.Windows.Forms.MessageBox]::Show(
        $msg, 'Claude Code Best',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}

# Parse args: consume --cwd <dir> for the starting directory; forward everything else.
$quotedArgs = @()
$CallerDir  = $PWD.Path
$i = 0
while ($i -lt $PassArgs.Count) {
    if ($PassArgs[$i] -eq '--cwd' -and ($i + 1) -lt $PassArgs.Count) {
        $CallerDir = $PassArgs[$i + 1]
        $i += 2
    } else {
        $a = $PassArgs[$i]
        if ($a -match '\s') { $quotedArgs += '"' + ($a -replace '"', '\"') + '"' }
        else                 { $quotedArgs += $a }
        $i++
    }
}

# ── Find wt.exe (Windows Terminal) ───────────────────────────────────────────
$WtExe = $null

# 1. PATH lookup
$WtGcm = Get-Command 'wt.exe' -ErrorAction SilentlyContinue
if ($WtGcm) { $WtExe = $WtGcm.Source }

# 2. App-execution alias (reparse point — must NOT use -PathType Leaf)
if (-not $WtExe) {
    $p = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
    if (Test-Path $p) { $WtExe = $p }
}

# 3. Packaged app under Program Files
if (-not $WtExe) {
    $p = Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.WindowsTerminal*\wt.exe" `
         -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
    if ($p) { $WtExe = $p.FullName }
}

# ── Launch ────────────────────────────────────────────────────────────────────
#
# Goal: run claude-core.exe DIRECTLY inside Windows Terminal (no PowerShell wrapper).
# wt.exe supports:  new-tab --startingDirectory <dir> -- <program> [args]
# The -- separator tells wt that everything after it is the program commandline.
# This gives claude-core.exe a proper WT pseudo-console: GPU rendering, ligatures,
# true-color, correct ANSI sequences — exactly what the Claude Code TUI needs.

if ($WtExe) {
    $safeTitle = $WindowTitle -replace '"', '\"'
    $safeDir   = $CallerDir   -replace '"', '\"'
    $safeExe   = $CoreExe     -replace '"', '\"'

    $wtArgs = "new-tab --title `"$safeTitle`" --startingDirectory `"$safeDir`" -- `"$safeExe`""
    if ($quotedArgs.Count -gt 0) { $wtArgs += ' ' + ($quotedArgs -join ' ') }

    Start-Process -FilePath $WtExe -ArgumentList $wtArgs
    exit 0
}

# Fallback: no Windows Terminal — open a plain conhost window running claude-core.exe directly
$fallbackArgs = if ($quotedArgs.Count -gt 0) { $quotedArgs -join ' ' } else { $null }
if ($fallbackArgs) {
    Start-Process -FilePath $CoreExe -WorkingDirectory $CallerDir -ArgumentList $fallbackArgs
} else {
    Start-Process -FilePath $CoreExe -WorkingDirectory $CallerDir
}
