# agent-pdp1

AI copilot skills and tools for the PiDP-1. This package turns an AI
agent (Hermes Agent, Claude Code, OpenCode, or any agent that reads markdown
skills) into a helpful copilot for your PDP-1: 
- writing and assembling programs, debugging code, 
- handling the front panel, and the whole machine,
- reading and visually interpreting the Type 30 display. 

Or, much more fun: 
- Let it be your tutor, interactive guide through the PDP-1 world.
- Let it review source code. The Code Review skill is an amazing teacher!

Works on a PiDP-1 (needs 4, perhaps 2 GB of RAM) or any regular Linux  
that has the pidp1 package already installed. 

## Eye candy

<Tic-tac-toe> <Rotating-cube> <dodecahedron> <hello-world-typewriter>

## Install

    git clone https://github.com/obsolescence/agent-pdp1.git /opt/agent-pdp1
    cd /opt/agent-pdp1
    ./install.sh

One installer, one menu:

    1) Install basic setup        — update the pidp1 package, rebuild all
                                    binaries, install the agent tools, test
                                    the emulator on port 1040. Leaves the
                                    machine stopped for a clean start.
    2) Install Hermes Agent       — unattended Hermes install; connect
                                    DeepSeek (or defer that); wire the six
                                    skills, pdp1-learnings and SOUL.md into
                                    the agent; verify with a real round-trip.
    3) Update/restore Core Skills — pull the latest from GitHub. Edits to
                                    the six core skills are replaced; your
                                    own files (pdp1-learnings, SOUL.md) are
                                    left alone.

Every step explains itself as it runs, and every step can be declined.
The Hermes step wants a DeepSeek API key — paste it, or point the
installer at a file that holds one (e.g. ./install.sh ~/.hermes/.env).
There is no particular reason to use DeepSeek. It is just, at the time
of writing, the cheapest, and very much good enough. Hermes will work
with any model — add others later, on the fly.

DRY_RUN=1 ./install.sh simulates the whole thing without changing
anything; handy as a preview or for testing.

## What's inside

skills/ — the six skills, frozen and human-curated. Instead of editing these
skills, agents are instructed to write what they learn to their own 
pdp1-learnings skill file. 

You can decide otherwise, we noticed that it 
is better to go through the isolated learnings text file rather than have
the 'canonical knowledge' polluted by agents in their moments of confusion.


- pdp1-assembly      — instruction set, MACRO-1, patterns
- pdp1-debugging     — the port-1040 protocol, recipes, the pdp1dbg helper client
- pdp1-plumbing      — ports, copilot etiquette, building/starting/loading/updating
- pdp1-type30-vision — reading the screen (pdp1_dpy tool)
- pdp1-tutor         — guided tours of PDP-1 applications (in preparation)
- pdp1-code-review   — structured code review workflow

hermes-specific/ — SOUL.md (the rules file Hermes reads on every
request) and the pdp1-learnings template (the agent's own learning
file, copied per install, never shared).

If you are new to this, using Hermes as your agent is probably the best
idea. It has been carefully set up so as to actively learn from new
experience, without messing up the 'canonical knowledge base'.

## Updating

    ./skills/update.sh    # unprotect, git pull, re-protect

(or equivalently: menu option 3 of ./install.sh)
