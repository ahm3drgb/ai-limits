# AI Limits

A macOS menu bar app with desktop widgets showing your Claude and ChatGPT usage limits at a glance: session, weekly and per-model (e.g. Fable) limits, with reset times.

## Features

- **Menu bar panel**: click the gauge icon for a glass dashboard in three styles (Rings, Bars, Dials).
- **Notch mode**: compact gauges beside the MacBook notch that expand on hover.
- **Floating window**: resizable and can be pinned on top of all spaces; shrinks to a compact bar list.
- **Desktop widgets**: Dial, Rings, Bars and Overview, in small, medium and large sizes, configurable per provider or meter.

## Requirements

- macOS 14 or later, Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Signed in to [Claude Code](https://claude.com/claude-code) for Claude limits
- Signed in to [Codex CLI](https://github.com/openai/codex) for ChatGPT limits

## Build and install

```sh
./install.sh
```

This generates the Xcode project, builds a Release copy, installs it to `~/Applications/AI Limits.app` and launches it.

Add widgets: right-click the desktop → **Edit Widgets…** → search **AI Limits**.

## How it works

The app reuses the logins that Claude Code (macOS keychain item `Claude Code-credentials`) and Codex CLI (`~/.codex/auth.json`) already keep, and calls the same usage endpoints those tools use for their own usage screens. It refreshes every 2 minutes and writes a snapshot to `~/Library/Application Support/AILimits/snapshot.json`, which the sandboxed widget extension reads.

Credentials never leave your Mac except to the provider they belong to, and nothing is stored by this app.

These endpoints are undocumented and may change. If they do, the app shows an error instead of wrong numbers.

## Project layout

- `App/`: menu bar app, popover, floating window, notch, data fetching
- `Widget/`: WidgetKit extension
- `Shared/`: models, snapshot store, ring, dial and bar components
- `project.yml`: XcodeGen spec
