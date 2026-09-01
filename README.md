# Magic Mouse Zone

A small macOS menu-bar app that limits Magic Mouse scrolling to a region you draw — typically a strip under your middle finger — so your ring finger and pinky can rest without accidentally scrolling.

Apple’s System Settings on macOS Sequoia cannot host a third-party Mouse pane. This app is the stand-in: a settings window in the same grouped style, plus a menu-bar extra that stays running.

## Build and run

Requires Command Line Tools (or Xcode) on macOS 14+.

```bash
make run
```

Or install a copy in `~/Applications`:

```bash
make install
```

If Gatekeeper blocks it:

```bash
xattr -cr ~/Applications/"Magic Mouse Zone.app"
```

Then right-click the app and choose Open.

## First launch

1. Open **Scroll Zone Settings…** from the mouse icon in the menu bar (the window also opens at launch).
2. Click **Open Accessibility Settings** and enable **Magic Mouse Zone** in System Settings → Privacy & Security → Accessibility.
3. Click **Quit & Reopen**. macOS often keeps the old “denied” answer until the app is fully restarted.
4. Rest your fingers on the mouse. Green dots are inside the zone; orange dots are ignored.
5. Drag the blue rectangle (or use Width / Position) so it covers only your middle finger.
6. Optionally turn on **Open at login**.

If the warning stays after you turned the switch on, System Settings is still tied to an old copy of the app. Remove **Magic Mouse Zone** from the Accessibility list, click **Reveal in Finder**, add that exact copy, then quit and reopen. Local builds are signed with a stable self-signed identity so you should only have to do this once.

Clicks still work on the whole mouse. Only scroll events are filtered. Two-finger swipes are ignored by default; a resting finger outside the zone still lets you scroll with one finger.

## If the mouse is not detected

With the Magic Mouse connected, run:

```bash
make probe
```

That prints Multitouch family IDs. Magic Mouse is usually family `112` or `113`.

## Quit

Menu bar icon → **Quit Magic Mouse Zone**.
