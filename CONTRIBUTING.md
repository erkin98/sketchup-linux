# Contributing to sketchup-linux

Thanks for helping improve this project. This guide covers how to report issues,
test changes, and submit pull requests.

---

## Reporting issues

When filing a bug, include:

1. Your Linux distro and version (`lsb_release -a` or `cat /etc/os-release`)
2. Steam installation type: Flatpak, APT/native, or Snap
3. SketchUp version you're trying to install
4. GE-Proton version used
5. **Full log file** from `~/.cache/sketchup-linux/install-*.log`
6. The exact command you ran

---

## Development setup

```bash
git clone https://github.com/erkin98/sketchup-linux.git
cd sketchup-linux

# Install dev tools
make install-dev

# Run linter
make lint

# Run tests (requires bats-core)
make test
```

---

## Code style

- **ShellCheck must pass with zero warnings** (`make lint`)
- Follow existing conventions in `install.sh`:
  - `set -euo pipefail` always on
  - Variables in `"double quotes"` everywhere
  - Arrays for command lists (`PROTONTRICKS_CMD=()`)
  - `mapfile -t` for reading file lists
  - `run()` wrapper for all destructive commands (enables `--dry-run`)
  - `phase_enabled N || return 0` guard at the top of every phase
  - Distro-specific error messages using `$DISTRO_PM`
  - Exit codes: `E_SUCCESS=0`, `E_ERROR=1`, `E_USER_ABORT=2`, `E_DEP_MISSING=3`

---

## Testing

Tests live in `tests/install.bats` and use [bats-core](https://github.com/bats-core/bats-core).

```bash
# Run all tests
make test

# Run a single test file
bats tests/install.bats

# Run tests verbosely
bats --verbose-run tests/install.bats
```

Adding new tests:
- Mock external commands (`flatpak`, `curl`, `protontricks`) with `export -f`
- Use `setup()` / `teardown()` for temp directories
- Test each phase function in isolation
- Include both happy-path and error-path cases

---

## Submitting changes

1. Fork the repo and create a feature branch
2. Make your changes
3. Run `make lint` and `make test` — both must pass
4. Open a PR with a clear description of what changed and why
5. Reference any related issues

---

## Versioning

This project uses [Semantic Versioning](https://semver.org/).
Update the `VERSION` variable at the top of `install.sh` for any release.
