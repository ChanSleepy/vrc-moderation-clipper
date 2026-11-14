$logDirectory         = Join-Path $env:USERPROFILE "AppData\LocalLow\VRChat\VRChat"

# Pressing the Clip Key Events. Setting Enabled = $false will disable an event.
# Only the line that begins with [ModerationManager] counts. Ignore the "Remove notification ..."
# lines which contain moderation message within a notification.
$triggers = @(
    @{ Name = "Player kicked"; Enabled = $true; Pattern = '\[ModerationManager\] .+ has been kicked' }
    @{ Name = "Player warned"; Enabled = $true; Pattern = '\[ModerationManager\] .+ has been warned' }
)
$clipDelaySeconds     = 0     # Wait for that amount of time before pressing the clip button (for the consequences).
$clipCooldownSeconds  = 2    # Do not consider any more events beyond this point from a clip
$pollIntervalSeconds  = 1     #How frequently should one inspect the log?

# Key for saving the clip. Must be the same key used in OBS as “Save Replay” hotkey.
# Available keys: F1-F24, A-Z, 0-9, Numpad0-Numpad9, Home, End, Insert, Delete,
#               PageUp, PageDown, Pause, ScrollLock, Space
# Modifiers: "Ctrl", "Alt", "Shift"  e.g. @("Ctrl","Shift")
$clipKey              = "PageDown"
$clipModifiers        = @()

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

$currentPolicy = Get-ExecutionPolicy -Scope LocalMachine
Write-Host "Current Execution Policy for LocalMachine is: $currentPolicy"

