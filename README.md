# ⛓️ Chained Teams

**Race your friends up the tower in Chained Together.**
Two teams of 3, two chains, one lobby, plus live split times so you can see who's really winning.

> 🔒 Made for private lobbies with friends. No leaderboards, no public matchmaking.

---

## 🚀 Get playing in 3 steps

**1. Download**
Go to [**Releases**](../../releases/latest) and download **`ChainedTeams-vX.zip`**.

**2. Unzip**
Right-click the zip → **Extract All** → put the folder anywhere (your Desktop is fine).

**3. Play**
Open the folder and double-click **`ChainedTeams.exe`**. The game starts with the mod on.
Then join your friend's lobby like you normally would.

That's it! 🎉

<details>
<summary>😬 Windows says "Windows protected your PC"</summary>

That's normal for small homemade tools. Click **More info** → **Run anyway**.
If your antivirus complains, allow `ChainedTeams.exe`. All it does is switch the mod on while the game is running.
</details>

<details>
<summary>🎮 I want to play the normal game</summary>

Just launch Chained Together from Steam like you always do. The mod only runs when you start it with `ChainedTeams.exe`. Nothing in your game folder is changed.
</details>

---

## ✨ What you get

- 🏁 **3v3 races.** Team Red vs Team Blue in one lobby.
- ⛓️ **Your own chain.** Each team is chained only to its own players, and you pass right through the other team.
- ⏱️ **Live splits.** Every section of the map (The underworld → … → The Final Trials) gets a time for each team, shown in the chat box on the left.
- 🏆 **First to the top wins.** Everyone sees both teams' times at the end.
- 🔁 **Instant rematch.** Back to the lobby without anyone rejoining.
- 🧗 **Practice mode.** Save your spot, mark tricky jumps, and teleport back to them. Works with 1 to 3 players.
- 🛡️ **Update-safe.** If the game updates and the mod isn't ready yet, it switches itself off instead of breaking your game.

---

## 💬 Chat commands

Press **T** to open chat and type a command.

**🏁 During a race**
| Command | What it does |
|---|---|
| `!help` | Shows all commands |
| `!time` | Current race time |
| `!splits` | Both teams' times so far |
| `!team red` / `!team blue` | Switch teams |
| `!spectate` | Watch the other team (`!me` to come back) |

**🧗 Practice** (only when a race isn't running)
| Command | What it does |
|---|---|
| `!save` / `!load` | Save your team's spot and jump back to it |
| `!mark jump1` | Remember this spot as "jump1" |
| `!tp jump1` | Teleport your team to "jump1" |
| `!skips` | List your saved spots |
| `!top` | Teleport to the top |

**👑 Host only**
| Command | What it does |
|---|---|
| `!balance` | Splits everyone into even teams |
| `!rematch` | Back to the lobby for another round |
| `!start` / `!reset` | Start or reset the clock by hand |

---

## 👑 Hosting a race

See the **[Host guide](docs/HOST_GUIDE.md)**. It's short, promise.

---

## 📋 Status (v0.4)

- ✅ **Working:** splits, practice mode, the launcher, and a full 6-player race (teams, chains, timer, winner, rematch).
- 🔜 **Still to try with real friends online:** players 5 and 6 joining through Steam, and spectating.

Found a bug? [Open an issue](../../issues) and say what happened.

---

<details>
<summary>🛠️ For tinkerers: building it yourself</summary>

```powershell
.\tools\build-release.ps1
```
This downloads UE4SS, builds the launcher and creates `release\ChainedTeams-v<version>.zip`.

| Folder | What's inside |
|---|---|
| `mod/` | The mod itself |
| `launcher/` | Source for `ChainedTeams.exe` |
| `docs/` | Player and host guides (`docs/dev/` has the technical notes) |
| `tools/` | The build script |

Uses [RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (MIT). Contains no game files.
</details>
