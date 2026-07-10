# HA Volume Control

A macOS menu bar app that controls the volume of a [Home Assistant](https://www.home-assistant.io) media player entity. Hardware volume keys are optionally intercepted system-wide and redirected to the selected HA media player.

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15 or later (for building)
- A running Home Assistant instance reachable from the Mac

## Building

### Xcode

1. Open `HA Volume Control.xcodeproj`.
2. Select the **HA Volume Control** scheme and your Mac as the destination.
3. Press **⌘R** to build and run, or **⌘B** to build only.

### Command line

```bash
xcodebuild build \
  -project "HA Volume Control.xcodeproj" \
  -scheme "HA Volume Control" \
  -configuration Debug \
  -destination "platform=macOS" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO
```

For a release archive:

```bash
xcodebuild archive \
  -project "HA Volume Control.xcodeproj" \
  -scheme "HA Volume Control" \
  -configuration Release \
  -destination "platform=macOS" \
  -archivePath build/HA\ Volume\ Control.xcarchive
```

## Configuration

Open **Settings** from the menu bar popup (click the speaker icon → Settings).

### Connection

Enter the base URL of your Home Assistant instance, e.g.:

```
http://homeassistant.local:8123
https://my.ha-instance.com
```

### Authentication

Paste a **long-lived access token** from Home Assistant:

1. In HA, go to your profile page (click your name in the sidebar).
2. Scroll to **Long-lived access tokens** and click **Create token**.
3. Copy the token and paste it into the **Token** field in Settings.

The token is stored in the macOS Keychain, not in plain text.

### Selecting a media player

Click any entry in the menu bar popup list to make it the active entity. The volume slider controls that entity. The selected entity persists across restarts.

### Volume key interception

Enable **Intercept hardware volume keys** to redirect the keyboard volume up/down/mute keys to the selected HA media player instead of controlling Mac system volume.

This requires **Accessibility** permission. Click **Grant Accessibility Permission** to open the system prompt. If the toggle remains disabled after granting permission, quit and relaunch the app.

### Filtering by label

If your HA media player entities have [labels](https://www.home-assistant.io/docs/organizing/labels/) assigned, a **Labels** section appears in Settings. Select one or more labels to show only entities that carry at least one of them. Selecting none shows all entities.

Label names are fetched directly from HA and displayed as you named them.

### Filtering by integration

An **Integrations** section appears once HA reports the integration platform for each entity. Toggle integrations off to hide all entities provided by that integration (e.g. hide all Google Cast devices while keeping Apple TV).

## AI Disclosure

This project was developed with the assistance of [Claude Code](https://claude.ai/code) (Anthropic). AI assistance was used in the development of source code and assets.
