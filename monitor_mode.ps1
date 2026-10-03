<#
  Switches the LG 32GX850A between Dual-Mode ON (1080p 330 Hz) and OFF (4K 165 Hz).

  The monitor does not expose Dual-Mode over DDC/CI, so the switch is done by pressing
  the LG Switch app's Dual-Mode keyboard shortcut. The current state is read from the
  monitor's hardware id, which changes with the mode.

  Usage:
    .\monitor_mode.ps1 -Mode On        # 1080p 330 Hz
    .\monitor_mode.ps1 -Mode Off       # 4K 165 Hz
    .\monitor_mode.ps1 -Mode Toggle
    .\monitor_mode.ps1 -Watch          # ON while Valorant runs, OFF when it closes
    .\monitor_mode.ps1 -InstallAutostart   # run -Watch hidden at every login
#>
param(
  [ValidateSet('On', 'Off', 'Toggle')] [string]$Mode,
  [switch]$Watch,
  [switch]$InstallAutostart
)

# ---- Settings ---------------------------------------------------------------
# The Dual-Mode shortcut you set in LG Switch, in SendKeys notation:
#   ^ = Ctrl   % = Alt   + = Shift      e.g. '^%d' = Ctrl+Alt+D,  '^%{F10}' = Ctrl+Alt+F10
$Hotkey       = '%+d'                                       # Alt+Shift+D
# The LG reports a different hardware id per mode: GSM7856 = 4K, GSM7859 = Dual-Mode.
$MonitorPrefix = 'GSM785'
$DualModeId    = 'GSM7859'
$GameProcess  = 'VALORANT-Win64-Shipping', 'VALORANT'      # game + its launcher stub
$PollSeconds  = 3
# -----------------------------------------------------------------------------

Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class Disp {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
  public struct DISPLAY_DEVICE { public int cb;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string Name;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string String;
    public int Flags;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string ID;
    [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string Key; }
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool EnumDisplayDevices(string dev, int i, ref DISPLAY_DEVICE dd, int flags);

  // Returns the monitor id (e.g. MONITOR\GSM7856\{...}) of the first active display whose id contains `id`.
  public static string Find(string id) {
    var a = new DISPLAY_DEVICE(); a.cb = Marshal.SizeOf(a);
    for (int i = 0; EnumDisplayDevices(null, i, ref a, 0); i++) {
      var m = new DISPLAY_DEVICE(); m.cb = Marshal.SizeOf(m);
      if (EnumDisplayDevices(a.Name, 0, ref m, 0) && m.ID.Contains(id)) return m.ID;
    }
    return null;
  }
}
public static class Fg {
  [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out int pid);
  public static int Pid() { int pid; GetWindowThreadProcessId(GetForegroundWindow(), out pid); return pid; }
}
'@

function Test-DualMode([switch]$AllowMissing) {
  $id = [Disp]::Find($MonitorPrefix)
  if (-not $id) {
    # The monitor drops out briefly while it re-syncs after a mode change.
    if ($AllowMissing) { return $null }
    throw "LG monitor ($MonitorPrefix*) not found among active displays."
  }
  $id -match $DualModeId
}

# Prints and appends to monitor_mode.log, since the watcher runs without a window.
function Log([string]$msg) {
  Write-Host $msg
  "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Add-Content -Encoding utf8 (Join-Path $PSScriptRoot 'monitor_mode.log')
}

function Set-DualMode([bool]$On) {
  $label = if ($On) { 'ON (1080p 330 Hz)' } else { 'OFF (4K 165 Hz)' }
  if ((Test-DualMode) -eq $On) { Log "Dual-Mode already $label"; return }
  # A key press sent while the game is starting can get lost, so retry a few times.
  for ($try = 1; $try -le 3; $try++) {
    $fg = (Get-Process -Id ([Fg]::Pid()) -ErrorAction SilentlyContinue).Name
    Log "Sending $Hotkey for $label (try $try, foreground: $fg)"
    [System.Windows.Forms.SendKeys]::SendWait($Hotkey)
    # The monitor re-syncs and reconnects with its new hardware id; wait for that to happen.
    # A switch can take ~10 s; wait well past that so a retry never toggles it back.
    for ($i = 0; $i -lt 40; $i++) {
      Start-Sleep -Milliseconds 500
      if ((Test-DualMode -AllowMissing) -eq $On) { Log "Dual-Mode $label"; return }
    }
  }
  Log "WARNING: Dual-Mode did not switch. Is LG Switch running, and is its Dual-Mode shortcut set to $Hotkey?"
}

if ($InstallAutostart) {
  $lnk = Join-Path ([Environment]::GetFolderPath('Startup')) 'Valorant Dual-Mode.lnk'
  $s = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
  $s.TargetPath = 'powershell.exe'
  $s.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`" -Watch"
  $s.WindowStyle = 7
  $s.Save()
  Write-Host "Autostart installed: $lnk"
  return
}

if ($Mode) {
  switch ($Mode) {
    'On'     { Set-DualMode $true }
    'Off'    { Set-DualMode $false }
    'Toggle' { Set-DualMode (-not (Test-DualMode)) }
  }
  return
}

if ($Watch) {
  Write-Host "Watching for Valorant (Ctrl+C to stop)..."
  $wasRunning = $false
  while ($true) {
    $running = [bool](Get-Process -Name $GameProcess -ErrorAction SilentlyContinue)
    # Only act on start/stop, so a manual switch mid-session is left alone.
    if ($running -ne $wasRunning) {
      Log "Valorant $(if ($running) { 'started' } else { 'closed' })"
      try { Set-DualMode $running } catch { Log "ERROR: $_" }
      $wasRunning = $running
    }
    Start-Sleep -Seconds $PollSeconds
  }
}

Get-Help $PSCommandPath
