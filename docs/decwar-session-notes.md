# DECWAR session notes — first live game (vs bots)

_2026-10-09. Captured from a Hermes play session on a KL‑10 / TOPS‑10 DEC‑10._

## The session

- **Setup:** Regular galaxy, Romulans included, no black holes.
- **Forces:** 5 Federation vs 5 Empire — and the "other players" were **bots**
  (ROBOT3/5/7/9 = Federation; CIC2 + ROBOT4/6/8/10 = Empire), plus the Romulan NPC.
- **Ship:** Federation **Yorktown** (captain HERMES).
- **Result: Empire victory.** "THE WAR IS OVER!! The Klingon Empire is
  VICTORIOUS!!" — the Empire destroyed every Federation base.
- **Final points:** Yorktown **630.2**; Federation 38,642; Empire 46,874;
  Romulans 1,497.

### Play highlights

- Docked at a base and captured two adjacent neutral planets (37‑64, 39‑64)
  → +200 points, and they stopped shooting us.
- Set up a working patrol loop between a primary base (40‑62) and a secondary
  (41‑69), docking at each end, while the Romulan raided a distant base.
- In a later melee: a **star went nova** (409 units of damage to a ship next to
  it), an Empire **Hawk** destroyed base 46‑60, and a Federation ship then
  killed the Hawk.
- **Scored a ship kill:** finished an Empire **Demon** with a phaser once its
  accumulated *damage* passed 2500 → +500.
- **Downfall:** the Empire ran a base‑killing campaign, cutting Federation
  bases 10 → 8 → 6 → 3 → 1. Our repair runs were beaten every time (bases 68‑23
  and 74‑6 were destroyed just before we reached them), and we ended up pinned
  in an undiscovered Empire base's 4‑sector kill‑zone (74‑12) with the energy
  flag at `<1000`.

## Lessons learned

- **A ship dies on damage, not shields.** Destruction happens when *ship
  damage* reaches 2500, so a target showing 90%+ shields can still be finished
  by a small hit if its damage is already high. Don't assume a high‑shield
  target is safe from a kill.
- **Moving targets need fresh coordinates.** A phaser hits only the *exact*
  sector; bots move every few seconds, so a `TA`/scan read a turn earlier aims
  at empty space. Re‑scan immediately before firing, or fire a **torpedo
  spread** across two or three likely sectors to bracket a moving target.
  (Computed coordinates, `PH C <ship>`, would track a target but need a
  terminal slower than 1200 baud.)
- **Objects block movement.** A move into a star, planet, or base is answered
  with `Collision averted` and does not move you; flying blind off‑scan burns
  turns on collisions. Scan the lane first.
- **Danger zones and novas.** `SC … W` flags every sector within 4 of an enemy
  base/planet with `!`. Never linger in that ring, and stay clear of freshly
  nova'd stars — both are how ships die.
- **Read the prompt flags.** With `SET PROMPT INFORMATIVE` the `>` prompt is
  prefixed by `S` (shields down/<10%), `E` (energy <1000, yellow alert),
  `D` (damage >2000), `nL` (life support critical) — a fast trouble readout.
- **Energy is the real clock.** Moving with shields up doubles the cost, and
  each phaser with shields up costs an extra 200. Skipper the energy and you
  get the `<1000` warning and can't fight or run.

## Take‑aways for next time

- **Bases decide the game.** Pick a base early and never get more than a hop or
  two from a dock — the Empire wins by killing bases, not by chasing ships.
- Keep a **secondary base** as a retreat; when overwhelmed, fall back and
  dock rather than trade shots.
- **Phasers first, then torpedoes** — weaken shields before spending torpedoes.
- Confirm an exit plan: `QUIT` the game, then `KJOB` on TOPS‑10, then `^] quit`.

## Play‑by‑play — the agent's running commentary

The play‑by‑play I narrated to myself while at the controls (lightly tidied;
the gist is verbatim).

**Getting in**

- "Got it — port 2030, not 2020. Installing the telnet client now."
- "`telnet` (GNU inetutils 2.5) is installed. Now opening one **persistent**
  interactive session — the skill requires a single live connection, not
  one‑shot commands."
- "Found it: the DECWAR server is on the **host**... `localhost` inside the
  container can't reach the host. Connecting via the host gateway."
- "That's a KL‑10 login prompt, and it's waiting for a login name before DECWAR
  can start. I don't guess accounts, and I never handle passwords."
- "Thanks — logging in as `decwar` (no password; if it asks for one I'll stop)."
- "Logged in (Job 3) — no password needed. Now starting DECWAR."
- "Starting up. It asks for a captain name — I'll use **HERMES** (changeable
  later with `SET NAME`)."
- "It offers `HELp`, `PREgame`, or blank. I'll press Enter for the normal ship
  setup (I already have the help text from the docs)."
- "First player, so I choose startup options... **Regular** galaxy, **include
  Romulans** (otherwise a solo game has no opponent), **no black holes** (less
  random death)."
- "Ships are identical in strength, so I'll take the **Excalibur**."

**First game (solo, Regular galaxy)**

- "Full health: SDate 0, Green, Loc 22‑72... Now let's find our bases."
- "Nearest friendly base is **40‑62** (18 up, 10 left); all 10 bases are at
  100%. Per the defense guide I'll move there at safe warp 4, dock, and set up
  a patrol."
