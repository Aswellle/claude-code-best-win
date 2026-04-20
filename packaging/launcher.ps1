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

# Build forwarded arg string (no --cwd; CWD is set via Set-Location in the payload).
# If the caller passed --cwd <dir> (Explorer context-menu), extract it as the target dir;
# otherwise use $PWD.Path so a terminal launch preserves the calling directory.
$quotedArgs = @()
$CallerDir  = $PWD.Path
$i = 0
while ($i -lt $PassArgs.Count) {
    if ($PassArgs[$i] -eq '--cwd' -and ($i + 1) -lt $PassArgs.Count) {
        $CallerDir = $PassArgs[$i + 1]
        $i += 2
    } else {
        $a = $PassArgs[$i]
        if ($a -match '\s') { $quotedArgs += '"' + ($a -replace '"','\"') + '"' }
        else                 { $quotedArgs += $a }
        $i++
    }
}
$ArgString = $quotedArgs -join ' '

# ── Find wt.exe ───────────────────────────────────────────────────────────────
$WtExe = $null

$WtGcm = Get-Command 'wt.exe' -ErrorAction SilentlyContinue
if ($WtGcm) { $WtExe = $WtGcm.Source }

if (-not $WtExe) {
    $p = "$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe"
    if (Test-Path $p -PathType Leaf) { $WtExe = $p }
}

if (-not $WtExe) {
    $p = Get-Item "$env:ProgramFiles\WindowsApps\Microsoft.WindowsTerminal*\wt.exe" `
         -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($p) { $WtExe = $p.FullName }
}

# ── Build PowerShell -EncodedCommand payload ──────────────────────────────────
#
# Using cmd /k "path with spaces\exe" is fundamentally broken:
#   - wt.exe (CRT parser) strips quotes when building argv → path splits at spaces
#   - cmd.exe /k strips outer quotes → inner path loses quotes → also splits
#
# Solution: encode the command as Unicode base64 and pass via -EncodedCommand.
# Base64 contains no spaces or special chars, so all argument parsers pass it
# through intact. PowerShell then decodes and runs the command natively, with
# full support for paths containing spaces via the & '...' call operator.

$EscapedExe  = $CoreExe  -replace "'", "''"
$EscapedDir  = $CallerDir -replace "'", "''"
$PsCommand   = "Set-Location '$EscapedDir'; & '$EscapedExe'"
if ($ArgString -ne '') { $PsCommand += " $ArgString" }

$PsCmdBytes   = [System.Text.Encoding]::Unicode.GetBytes($PsCommand)
$PsCmdEncoded = [System.Convert]::ToBase64String($PsCmdBytes)

# ── Launch ────────────────────────────────────────────────────────────────────
$PsExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

if ($WtExe) {
    Start-Process -FilePath $WtExe `
        -ArgumentList "--title `"$WindowTitle`" powershell -NoLogo -NoExit -EncodedCommand $PsCmdEncoded"
    exit 0
}

# Fallback: plain PowerShell window (no wt.exe)
if (Test-Path $PsExe -PathType Leaf) {
    Start-Process -FilePath $PsExe -ArgumentList "-NoLogo -NoExit -EncodedCommand $PsCmdEncoded"
} else {
    Start-Process -FilePath $CoreExe -ArgumentList ($quotedArgs -join ' ')
}
