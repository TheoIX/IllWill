# IllWill

**IllWill** is a lightweight **Death Wish tracker** for **Turtle WoW (Vanilla 1.12)** raids. It scans your raid/party for **Warriors** and displays a compact list with each warrior’s **Death Wish status** and a **usage counter**.

**Statuses**
- **READY** (green): Death Wish is considered available
- **ACTIVE** (yellow): Death Wish aura detected (shows remaining active time)
- **COOLDOWN** (red): cooldown timer running (shows remaining CD time)
- **?? / UNKNOWN** (gray): optional mode until IllWill has seen the first Death Wish from that warrior
- **OFFLINE** (gray): optional display for disconnected players

> IllWill infers cooldowns by detecting the **Death Wish aura** (buff/debuff) and starting a timer. It cannot read other players’ actual cooldowns directly on 1.12.

---

## Features

- Tracks **all Warriors** in your **raid** (or party/solo fallback)
- Detects Death Wish by **icon texture match** (checks both buffs and debuffs)
- Small UI frame with:
  - **Left:** total Death Wish uses (count)
  - **Middle:** warrior name
  - **Right:** READY / ACTIVE (with timer) / cooldown timer
- Throttled scanning (default ~0.2s) to stay lightweight in 40-man raids
- Saved settings via `IllWillDB`:
  - locked/unlocked position
  - scale
  - sort mode
  - offline visibility
  - “assume ready” vs “unknown until first seen”

---

## Installation

1. Download/clone this repository.
2. Create the folder:

World of Warcraft\Interface\AddOns\IllWill\

markdown
Copy code

3. Place these files inside:

IllWill.toc
IllWill.lua

markdown
Copy code

4. Restart Turtle WoW (or /reload if your client supports it).

---

## Usage

Type:

- `/iw` — show help
- `/iw show` / `/iw hide` / `/iw toggle`
- `/iw unlock` — unlock the frame (drag to move)
- `/iw lock` — lock the frame in place
- `/iw reset` — clears all counts + timers

### Sorting

- `/iw sort status` — groups by ACTIVE → COOLDOWN → READY → UNKNOWN → OFFLINE
- `/iw sort name` — alphabetical

### Scaling

- `/iw scale 1.2` — set scale (range clamped to 0.6–2.0)

### Unknown vs Assume-Ready Mode

- `/iw assume ready` — warriors you haven’t observed yet show **READY** (default)
- `/iw assume unknown` — warriors you haven’t observed yet show **??** until IllWill sees their first Death Wish

### Offline Display

- `/iw offline on` — show offline warriors (default)
- `/iw offline off` — hide offline warriors

---

## How It Works

IllWill maintains a small state per warrior:

- Detects Death Wish via `UnitBuff`/`UnitDebuff` icon texture substring match.
- When a warrior transitions **not active → active**, IllWill:
- increments their **use count**
- sets `activeUntil = now + 30`
- sets `cdUntil = now + 180`

**Default timings**
- Active: **30s**
- Cooldown: **180s**

If Turtle WoW changes Death Wish duration/cooldown on your realm/version, edit these constants near the top of `IllWill.lua`:

```lua
local DW_ACTIVE = 30
local DW_COOLDOWN = 180
Limitations (Important)
No true cooldown reading: Vanilla/Turtle API does not expose another player’s cooldown state. IllWill infers cooldown after it detects the aura.

Raid-start uncertainty: If you join mid-fight or mid-cooldown, IllWill won’t know prior cooldowns until it sees the first cast (use /iw assume ready if you prefer optimistic display).

Talent unknown: Warriors without Death Wish talent can’t be reliably detected until they never use it; they’ll just remain READY/UNKNOWN depending on mode.

Troubleshooting
Everyone shows READY / ACTIVE never triggers
IllWill detects Death Wish using icon texture substring matching. If Turtle uses a different icon path/name, update these constants near the top of IllWill.lua:

lua
Copy code
local DW_ICON_SUBSTR_1 = "spell_shadow_deathpact"
local DW_ICON_SUBSTR_2 = "deathpact"
local DW_ICON_SUBSTR_3 = "death_wish"
local DW_ICON_SUBSTR_4 = "deathwish"
Quick fix: replace/add substrings to match the actual icon texture string used by your client.

Frame won’t move
Run:

/iw unlock

UI is too big/small
Run:

/iw scale 0.9 (or any value 0.6–2.0)
<img width="277" height="301" alt="image" src="https://github.com/user-attachments/assets/0899bcb2-7148-49a4-b40f-255d21091628" />
<img width="283" height="303" alt="image" src="https://github.com/user-attachments/assets/fff5f496-ed3c-4c6c-a5e7-8f054d0dab37" />
<img width="279" height="304" alt="image" src="https://github.com/user-attachments/assets/179e0c86-84c2-4e04-b6d1-495c983b648d" />
<img width="371" height="545" alt="image" src="https://github.com/user-attachments/assets/56b1286f-b33d-4bed-a6ca-5ea3df4246c5" />


