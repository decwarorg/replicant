# Defending bases and staying alive

A practical, low-stress approach for new captains. Adapted from the
project's "Playing Defense and Staying Alive" guide. The message is not
"always retreat" — it is to play the bases and manage energy.

## Why defense

DECWAR gets overwhelming fast. Defending a friendly base gives you a
clear, repeatable plan and an automatic response to trouble: you are
always near somewhere to dock. When your side loses all its bases you
are close to losing the game, so dedicated defenders are a core part of
an effective team. Docking at a base restores ship energy, shield
energy, repairs ship damage, and re-arms torpedoes — so simply standing
near the base you defend keeps you alive even through heavy damage.

## Pick a base

Use `BA` to list your bases. Choose one to defend — usually the nearest,
though a base in a strong location (a corner of the galaxy) is easier to
hold than one in the center. Then `M` toward it at a moderate, safe
speed (warp 4; warp 5–6 risk engine damage), shields up is fine since
you can dock to refill on arrival. Dock (`DO`, or `DO ST`) as soon as
you arrive to fully recover and prepare to fight.

## Patrol two bases

Once your primary is topped up and things are quiet, choose a nearby
secondary base as an escape hatch. Patrol between them. Your primary is
the stand-and-fight location; the secondary is the fallback you run to
and dock at if a raid overwhelms the primary. Defending two bases is a
good starting target (skilled players cover three or more). Think of the
space between them as your zone; taking responsibility for it makes you
an active, collaborative team member. Use `SC` and radio (`TE`) to watch
the zone and keep teammates informed ("patrolling and defending the
two bases in the upper-left").

## When attacked

- **Dock regularly** so your health never gets low. Docking fast in
  combat is a huge advantage — done well, it takes several coordinated
  enemies to kill you or the base.
- If enemy ships concentrate and overwhelm your base, withdraw along
  your patrol path to the secondary base. Even if they follow, you buy
  valuable time for teammates, who will rush to your zone; this is how
  big fleet battles around bases begin.
- **Weapons mix:** pepper the enemy with phaser fire first (`PH`) to
  lower their shields, then finish with photon torpedoes (`TO`). Two or
  three phaser blasts then torpedoes works well; don't rely on one
  weapon.
- **Use nearby stars as landmines** around your base (`SC`): a
  well-placed torpedo can nova a star, which is extremely destructive —
  but never do it next to your own base or teammates.

## The energy model (why docking is vital)

Your ship has ship energy (a battery that drains with time, movement,
firing, and taking hits — and acts like life points), a separate shield
energy pool (transferable), and ship damage (accumulates with hits;
reduced only by docking). Losing energy and accumulating damage is how
you die. Docking is by far the most effective recovery: it restores ship
and shield energy, repairs damage, and replenishes torpedoes. Check
`ST` regularly; in combat you will usually have less energy left than
you expect.

## Command summary

- `BA` lists friendly bases and locations; `BA CL` the closest.
- `M <vpos> <hpos>` moves by warp. Warp 4 is the safe maximum; energy
  use rises with the square of the factor. `M R 4 0` moves four up.
- `DO` docks at an adjacent friendly base/planet (refuel, re-arm,
  repair); `DO ST` docks then reports status. Bases restore more per
  turn than planets.
- `ST` shows full status (location, ship/shield energy, damage,
  torpedoes, radio). `ST E D SH`, `ST L` for subsets.
- `SC` scans up to 10 sectors; `SC 4` a smaller one; `SC W` marks
  sectors in range of enemy bases/planets as dangerous. Stars are `*`.
- `PH <vpos> <hpos>` fires phasers at one sector within 10; default 200
  ship energy, 50–500 allowed.
- `TO 1 <vpos> <hpos>` fires one photon torpedo along a path (it may be
  deflected or hit something else, and can nova a star).
- `TE ALL;<msg>` radios everyone; narrow with a ship name or `FRIENDLY`.
  `RA ON` re-enables a radio that was turned off.

For command-specific help in game, type `HELP` followed by the command
(`HELP MOVE`, `HELP TORPEDOES`).

## Coordinates and abbreviations

DECWAR accepts the shortest unambiguous abbreviation, usually two
letters. Coordinates are vertical position then horizontal. Use an
absolute location (`M 37 45`) or a relative one (`M R 4 -5`). Many
players set relative as the default with `SET ICDEF REL` (often in
`DECWAR.INI`) so `M 4 -5` suffices.

## Tactical notes from live play

- **Moving targets need fresh coordinates.** A phaser hits only the
  exact sector, and ships move every few seconds, so a `TA`/scan read a
  turn ago often aims at empty space. Re-scan immediately before firing,
  or fire a torpedo spread across two or three likely sectors to bracket
  the target. A ship is destroyed when its *damage* reaches 2500, not
  when shields hit zero — a target at high shields can still die to a
  small hit if its damage is already high.
- **Objects block movement.** A move into a star, planet, or base is
  answered with "Collision averted" and does not move you. When flying
  without a scan you may burn several turns on collisions; scan the lane
  first. Nova'd stars and the whole 4-sector ring around an enemy base
  (flagged `!` by `SC … W`) are places to avoid lingering.
- **Watch the prompt flags.** With `SET PROMPT INFORMATIVE` the `>`
  prompt is preceded by `S` (shields down/<10%), `E` (energy <1000,
  yellow alert), `D` (damage >2000), `nL` (life support critical) — a
  quick read on how much trouble you are in.
- **Team play.** Capture nearby neutral planets to silence their fire
  and gain a nearby dock; radio teammates (`TE`) your zone. When badly
  hurt with no base nearby, break off rather than trade shots.
