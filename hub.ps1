# Dual-Mode Hub: switch the LG manually, edit the game list, control the watcher.
. (Join-Path $PSScriptRoot 'monitor_mode.ps1')

[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-Watcher {
  Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
    Where-Object CommandLine -match 'monitor_mode\.ps1.*-Watch'
}

function Start-Script([string[]]$scriptArgs) {
  Start-Process powershell.exe -WindowStyle Hidden -ArgumentList (
    @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', "`"$ScriptFile`"") + $scriptArgs)
}

function New-Control($type, $text, $x, $y, $w, $h) {
  $c = New-Object "System.Windows.Forms.$type"
  $c.Text = $text; $c.Location = "$x,$y"; $c.Size = "$w,$h"
  $c
}

$form = New-Control Form 'Dual-Mode Hub' 0 0 480 545
$form.FormBorderStyle = 'FixedSingle'; $form.MaximizeBox = $false; $form.StartPosition = 'CenterScreen'
# Same monitor icon as the Start menu shortcut (shell32.dll, index 15).
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Ico { [DllImport("shell32.dll", CharSet=CharSet.Unicode)] public static extern int ExtractIconEx(string f, int i, IntPtr[] large, IntPtr[] small, int n); }
'@
$icon = New-Object IntPtr[] 1
if ([Ico]::ExtractIconEx("$env:SystemRoot\System32\shell32.dll", 15, $icon, $null, 1) -gt 0) {
  $form.Icon = [System.Drawing.Icon]::FromHandle($icon[0])
}

# ---- Monitor -----------------------------------------------------------------
$lblMode = New-Control Label '' 16 14 440 26
$lblMode.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$btnOn  = New-Control Button '1080p 330 Hz' 16 46 140 32
$btnOff = New-Control Button '4K 165 Hz' 166 46 140 32
$btnOn.Add_Click({  Start-Script '-Mode', 'On';  $lblMode.Text = 'Switching...' })
$btnOff.Add_Click({ Start-Script '-Mode', 'Off'; $lblMode.Text = 'Switching...' })

# ---- Games -------------------------------------------------------------------
$grpGames = New-Control GroupBox 'Games (1080p 330 Hz while one of these runs)' 12 92 440 220
$lstGames = New-Control ListBox '' 10 22 420 150
$btnAddRun = New-Control Button 'Add running app...' 10 178 140 30
$btnAddExe = New-Control Button 'Add .exe...' 156 178 110 30
$btnRemove = New-Control Button 'Remove' 320 178 110 30
$grpGames.Controls.AddRange(@($lstGames, $btnAddRun, $btnAddExe, $btnRemove))

function Show-Games {
  $lstGames.Items.Clear()
  foreach ($g in Get-Games) { [void]$lstGames.Items.Add("$($g.name)   ($($g.processes -join ', '))") }
}

function Add-Game([string]$name, [string]$process) {
  $games = Get-Games
  if ($games | Where-Object { $_.processes -contains $process }) {
    [System.Windows.Forms.MessageBox]::Show("$process is already in the list.") | Out-Null; return
  }
  Save-Games (@($games) + [pscustomobject]@{ name = $name; processes = @($process) })
  Show-Games
}

$btnAddRun.Add_Click({
  # Only apps with a window, so the list is short. Uses window titles, not process
  # handles, so nothing touches an anti-cheat protected game.
  $apps = @(Get-Process | Where-Object { $_.MainWindowTitle -and $_.Id -ne $PID } |
    Sort-Object Name -Unique | Sort-Object MainWindowTitle)
  $dlg = New-Control Form 'Pick a running app' 0 0 420 400
  $dlg.StartPosition = 'CenterParent'; $dlg.FormBorderStyle = 'FixedDialog'; $dlg.MaximizeBox = $false
  $lst = New-Control ListBox '' 10 10 384 300
  foreach ($a in $apps) { [void]$lst.Items.Add("$($a.MainWindowTitle)   [$($a.Name)]") }
  $ok = New-Control Button 'Add' 294 318 100 30
  $ok.DialogResult = 'OK'; $dlg.AcceptButton = $ok
  $lst.Add_DoubleClick({ $dlg.DialogResult = 'OK' })
  $dlg.Controls.AddRange(@($lst, $ok))
  if ($dlg.ShowDialog($form) -eq 'OK' -and $lst.SelectedIndex -ge 0) {
    $a = $apps[$lst.SelectedIndex]
    Add-Game $a.MainWindowTitle $a.Name
  }
})

$btnAddExe.Add_Click({
  $ofd = New-Object System.Windows.Forms.OpenFileDialog
  $ofd.Filter = 'Programs (*.exe)|*.exe'; $ofd.Title = 'Pick the game .exe'
  if ($ofd.ShowDialog($form) -eq 'OK') {
    $name = [IO.Path]::GetFileNameWithoutExtension($ofd.FileName)
    Add-Game $name $name
  }
})

$btnRemove.Add_Click({
  $i = $lstGames.SelectedIndex
  if ($i -lt 0) { return }
  $games = Get-Games
  Save-Games ($games | Where-Object { $_ -ne $games[$i] })
  Show-Games
})

# ---- Watcher -----------------------------------------------------------------
$grpWatch = New-Control GroupBox 'Watcher' 12 322 440 96
$lblWatch = New-Control Label '' 10 26 200 22
$btnWatch = New-Control Button '' 220 20 100 30
$btnLog   = New-Control Button 'Open log' 330 20 100 30
$chkAuto  = New-Control CheckBox 'Start watcher with Windows' 10 58 300 24
$grpWatch.Controls.AddRange(@($lblWatch, $btnWatch, $btnLog, $chkAuto))

$btnWatch.Add_Click({
  $w = Get-Watcher
  if ($w) { $w | ForEach-Object { Stop-Process -Id $_.ProcessId -Force } } else { Start-Script '-Watch' }
  Start-Sleep -Milliseconds 800
  Update-Status
})
$btnLog.Add_Click({
  if (Test-Path $LogFile) { Start-Process notepad.exe $LogFile }
})
# Click (not CheckedChanged) so the timer setting Checked doesn't trigger it.
$chkAuto.Add_Click({
  if ($chkAuto.Checked) { Install-Autostart } else { Remove-Item $AutostartLink -ErrorAction SilentlyContinue }
})

# ---- LG Switch shortcut ------------------------------------------------------
$grpKey = New-Control GroupBox 'LG Switch Dual-Mode shortcut' 12 428 440 66
$txtKey = New-Control TextBox (Format-Hotkey (Get-Hotkey)) 10 26 150 24
$txtKey.ReadOnly = $true; $txtKey.BackColor = 'Window'; $txtKey.TextAlign = 'Center'; $txtKey.Cursor = 'Hand'
$lblKey = New-Control Label 'Click the box, then press the shortcut you set in LG Switch.' 170 22 260 34
$grpKey.Controls.AddRange(@($txtKey, $lblKey))

$Keys = [System.Windows.Forms.Keys]
# KeyCode -> SendKeys name for keys that aren't letters, digits or F-keys.
# PageUp/Prior and PageDown/Next are the same enum value, so both names are listed.
$specialKeys = @{ Home = '{HOME}'; End = '{END}'; Insert = '{INS}'; Delete = '{DEL}'
  PageUp = '{PGUP}'; Prior = '{PGUP}'; PageDown = '{PGDN}'; Next = '{PGDN}'
  Up = '{UP}'; Down = '{DOWN}'; Left = '{LEFT}'; Right = '{RIGHT}' }

$txtKey.Add_KeyDown({
  param($s, $e)
  $e.SuppressKeyPress = $true
  $k = $e.KeyCode
  if ($k -in $Keys::ControlKey, $Keys::ShiftKey, $Keys::Menu, $Keys::LWin, $Keys::RWin) { return }  # wait for the main key
  if (-not ($e.Control -or $e.Alt)) { $lblKey.Text = 'Use Ctrl and/or Alt (plus Shift if you like) with a key.'; return }
  $key = if ($k -ge $Keys::A -and $k -le $Keys::Z) { "$k".ToLower() }
         elseif ($k -ge $Keys::D0 -and $k -le $Keys::D9) { "$k".Substring(1) }
         elseif ("$k" -match '^F\d+$') { "{$k}" }
         else { $specialKeys["$k"] }
  if (-not $key) { $lblKey.Text = "The $k key isn't supported. Use a letter, digit or F-key."; return }
  $mods = $(if ($e.Control) { '^' }) + $(if ($e.Alt) { '%' }) + $(if ($e.Shift) { '+' })
  Set-Hotkey ($mods + $key)
  $txtKey.Text = Format-Hotkey ($mods + $key)
  $lblKey.Text = 'Saved. Make sure LG Switch uses the same shortcut.'
})

function Update-Status {
  $id = [Disp]::Find($MonitorPrefix)
  $lblMode.Text = if (-not $id) { 'LG monitor not found' }
                  elseif ($id -match $DualModeId) { 'Now: 1080p 330 Hz (Dual-Mode ON)' }
                  else { 'Now: 4K 165 Hz (Dual-Mode OFF)' }
  $running = [bool](Get-Watcher)
  $lblWatch.Text = if ($running) { 'Running' } else { 'Stopped' }
  $lblWatch.ForeColor = if ($running) { 'Green' } else { 'Firebrick' }
  $btnWatch.Text = if ($running) { 'Stop' } else { 'Start' }
  $chkAuto.Checked = Test-Path $AutostartLink
}

$form.Controls.AddRange(@($lblMode, $btnOn, $btnOff, $grpGames, $grpWatch, $grpKey))
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000
$timer.Add_Tick({ Update-Status })
$timer.Start()

Show-Games
Update-Status
[void]$form.ShowDialog()