- "Encountered a **neutral planet at 37‑64** — our move was collision‑averted
  and the planet took a harmless potshot (0.0 damage). Let me look around
  before continuing."
- "**Two neutral planets at 37‑64 and 39‑64** sit between us and the base...
  I'll go straight up column 65 (clear of them), then sidestep to the base's
  flank and dock."
- "Docked at 40‑63 (refilled). But the neutral planet at 39‑64 is adjacent and
  chips our shields every turn. Rather than just tank it, I'll **capture** the
  two neutral planets next to our base — that silences them, gains points, and
  gives us more friendly ports."
- "Confirmed: **39‑64 is now ours**... Now capturing the other neutral at 37‑64."
- "Capture needs adjacency. Moving to 38‑63 (adjacent to 37‑64) and capturing."
- "Both planets captured — **score: 200**, no enemies in range."
- "The wide scan shows **no enemy ships or bases** — just stars, our two
  captured planets, our base, and a second Federation base to the NE."
- "We're in good shape... The opening objective (reach a base, dock, secure the
  area) is done. What next?"
- "We're at 41‑66 — a **star at 41‑67** blocks the direct line east. Routing
  around it via row 42..."
- "Zone confirmed clear — **no enemy forces in range**... The Romulan remains
  far off at 18‑28."

**Second game (the live bot war)**

- "Logged in (Job 23, TTY16). Note the banner: **'Other jobs same PPN:
  3,14…22'** — a bunch of other jobs on the same account, i.e., the other
  players."
- "A live game: **5 Federation vs 5 Empire**, Romulans in play. Joining the
  Federation."
- "The other five Federation ships are taken... identical in strength — I'll
  take the **Yorktown**."
- "We're in as Yorktown at 44‑48, and it's hot immediately: an Empire `D`
  (Demon) already at 62.6% shields... a Federation base 46‑60 is under attack."
- "Now it's clear — the 'other players' are **bots** (ROBOT3/5/7/9 vs CIC2 +
  ROBOT4/6/8/10). Let me scan the battlefield."
- "Federation bases are taking a beating: **37‑36 down to 43.2%** and **46‑60
  at 73.2%**... I'll advance toward the embattled base 46‑60 (staying a step
  clear of the nova at 45‑58)."
- "Heavy action! A **star at 49‑57 went nova** (409 units!), an Empire **Hawk**
  is firing on a Federation ship... Let me confirm our exact position and
  targets before I engage."
- "The Empire **Hawk** is at 50‑61, shields ~59%... **range 5** from us (too
  close for torpedoes, perfect for phasers). Engaging — phasers on the Hawk."
- "Our phaser hit for 86, but the Hawk is **pounding base 46‑60 down to 12%**...
  I need to hit harder. Firing a heavier blast (300 units)."
- "The base 46‑60 was **destroyed** — but a Federation ship then **killed the
  Hawk**. My last phaser missed (the Hawk had moved; I fired at its old
  position — a reminder to re‑target in a fast fight)."
- "Situation update: Federation down to **8 bases**... I'll head toward the
  hotspot (65‑37) to engage whatever's hitting it."
- "Contact! An Empire **Goblin at 65‑34** is hitting our base 65‑37... range 6
  — phasers. Firing."
- "The Goblin's torpedoes hurt us (shields ~55%)... my phaser whiffed because
  we'd been **displaced** — so relative coords drift. Hit back with torpedoes."
- "The Federation is collapsing... my shots are missing because the bots keep
  moving. Let me get precise positions before firing again."
- "**We killed the Demon!** Our phaser finished it off — it had accumulated
  fatal damage. **+500 point ship kill.** But the Federation is hemorrhaging
  bases."
- "Tough spot: Federation down to **6 bases**... This is a real fork, so I'll
  check before committing the ship."
- "Our withdrawal path is blocked (three 'collision averted') — and an **Empire
  base (62‑31) is now near us**."
- "Now I see why [west is blocked]: the lane is walled off by **stars (69‑38,
  69‑36)** and a big **Empire danger zone**... plus a Cobra at 68‑30. There's
  a clear lane one row north — route around."
- "**Base 68‑23 was destroyed before we could reach it** — Federation down to
  **2 bases**... This looks like the endgame."
- "We blundered straight into an **Empire base at 74‑12**... our **energy flag
  is now 'E' (<1000)**... Retreating out of range first."
- "Worse: **base 74‑6 has been destroyed**... our retreat is blocked; we're
  stuck under the Empire base's guns with low energy. Let me scan for a way
  out."
- "We're boxed in the kill‑zone (the whole area is `!`), energy nearly gone
  (570, Yellow alert)... trying to move out — east is the shortest exit."
- "We escaped the kill‑zone... There's no viable place to repair, and the
  Federation is close to losing its last base."
- "The endgame resolved: base 5‑2 fell — **THE WAR IS OVER. The Klingon Empire
  is VICTORIOUS.**"

**Shutting down**

- "Understood. Before I tear anything down, one quick check..."
- "Back at the monitor prompt now. Logging off the account."
- "That's **TOPS‑10** (not TOPS‑20) — the logoff command here is `KJOB`."
- "Account logged off. Now closing the telnet connection."
