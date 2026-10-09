# DECWAR command reference

Condensed from DECWAR's in-game help (`docs/DECWAR.HLP`, DECWAR 2.3).
The live game's `HELP <command>` is authoritative for the host's
version; use this for a fast, offline lookup.

## Input basics

- Only the first 5 characters of each input word are stored.
- Words are separated by spaces, tabs, or commas.
- A line ends with `<CR>`, `<LF>`, `<VT>`, `<FF>`, `<ESC>`, or `^Z`.
- `^G` toggles echo on/off; `^U` (and the end of a line) restores it.
- Several commands may go on one line, separated by `/`. A `TELL` must
  be last on the line.
- Anything after `;` is a comment — except that `TELL` rescans the line
  and takes the text after the first `;` as its message.
- `<ESC>` as the first character repeats the previous command (not a
  `TELL`). Handy for docking, repairing, building, firing torpedoes.
- Any ship name may be abbreviated to 1 character; any command or
  keyword to its shortest unambiguous abbreviation (never more than 2).

## Coordinates

A command needing a location takes `<vpos> <hpos>` (vertical then
horizontal). Three forms; a form keyword is given once and applies to
the whole set of coordinates on the line:

- **Absolute** (default) — `M 37 45`; optional keyword `ABSOLUTE`.
- **Relative** — `M R 4 -5` (up 4, left 5); positive = up/right,
  negative = down/left. The `R` is unnecessary if input defaults to
  relative (`SET ICDEF RELATIVE`), e.g. from `DECWAR.INI`.
- **Computed** — `PH C BUZZARD` targets the named ship's location; only
  for slow terminals (< 1200 baud) and needs an operational computer.

Coordinate *output* style is set with `SET OCDEF ABSOLUTE|RELATIVE|BOTH`
(`BOTH` adds range and direction to hit messages and listings).

## Commands

Alphabetical. Bracketed parts are optional; the caps show the shortest
unambiguous abbreviation.

- **`BA [<keywords>]`** — list friendly bases (location, shield %) or,
  with keywords, enemy bases, summary, closest (`BA CL`), or a specific
  sector. Default range is the whole galaxy, default side friendly.
- **`BU <vpos> <hpos>`** — build fortifications on a captured planet.
  A planet takes up to 4 builds; the 5th becomes a new starbase if a
  team starbase has been destroyed. Max 10 starbases at once.
- **`CA <vpos> <hpos>`** — capture a neutral or enemy planet. Costs 5 s
  + 1 s per enemy build, and 50 ship energy per build.
- **`DA [<device names>]`** — list damaged devices and their units.
  Device keywords include `SHields TOrpedoes PHasers RA `(radio)`C`(computer).
  Total ship damage is not reported here (use `ST`).
- **`DO [Status [<device names>]]`** — dock at an adjacent friendly base
  or planet: refuel, repair, re-arm, set condition green. `DO ST` also
  shows status after docking. No effect if already full.
- **`E <ship> <units>`** — transfer ship energy to an adjacent friendly
  ship; 10% is lost to dissipation.
- **`GRIPE`** — record a comment/bug in `GAM:DECWAR.GRP`; `^Z` sends,
  `^C` aborts. Protects you from attack unless on red alert.
- **`H [*|<keywords>]`** — general help, command list (`H *`), or help
  for a command/keyword (`H MOVE`, `H SCAN`). Protects you unless on
  red alert.
- **`I <vpos> <hpos>`** — impulse move, one sector (warp 1). Sets
  condition green.
- **`LI [<keywords>]`** — the general listing command (ships, bases,
  planets); covers infinite range, all sides, all objects by default.
  Keywords: ship names, `vpos hpos`, `CLosest`, `SHips`, `BAses`,
  `PLanets`, `POrts`, `FEderation`/`HUman`, `EMpire`/`Klingon`,
  `FRiendly`, `ENemy`/`TArgets`, `NEutral`, `CAptured`, a range `n`,
  `ALl`, `LIst`/`SUmmary`, `And`/`&`. Enemy objects are flagged `*`.
- **`M <vpos> <hpos>`** — warp move. Max speed warp 6, safe warp 4;
  energy use scales with the square of the factor, doubled if shields
  are up. `M C <ship>` moves adjacent to a ship ("ram"). Sets green.
- **`NE`** — display `GAM:DECWAR.NWS` (version notes).
- **`PH [energy] <vpos> <hpos>`** — fire phasers at one target within
  10 sectors. Default 200 ship energy; 50–500 allowed. Damage falls off
  with distance. ~5% chance of phaser-bank damage at 200 energy, up to
  ~65% at 500. If shields are up they are briefly dropped to fire,
  costing another 200 energy. Friendly targets are cancelled. Puts you
  on red alert. Can damage planetary builds but not destroy a planet.
- **`PL [<keywords>]`** — planet info (default range 10, all sides).
- **`PO [Me|Federation|Empire|Romulan|All]`** — score breakdown. 500 per
  enemy destroyed, 100 per planet captured, 1000 per base built;
  −50 per star destroyed, −100 per planet destroyed.
- **`QUIT`** — leave the game for good (ship released, counts as a
  casualty). To step out only briefly, use `^C` instead; under red
  alert you must `QUIT`.
- **`RA ON|OFf`**, **`RA Gag|Ungag <ship>`** — turn the sub-space radio
  on/off, or ignore/restore a specific ship's messages.
- **`RE [<units>]`** — repair device damage (default 4 s: 50 units, +50
  more if docked). Does not reduce ship damage; docking does that.
