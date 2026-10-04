# Contributing to OmaSwitch

Thanks for helping. Bug reports, ideas, and pull requests are all welcome.

## Reporting a bug

Use the [bug report form](https://github.com/piyush97/omaswitch/issues/new?template=bug_report.yml). The most useful reports include:

- Your Omarchy, Quickshell, and Qt versions (`quickshell --version` prints the last two)
- Whether the problem persists with OmaSwitch disabled (`omarchy plugin disable piyush.omaswitch`) — this separates plugin bugs from shell or compositor bugs
- For a crash: the Quickshell crash report
- For missed OCR matches: the app, and roughly what text was on screen

## Development setup

Clone into your Omarchy plugin directory and enable it:

```bash
git clone https://github.com/piyush97/omaswitch.git ~/.config/omarchy/plugins/piyush.omaswitch
omarchy-shell shell rescanPlugins
omarchy plugin enable piyush.omaswitch
```

Watch for QML errors while you work:

```bash
journalctl --user -f | grep -Ei 'piyush.omaswitch|Switcher.qml|qml.*(error|warning)'
```

## Before opening a pull request

```bash
node test_model.js
omarchy plugin validate .
git diff --check
```

CI runs the model tests, a manifest check, and a whitespace check on every pull request.

## Guidelines

- **Keep logic in `Model.js`.** It is plain JavaScript with no QML dependencies, so behavior can be tested without a compositor. Add a regression test for every bug fix.
- **Never store compositor-owned objects** (`HyprlandToplevel`, `Toplevel`) in list models or long-lived properties. Store plain snapshots and look the live object up by address when needed. Windows can be destroyed at any moment.
- **Treat window metadata as untrusted.** Titles, app IDs, and addresses come from other programs. Render text as `Text.PlainText`, validate before it reaches a process, and never build shell strings from it.
- **Keep it light.** No new runtime dependencies, daemons, or network access. OCR must stay on-device and session-only.
- **Bump `manifest.json`'s `version`** and add a `CHANGELOG.md` entry for user-visible changes.

## Releases

1. Bump `manifest.json` and update `CHANGELOG.md`.
2. Merge to `main` and confirm CI passes.
3. Tag and create a GitHub release at that exact commit.
4. Submit the exact commit through the [marketplace verification form](https://github.com/omacom/omarchy-plugin-marketplace/issues/new?template=verify-plugin.yml) without changing its headings; put release notes in a comment.
