$logDirectory         = Join-Path $env:USERPROFILE "AppData\LocalLow\VRChat\VRChat"

# Counts lines from [ModerationManager], plus "Remove notification from AllTime notifications" lines.
# Does not count "Remove notification from Local notifications" lines.
$triggerPattern       = '(\[ModerationManager\].*(A vote kick has been initiated against|A vote to kick .+ has been requested))|(Remove notification from AllTime notifications:.*A vote kick has been initiated against)'
$clipDelaySeconds     = 0     # Press the clip key after waiting this long (to capture the consequences)
$clipCooldownSeconds  = 2    # Don’t consider more voting kicks from now on after this video
$pollIntervalSeconds  = 1     # The frequency of the log inspection

#Key to press for saving the clip. Should correspond to your OBS “Save Replay” shortcut.
#Keys allowed: F1-F24, A-Z, 0-9, Numpad0-Numpad9, Home, End, Insert, Delete,
#             PageUp, PageDown, Pause, ScrollLock, Space
#Modifiers (optional): “Ctrl”, “Alt”, “Shift”    Example: @("Ctrl","Shift")
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

if (-not ('KeySender' -as [type]))
{
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KeySender {
    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);
}
"@
}

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

    # Modifiers reduced, and then comes the
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
Write-Host "VRChat Vote Kick Clipper" -ForegroundColor Yellow
Write-Host "---------------------------------------------------" -ForegroundColor DarkGray
Write-Host "Log directory : $logDirectory" -ForegroundColor Cyan
Write-Host "Clip key      : $clipLabel" -ForegroundColor Cyan
Write-Host "Clip delay    : $clipDelaySeconds s | Cooldown: $clipCooldownSeconds s" -ForegroundColor Cyan
Write-Host "---------------------------------------------------" -ForegroundColor DarkGray
Write-Host "Watching for vote kicks. Make sure the OBS Replay Buffer is running." -ForegroundColor Green
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

        $hit = $newLines | Where-Object { $_ -match $triggerPattern } | Select-Object -Last 1

        if ($hit)
        {

            $sinceLast = ((Get-Date) - $lastClip).TotalSeconds

            if ($sinceLast -ge $clipCooldownSeconds)
            {

                Write-Host "VOTE KICK DETECTED" -ForegroundColor Magenta
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
                Write-Host "Vote kick ignored (cooldown)." -ForegroundColor DarkYellow
            }
        }
    }

    Start-Sleep -Seconds $pollIntervalSeconds
}