- **`SC [U|D|R|L|C] [<range>|<vr><hr>] [W]`** — scan (default 10
  sectors). Direction keywords limit the field; `W` flags empty sectors
  within enemy base/planet range with `!`.
- **`SE <keyword> <value>`** — set input/output defaults (see table).
- **`SH UP|DOWN`**, **`SH TRANSFER <energy>`** — raise (costs 100 ship
  energy) or lower shields, or move energy to/from shields (free).
- **`SR [...]`** — like `SC` but default range 7.
- **`ST [Condition|Location|Torpedoes|Energy|Damage|Shields|Radio]`** —
  full or partial status report. `ST` shows stardate plus all key
  attributes.
- **`SUM [<keywords>]`** — like `LI` but summarizes by default (counts
  of ships, bases, planets per side).
- **`TA [<keywords>]`** — `LI` restricted to enemies within 10 sectors —
  the fast in-battle target list. `TA` = `LI EN 10`-style.
- **`TE All|Federation|Empire|Enemy|Friendly|<ships>;<msg>`** — radio a
  message with no range limit (ship names may be comma-separated).
- **`TI`** — times: game elapsed, ship elapsed, job run time, clock.
- **`TO <n> <v1><h1> [<v2><h2> [<v3><h3>]]`** — fire 1–3 photon
  torpedoes along a path (10-sector max, 8-sector minimum; anything on
  the path can intercept). Uses no ship energy. Torpedoes can be
  deflected by shields/damage/misfires (a misfire aborts the rest of
  the burst); they can nova a star and destroy a stripped planet.
  Friendly hits are cancelled. Puts you on red alert.
- **`TR <ship>`** / **`TR OFf`** — tractor-tow a same-team ship (both
  adjacent, both shields down). Towing costs 3× normal movement.
- **`TY OPtion|OUtput`** — show the game option and output settings.
- **`USERS`** — list ships in the game with captain, TTY speed, PPN,
  TTY and job numbers (medium/short output trims these).

## Device damage

Devices (Warp engines, Impulse engines, Torpedo tubes, Phaser banks,
Deflector shields, Computer, Life Support, Sub-space radio, Tractor
beam) carry damage of their own: below 300 units performance degrades,
at 300+ the device is inoperative. Example effects: damaged warp caps
speed at 3; inoperative computer makes warp/impulse navigation inexact;
inoperative life support must be repaired or the ship docked within 5
stardates or the crew dies. Device damage (not ship damage) can be
repaired with `RE` while under way.

## Docking resources per move

| Resource | Base | Planet |
|---|---|---|
| Ship energy | +1000 | +500 |
| Shield energy | +500 | +250 |
| Photon torpedoes | +10 | +5 |
| Life support reserves | +5 | +5 |
| Ship damage | −100 | −50 |
| Ship damage, if already docked | −200 | −100 |

## Pause times (real time per command)

| Command | Pause |
|---|---|
| BUILD | 5–7 s |
| CAPTURE | 5 s + 1 s per enemy build |
| DOCK | 2–4 s |
| IMPULSE | 2–4 s |
| MOVE | 2–4 s |
| REPAIR | (0.08 × repair size) s, ×0.5 if docked |

Phaser banks cool 3–6 s each (+ phaser damage/100); torpedo tubes reload
2–4 s per torpedo (+ tube damage/100 per torpedo). These times lengthen
when a slow terminal is in the game.

## SCAN symbols

| Symbol | Meaning |
|---|---|
| `E F I L N S T V Y` | Federation warships |
| `B C D G H J M P W` | Empire warships |
| `~~` | Romulan warship |
| `[]` / `()` | Federation / Empire starbase |
| `@` | Neutral planet |
| `+@` / `-@` | Federation / Empire planet |
| `*` | Star |
| (blank) | Black hole |
| `.` | Empty sector |
| `!` | Empty sector within range of an enemy port (`SC W` only) |

## SET options

| Keyword | Value | Meaning |
|---|---|---|
| `Name` | `<name>` | change captain name (shows in `USERS`) |
| `Output` | `Long`/`Medium`/`Short` | verbose ↔ cryptic hit messages |
| `Scan` | `Long`/`Short` | 2-char ↔ 1-char scan symbols |
| `Prompt` | `Normal`/`Informative` | `COMMAND:` ↔ `>` (prefixed with flags) |
| `Ttytype` | e.g. `VT100` | tells DECWAR the terminal type |
| `OCdef` | `Absolute`/`Relative`/`Both` | coordinate *output* format |
| `Icdef` | `Absolute`/`Relative` | coordinate *input* default |

The informative prompt marks state before the `>`: `S` shields down or
<10%, `E` energy <1000 (yellow alert), `D` damage >2000, `nL` life
support critically damaged.

## Pre-game and DECWAR.INI

Before entering a ship, DECWAR offers a pre-game (`PG>` prompt, program
`DECWPG`) with `Activate Gripe Help News Points Quit Summary Time Users`
— `ACTIVATE` exits into normal ship setup. After ship selection DECWAR
reads `DECWAR.INI` from your PPN (if present), running its lines as if
typed (typically `SET` and info commands), then switches to TTY input.

## Handy keys

- `^O` — suppress piling-up output so your next command runs immediately.
- `^C` — abort stacked commands; at the command prompt it aborts the game
  and returns to monitor (ship goes back to the pool).
- `^T` — show the current program name (`DECWTI` waiting for input,
  `DECWRN` executing, `DECWSL` sleeping, `DECWPG` pre-game).
- `<ESC>` — repeat the previous command.
