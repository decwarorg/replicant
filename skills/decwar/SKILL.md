---
name: decwar
description: |-
  Connect to DECWAR on a DEC-10 over an interactive telnet session.
  Help a human understand the game and choose moves, or play on the
  user's behalf when explicitly asked. Use for DECWAR, the user's
  DEC-10, or telnet-based DEC-10 game sessions.
---

# DECWAR on the DEC-10

Help the user play DECWAR on their DEC-10. The game and its command
interface depend on the host's installation; learn the live interface
from its welcome text and in-game help instead of guessing commands.

## Choose how to play

At the beginning of a session, establish one mode:

- **coach** — the human operates telnet; explain screens and rules, and
  suggest one move at a time.
- **assist** — share the live session. Explain the situation and
  recommend a move, but wait for the human to approve each game action
  before sending it.
- **play** — operate the game directly when the human explicitly asks
  you to play. Explain major decisions and pause when asked.

Do not silently switch from coach or assist to play. The human's request
to "play for me" or equivalent authorizes play mode for that session.
When another person is actively entering commands, do not send input
until they hand control back.

## Connect

Get the DEC-10 hostname and telnet port from the user; do not guess a
host, port, account, or password. If the host or port is not known yet,
ask for it. Use Hermes' interactive terminal/shell session to keep one
telnet connection open:

```text
telnet <dec-10-hostname> <telnet-port>
```

Use the host's documented login procedure. Do not put passwords in
commands, saved files, skill text, or chat. Let the user enter
credentials directly in the terminal if needed. Do not use a sequence
of separate one-shot telnet commands: DECWAR is an interactive program
and its state belongs to the live connection.

If the `telnet` client is unavailable, report that clearly and ask the
user to install or provide an approved interactive telnet client. Do not
silently substitute raw TCP, `nc`, or guessed protocol handling; telnet
negotiation and the game's session are stateful.

After login, inspect the server's output, identify the DECWAR start
procedure and available help, and use those instructions. If the
session lands at an operating-system prompt rather than in DECWAR, ask
the user how this system starts the game instead of trying commands
that could change files or system state.

## Play safely and collaboratively

- Treat the live game screen and help as the source of truth for
  available commands, turn order, and game rules. Explain uncertainty
  rather than inventing syntax.
- Keep the user informed: summarize the current situation, state a
  proposed action and its expected effect, then act according to the
  selected mode.
- In assist mode, do not send a move until the user approves that
  specific move. In play mode, make game moves without asking for
  per-move confirmation, but ask before account, system, or other
  non-game changes.
- Send only complete commands that the prompt is ready to receive.
  Confirm the result before deciding on the next action; recover from
  rejected commands using on-screen help, not repeated guesses.
- Respect any other players and the host's rules. Never disrupt the
  DEC-10, leave DECWAR unexpectedly, or run operating-system commands
  through a login prompt.
- On disconnect or an unclear prompt, stop and explain what happened.
  Do not claim a move succeeded until its result appears in the
  session.

## How to help

The human can ask for explanations of the current screen, strategic
options, or a specific move. Separate observed game state from
inference: quote or summarize what the server showed, then explain the
reasoning behind advice. When playing, provide concise commentary
before consequential actions and a brief status update after them.

Use DECWAR knowledge to help the human learn, not just to optimize a
score. After the session, summarize its outcome and any host-specific
commands or rules worth recording. Do not save local host details or
credentials in this shared skill.
