# DECWAR Replicant

**A Hermes companion for DECWAR on the DEC-10.** Connect through
telnet, get help understanding the game and choosing moves, or ask the
agent to play on your behalf.

Hermes provides the interactive agent; DeepSeek can provide its language
model. The DECWAR skill itself is model-provider independent.

## Play with Hermes

Install and configure Hermes using this repository's `install.sh`.
Choose **Install Hermes Agent** and configure DeepSeek when prompted, or
use another model provider supported by Hermes. The installer links the
DECWAR skill into Hermes automatically.

Start Hermes in interactive mode:

```sh
hermes --tui
```

Tell Hermes how you want to play:

- **Coach:** you operate the game; Hermes explains the screen and
  suggests one move at a time.
- **Assist:** Hermes recommends moves and waits for your approval before
  sending each one.
- **Play:** ask Hermes to play for you; it can make game moves directly
  and explain its decisions.

For example, ask: "Help me play DECWAR" or "Play DECWAR for me."

## Connect to the DEC-10

Provide Hermes with the DEC-10 hostname and telnet port. It keeps an
interactive telnet session open, follows the host's login instructions,
and learns the available game commands from the live session. DECWAR
startup procedures and command sets vary by host, so Hermes does not
guess a server address, credentials, or command syntax.

Enter passwords directly into the interactive terminal when prompted;
do not paste credentials into chat or save them in files. If the host
requires a game-start command or account-specific instructions, provide
the directions from its operator. Hermes will ask rather than run
unfamiliar system commands.

## Hermes and DeepSeek setup

Open this repository in its Linux Dev Container in VS Code, then run:

```sh
./install.sh
```

Choose **Install Hermes Agent**. The setup can install Hermes, configure
a DeepSeek API key, and link the available skills. You can defer model
configuration or select another provider supported by Hermes. A DeepSeek
key can be entered during setup or read from a file; setup instructions
are shown by the installer.

`DRY_RUN=1 ./install.sh` previews the installer without making changes.

## Development environment

Develop this project in its Linux Dev Container, not directly on macOS.
Open the repository in VS Code with Docker available, then select
**Reopen in Container** (or run **Dev Containers: Reopen in Container**
from the Command Palette).

Use Git from the VS Code integrated terminal inside the container.
Preserve the repository's existing remote and authentication setup.

## Project contents

- **`skills/decwar/`** — Hermes guidance for connecting to DECWAR,
  assisting a human, and playing when explicitly asked.
- **`install.sh`** — interactive setup for Hermes and the bundled
  skills.
- **`hermes-specific/SOUL.md`** — behavioral guidance installed into
  Hermes.
The DECWAR skill does not include a DEC-10 endpoint or credentials.
Supply connection details for the system you are authorized to use.

## License

MIT — see [LICENSE](LICENSE).