if ($currentPolicy -ne 'RemoteSigned')
{

    if (-not $isAdmin)
    {
        Write-Host "Run PowerShell as Administrator to set execution policy." -ForegroundColor Yellow
        Read-Host "Press Enter to exit..."
        exit
    }

    $choice = Read-Host "Execution policy 'RemoteSigned' is required. Set now? (Y/N)"

    if ($choice -notmatch '^[Yy]$')
    {
        Write-Host "Execution Policy was not changed. Exiting..." -ForegroundColor Yellow
        Read-Host "Press Enter to exit..."
        exit
    }

    Set-ExecutionPolicy RemoteSigned -Scope LocalMachine -Force | Out-Null
    Write-Host "Execution Policy set successfully." -ForegroundColor Green
}

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KeySender {
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@

function Get-VirtualKey
{
    param([string]$Name)

    $n = $Name.Trim()

    if ($n -match '^[Ff](\d{1,2})$')
    {
        $num = [int]$matches[1]
        if ($num -ge 1 -and $num -le 24)
        { return (0x70 + $num - 1)
        }
    }

    if ($n -match '^[A-Za-z]$')
    { return [int][char]$n.ToUpper()
    }
    if ($n -match '^[0-9]$')
    { return [int][char]$n
    }
    if ($n -match '^Numpad([0-9])$')
    { return (0x60 + [int]$matches[1])
    }

    $named = @{
        Home = 0x24; End = 0x23; Insert = 0x2D; Delete = 0x2E
        PageUp = 0x21; PageDown = 0x22; Pause = 0x13
        ScrollLock = 0x91; Space = 0x20
    }

    if ($named.ContainsKey($n))
    { return $named[$n]
    }

    return $null
}

$modifierMap = @{ Ctrl = 0x11; Alt = 0x12; Shift = 0x10 }

$clipVk = Get-VirtualKey $clipKey

if ($null -eq $clipVk)
{
    Write-Host "Unknown clip key '$clipKey'. Check the list in the settings." -ForegroundColor Red
    Read-Host "Press Enter to exit..."
    exit
}

$modifierVks = @()

foreach ($m in $clipModifiers)
{

    if (-not $modifierMap.ContainsKey($m))
    {
        Write-Host "Unknown modifier '$m'. Use Ctrl, Alt or Shift." -ForegroundColor Red
        Read-Host "Press Enter to exit..."
        exit
    }

    $modifierVks += $modifierMap[$m]
}

$clipLabel = (@($clipModifiers) + $clipKey) -join "+"

function Send-Hotkey
{

    # First remove the modifiers, and then
    foreach ($vk in $modifierVks)
    {
        [KeySender]::keybd_event([byte]$vk, 0, 0, [UIntPtr]::Zero)
    }

    [KeySender]::keybd_event([byte]$clipVk, 0, 0, [UIntPtr]::Zero)   # key down
    Start-Sleep -Milliseconds 50
    [KeySender]::keybd_event([byte]$clipVk, 0, 2, [UIntPtr]::Zero)   # key up

    # Modifiers down (reverse order)
    for ($i = $modifierVks.Count - 1; $i -ge 0; $i--)
    {
        [KeySender]::keybd_event([byte]$modifierVks[$i], 0, 2, [UIntPtr]::Zero)
    }
}

Write-Host ""
Write-Host "VRChat Moderation Clipper" -ForegroundColor Yellow
Write-Host "---------------------------------------------------" -ForegroundColor DarkGray
Write-Host "Log directory : $logDirectory" -ForegroundColor Cyan
Write-Host "Clip key      : $clipLabel" -ForegroundColor Cyan
Write-Host "Clip delay    : $clipDelaySeconds s | Cooldown: $clipCooldownSeconds s" -ForegroundColor Cyan
Write-Host "---------------------------------------------------" -ForegroundColor DarkGray
Write-Host "Kicking and warning on the lookout. Ensure that the OBS Replay Buffer is enabled." -ForegroundColor Green
Write-Host ""

$currentLog = $null
$position   = 0L
$partial    = ""
$lastClip   = [datetime]::MinValue

while ($true)
{

    $latest = Get-ChildItem -Path $logDirectory -Filter "output_log_*.txt" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latest)
    {

        Write-Host "VRChat log file not found. Is VRChat running?" -ForegroundColor Red
    } else
    {

        if ($latest.FullName -ne $currentLog)
        {

            # First time: start at the end of the file (ignore history).
            # New log after a VRChat restart: read it from the start.
            $position   = if ($null -eq $currentLog)
            { $latest.Length
            } else
            { 0L
            }
            $currentLog = $latest.FullName
            $partial    = ""

            Write-Host "Watching: $($latest.Name)" -ForegroundColor DarkGray
        }

        $newLines = @()
        $stream   = $null

        try
        {
            $stream = [System.IO.File]::Open($currentLog, 'Open', 'Read', 'ReadWrite')

            if ($stream.Length -lt $position)
            {
                $position = 0L
                $partial  = ""
            }

            if ($stream.Length -gt $position)
            {

                $stream.Seek($position, 'Begin') | Out-Null

                $reader   = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                $text     = $partial + $reader.ReadToEnd()
                $position = $stream.Position

                $parts   = $text -split "`n"
                $partial = $parts[-1]

                if ($parts.Count -gt 1)
                {
                    $newLines = $parts[0..($parts.Count - 2)]
                }
            }
        } catch
        {
            Write-Host "WARN: Could not read log: $($_.Exception.Message)" -ForegroundColor Red
        } finally
        {
            if ($stream)
            { $stream.Dispose()
            }
        }

        $hit     = $null
        $hitName = ""

        foreach ($line in $newLines)
        {
            foreach ($t in $triggers)
            {
                if ($t.Enabled -and $line -match $t.Pattern)
                {
                    $hit     = $line
                    $hitName = $t.Name
                    break
                }
            }
        }

        if ($hit)
        {

            $sinceLast = ((Get-Date) - $lastClip).TotalSeconds

            if ($sinceLast -ge $clipCooldownSeconds)
            {

                Write-Host "DETECTED: $hitName" -ForegroundColor Magenta
                Write-Host $hit.Trim() -ForegroundColor DarkGray

                if ($clipDelaySeconds -gt 0)
                {
                    Start-Sleep -Seconds $clipDelaySeconds
                }

                Send-Hotkey
                $lastClip = Get-Date

                Write-Host "$clipLabel sent." -ForegroundColor Green
            } else
            {
                Write-Host "$hitName ignored (cooldown)." -ForegroundColor DarkYellow
            }
        }
    }

    Start-Sleep -Seconds $pollIntervalSeconds
}
