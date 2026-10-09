# Development environment

- Develop and run project commands in the Linux Dev Container defined in
  `.devcontainer/`. Do not run project scripts, tests, builds, or package
  managers directly on the macOS host.
- If the workspace is not attached to the Dev Container, ask the user to reopen
  it in the container before running project commands.
- Host-side Docker commands are permitted only to build, start, or manage the
  Dev Container.
- Initialize repository submodules from inside the container with
  `git submodule update --init --recursive`.
