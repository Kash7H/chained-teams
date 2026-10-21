# Chained Teams

A mod for Chained Together: two teams of 3 race up the tower in one lobby, with live split times for each team.

Made for private lobbies with friends. No leaderboards, no public matchmaking.

## Install

1. Download `ChainedTeams-vX.zip` from [Releases](../../releases/latest).
2. Unzip it anywhere.
3. Double-click `ChainedTeams.exe`. The game starts with the mod on. Join your friend's lobby as usual.

To play without the mod, launch Chained Together from Steam as normal. Nothing in your game folder is changed.

If Windows shows "Windows protected your PC", click **More info**, then **Run anyway**.

## Features

- **3v3 races:** Team Red vs Team Blue in one lobby, up to 6 players.
- **Separate chains:** each team is chained only to its own players, and the teams pass through each other.
- **Live splits:** a time for each team at every section of the map, shown in the chat box.
- **First to the top wins:** both teams' split times are shown at the end.
- **Rematch:** return to the lobby without anyone rejoining.
- **Practice mode:** save positions and teleport back to them, with 1 to 3 players.
- **Update-safe:** if the game updates, the mod turns itself off instead of breaking the game.

## Chat commands

Press **T** to open chat.

**Race**

| Command | Description |
|---|---|
| `!help` | List all commands |
| `!time` | Current race time |
| `!splits` | Both teams' split times |
| `!team red` / `!team blue` | Switch team |
| `!spectate` / `!me` | Watch the other team / return to your own view |

**Practice** (not available during a race)

| Command | Description |
|---|---|
| `!save` / `!load` | Save your team's position / return to it |
| `!mark <name>` | Save the current position under a name |
| `!tp <name>` | Teleport your team to a saved position |
| `!skips` | List saved positions |
| `!top` | Teleport to the top |

**Host only**

| Command | Description |
|---|---|
| `!balance` | Split players into even teams |
| `!rematch` | Return everyone to the lobby |
| `!start` / `!reset` | Start or reset the clock manually |

## Hosting

See the [Host guide](docs/HOST_GUIDE.md).

## Status (v0.4)

- **Working:** splits, practice mode, the launcher, and a full 6-player race (teams, chains, timer, winner, rematch).
- **Not yet tested with real players online:** players 5 and 6 joining through Steam, and spectating.

Report bugs in [Issues](../../issues).

## Building from source

```powershell
.\tools\build-release.ps1
```

This downloads UE4SS, builds the launcher and writes `release\ChainedTeams-v<version>.zip`.

| Folder | Contents |
|---|---|
| `mod/` | The mod |
| `launcher/` | Source for `ChainedTeams.exe` |
| `docs/` | Player and host guides; `docs/dev/` has technical notes |
| `tools/` | Build script |

Uses [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (MIT). Contains no game files.
