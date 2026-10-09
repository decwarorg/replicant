---
name: decwar
description: |-
  Play DECWAR on a DEC-10 over an interactive telnet session — coach,
  assist, or play for the user. Covers connecting, the command set,
  ship energy/shield/damage mechanics, combat, docking, and defensive
  strategy. Use for DECWAR, the user's DEC-10, or any telnet-based
  DEC-10 game session.
---

# DECWAR on the DEC-10

DECWAR is a real-time space battle game for 1–18 players on a DEC-10.
Each player captains one ship on a separate terminal; the jobs interact
through a shared high segment, so players join and leave freely.

**Objective:** destroy every enemy ship and starbase, and capture every
enemy planet, before the other side does the same to you.

This skill is the operating guide. The `references/` files hold the full
command syntax, the mechanics, and the strategy guide — load the one you
need. The live game screen and in-game `HELP` are always the final
source of truth for the host's version: if a detail here disagrees with
the running game, follow the game.

## The game at a glance

- **Forces.** Federation (Humans) vs. Empire (Klingons); 9 ships per
  side, identical in strength. Federation: Excalibur, Farragut,
  Intrepid, Lexington, Nimitz, Savannah, Trenton, Vulcan, Yorktown.
  Empire: Buzzard, Cobra, Demon, Goblin, Hawk, Jackal, Manta, Panther,
  Wolf. A game may also carry **Romulans** (one at a time, cloaked,
  unlimited energy and torpedoes) and **black holes** (deadly if you are
  displaced into one).
- **Galaxy.** A 75×75 sector grid. Ships move by warp (max 6, safe 4) or
  impulse (1). Torpedo and sensor ranges are 10 sectors.
- **Three health numbers.** Ship energy (starts 5000 — spent on movement
  and phasers, lost when hit; at 0 the ship is dead), shield energy
  (starts 2500 — a separate, transferable pool), and ship damage
  (starts 0 — reduced only by docking; at 2500 the ship is destroyed).
- **Docking is the core survival mechanic.** A friendly base (or
  captured planet) refuels, re-arms, repairs, and resets you to green.
  Defenders should dock early and often.

## Choose how to play

At the start of a session, establish one mode and keep it:

- **coach** — the human operates telnet; explain screens and rules, and
  suggest one move at a time.
- **assist** — share the live session. Explain the situation and
  recommend a move, but wait for the human's approval of that specific
  move before sending it.
- **play** — operate the game directly when the human explicitly asks
  you to play. Explain major decisions and pause when asked.

Do not silently switch from coach or assist to play. "Play for me" or
equivalent authorizes play mode for that session. If another person is
typing commands, send nothing until they hand control back.

## Connect

Get the DEC-10 hostname and telnet port from the user; never guess a
host, port, account, or password. Keep one interactive connection open
from Hermes' terminal/shell session:

```text
telnet <dec-10-hostname> <telnet-port>
```

Do not use a sequence of one-shot telnet commands: DECWAR is interactive
and its state belongs to the live connection. If `telnet` is
unavailable, report that and ask for an approved interactive client — do
not silently substitute raw TCP, `nc`, or guessed protocol handling.

A typical DEC-10/DECWAR entry (confirm live — hosts vary): log in, run
the game with `R GAM:DECWAR`, give your name, choose Regular or
Tournament, choose a side (Federation or Empire), pick a ship, then
reach the command prompt (`>` with `SET PROMPT INFORMATIVE`, or
`COMMAND:` by default). If the session lands at an operating-system
prompt instead of DECWAR, ask the user how this host starts the game
rather than trying commands that could change files or system state.
Let the user enter credentials directly; leave passwords out of
commands, files, skill text, and chat.

## Play the game

Commands are one word, accepted at their shortest unambiguous
abbreviation (usually two letters, sometimes one). Coordinates are
`<vpos> <hpos>` — vertical position then horizontal. Give several
commands on one line separated by `/`; a `TELL` must be last. Full
syntax is in `references/command-reference.md`.

Highest-value commands:

| Command | Purpose |
|---------|---------|
| `BA` / `BA CL` | list your bases / the closest friendly base |
| `M <vpos> <hpos>` | warp move; `M R <dv> <dh>` relative; warp 4 is safe |
| `DO` / `DO ST` | dock at an adjacent friendly base/planet; `DO ST` also shows status |
| `ST` | status: stardate, location, energy, damage, shields, torps, radio |
| `SC` / `SC W` | scan 10 sectors / scan marking enemy-base danger zones |
| `TA` | targets — enemies within range |
| `PH [energy] <vpos> <hpos>` | phasers (200 energy default, 50–500) |
| `TO <n> <vpos> <hpos>` | fire `n` photon torpedoes (1–3) |
| `SH U` / `SH D` / `SH T <e>` | raise / lower shields / transfer shield energy |
| `TE <ship>;<msg>` | radio a message; `TE ALL;<msg>` broadcasts |
| `HELP <command>` | authoritative help for any command |

A sound beginner routine — defend a base and stay alive:

1. `BA` and pick a base to defend; a corner base is easier than center.
2. `M` toward it at warp 4; `DO ST` on arrival to fully recover.
3. Patrol between a primary and a nearby secondary base; dock often.
4. On attack: phasers first to drop the target's shields, then
   torpedoes. Torpedoes cost no ship energy but can be deflected; a
   phaser blast (or being hit) puts you on red alert.
5. Fall back to the secondary base if overwhelmed — you buy time for
   teammates to reinforce. Remember a torpedo can turn a nearby star
   into a nova.

## Pitfalls

- Don't park next to stars; a torpedo can nova them. Exploit an enemy
  that does.
- Don't batter 85–100% shields with torpedoes — weaken with phasers
  first.
- Don't enter an enemy base's 4-sector range; it will pound you. (A
  planet's range is 2.)
- The weapons officer cancels fire on friendly ships/bases/planets, but
  confirm friend vs. foe with `SC` / `TA` / `HELP SCAN` rather than
  relying on it.
- Shields up doubles movement energy; warp 5–6 risk engine damage.
- When output piles up mid-battle, `^O` suppresses it; `^C` aborts
  stacked commands; `<ESC>` repeats the last command.

## References

- `references/command-reference.md` — every command, its syntax, and the
  key mechanics (coordinates, `SET` options, the dock table, pause
  times, scan symbols).
- `references/defense-strategy.md` — how to defend bases and stay alive.
- `assets/DECWAR.HLP` — the verbatim in-game help text (DECWAR 2.3),
  the source for `command-reference.md`.
