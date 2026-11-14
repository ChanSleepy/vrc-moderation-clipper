# VRChat Moderation Clipper

Automatically saves an OBS replay clip when VRChat logs a kick, warning, ban, or vote kick.

The scripts read VRChat's log file and press your OBS "Save Replay" hotkey when a moderation event appears. Nothing is injected into VRChat and no client mods are needed.

> Unofficial. Not affiliated with or endorsed by VRChat Inc.

## What's included

| File | Purpose |
|---|---|
| `Start Moderation.bat` | Launches `VRChat_Moderation_Clipper.ps1` (kicks, warnings, bans, and optionally blocks and mutes) |
| `Start votkick Detected.bat` | Launches `VRChat_VoteKick_Clipper.ps1` (vote kicks) |
| `VRChat_Moderation_Clipper.ps1` | Watches the log for moderation events |
| `VRChat_VoteKick_Clipper.ps1` | Watches the log for vote kick events |

You can run either script on its own, or both at the same time.

## Requirements

- Windows with PowerShell 5.1 or newer
- OBS Studio with the **Replay Buffer** enabled and started
- VRChat running on the same PC

## Setup

1. In OBS, go to **Settings → Output → Replay Buffer** and enable it. Set the buffer length (for example 30 to 60 seconds).
2. In OBS, go to **Settings → Hotkeys** and set **Save Replay** to a key, for example `PageDown`.
3. Make sure that key matches `$clipKey` (and `$clipModifiers`) in the script.
4. Click **Start Replay Buffer** in OBS.
5. Launch VRChat, then double-click the `.bat` file for the script you want.

## Events detected

### Moderation script

Each event has an `Enabled` flag at the top of `VRChat_Moderation_Clipper.ps1`. Set it to `$false` to ignore that event.

| Event | Source in log | Enabled by default |
|---|---|---|
| Player kicked | `[ModerationManager]` message | Yes |
| Player warned | `[ModerationManager]` message | Yes |
| Player blocked | `[ModerationManager]` request | No |
| Player muted | `[ModerationManager]` message | No |
| Moderation: warn | `[API]` moderation request | Yes |
| Moderation: kick | `[API]` moderation request | Yes |
| Moderation: ban | `[API]` moderation request | Yes |
| Moderation: block | `[API]` player moderation request | No |
| Moderation: mute | `[API]` player moderation request | No |

The `[ModerationManager]` entries catch what happens in the instance. The `[API]` entries catch the moderation request VRChat sends to its servers. A single kick can produce both, so the cooldown (see below) makes sure you only get one clip.

Only lines that begin with `[ModerationManager]` or `[API]` count. "Remove notification" lines that merely repeat a moderation message are ignored.

Example:

```powershell
$triggers = @(
    @{ Name = "Player kicked";  Enabled = $true;  Pattern = '\[ModerationManager\] .+ has been kicked' }
    @{ Name = "Player muted";   Enabled = $true;  Pattern = '\[ModerationManager\] .+ is now Muted' }
    # ...
)
```

When the script starts, it prints the list of active events so you can confirm what it's watching.

### Vote kick script

`VRChat_VoteKick_Clipper.ps1` triggers on a single pattern that matches:

- `[ModerationManager]` lines saying a vote kick was initiated against someone or a vote to kick was requested
- "Remove notification from AllTime notifications" lines containing the vote kick message

"Remove notification from Local notifications" lines are ignored. The pattern is in `$triggerPattern` if you need to adjust it.

## Configuration

Settings are at the top of each `.ps1` file. Open it in any text editor.

| Setting | Default | What it does |
|---|---|---|
| `$clipDelaySeconds` | `0` | Seconds to wait after detecting an event before pressing the clip key. `0` saves immediately, so the clip shows what led up to the event. Raise it to also capture what happens afterwards. |
| `$clipCooldownSeconds` | `5` (moderation), `2` (vote kick) | After a clip is saved, further events within this many seconds are ignored. This prevents duplicate clips from retries and double log lines. |
| `$pollIntervalSeconds` | `1` | How often the log file is checked for new lines. 1 second is fine for most setups. |
| `$clipKey` | `"PageDown"` | The key pressed to save the replay. Must match your OBS "Save Replay" hotkey. |
| `$clipModifiers` | `@()` | Optional modifier keys held while pressing the clip key. |

### Allowed keys

`F1`-`F24`, `A`-`Z`, `0`-`9`, `Numpad0`-`Numpad9`, `Home`, `End`, `Insert`, `Delete`, `PageUp`, `PageDown`, `Pause`, `ScrollLock`, `Space`

### Modifiers

`Ctrl`, `Alt`, `Shift`

```powershell
$clipKey       = "F13"
$clipModifiers = @("Ctrl", "Shift")   # sends Ctrl+Shift+F13
```

If the key name or a modifier is not recognized, the script prints an error and exits.

### Choosing a good hotkey

The key is sent globally, to whatever window has focus. `PageDown` will also scroll pages in other apps, so a rarely used key such as `F13`-`F24`, or a combination like `Ctrl+Shift+F9`, is safer.

### Capturing the aftermath

The replay buffer saves the last N seconds before the key press. To capture the consequences of an event:

- Set `$clipDelaySeconds` to a few seconds, for example `5`.
- Make sure your OBS replay buffer length is longer than the delay plus the amount of lead-up you want.

## How it works

1. Finds the newest `output_log_*.txt` in `%USERPROFILE%\AppData\LocalLow\VRChat\VRChat`.
2. Starts reading from the end of the file, so old events are ignored. If VRChat restarts and creates a new log, it reads that one from the start.
3. Matches new lines against the enabled trigger patterns.
4. If the cooldown has passed, waits `$clipDelaySeconds` and sends the hotkey.

## Troubleshooting

- **"VRChat log file not found"**: VRChat isn't running, or hasn't created a log yet.
- **Nothing gets saved**: Check that the OBS Replay Buffer is started (not just enabled) and the OBS hotkey matches `$clipKey` exactly.
- **A moderation event wasn't clipped**: Check that its `Enabled` flag is `$true`, and look at the "Active events" line printed at startup. Block and mute events are off by default.
- **Too many clips, or clips cut off by the cooldown**: Adjust `$clipCooldownSeconds`. A higher value merges nearby events into one clip; a lower value lets closely spaced events each save a clip.
- **Execution policy prompt**: The script checks that the machine execution policy is `RemoteSigned`. If it isn't, run PowerShell as Administrator once and answer `Y` when asked, or set it yourself with `Set-ExecutionPolicy RemoteSigned -Scope LocalMachine`.
- **Hotkey doesn't work in OBS**: If OBS runs as Administrator but the script doesn't, Windows may block the keypress. Run both at the same privilege level.

## Notes

- Only reads VRChat's log files. It does not modify the game.
- Clips are saved by OBS to its normal recording folder.
- Log message formats can change when VRChat updates. If a trigger stops working, check a recent log file and update the matching pattern.

## Acknowledgements

The `.bat` launcher files are adapted from
[VRC_World_Location](https://github.com/Elocin-Anagram/VRC_World_Location)
by Elocin-Anagram. Thanks for the original work.
