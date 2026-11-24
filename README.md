# Curtains

Curtains covers the displays on your Mac while your signed-in session keeps running. Use your usual remote connection to send tasks to Claude or Codex, then enter your curtain password when you return to your desk.

[Download the Mac preview](https://curtains.work/Curtains.dmg) · [Setup guide with screenshots](https://curtains.work/setup/)

## Using the app

1. Open Curtains and enter a password of at least eight characters. Confirm it to draw the curtain immediately across your connected displays.
2. Keep the Mac awake. Before leaving, try a task through your existing remote agent connection. Tools that rely on the foreground screen can see the curtain.
3. Type your curtain password and press Return or click the arrow. Curtains exits and reveals your desktop. Open it again to start a new session.

The password verifier lives in memory for one session. Your Mac stays signed in, and quitting the app or a crash exposes the desktop. Use the macOS lock screen when you need operating-system access control.

## Build from source

On a Mac with macOS 14 or later and the Xcode Command Line Tools installed, run:

```sh
git clone https://github.com/davidharket/curtains.git
cd curtains
./build.sh
open ./Skjermgardin.app
```

The script uses the macOS SDK and Swift compiler, creates the app icon, and ad-hoc signs a bundle for your Mac’s architecture. The downloadable preview is packaged as Curtains.app for Apple silicon. Apple has not notarized this build.

## Agent activity

The app reads local Claude and Codex session metadata to show activity along the bottom of the curtain. With the default installation, it uses locally available agent icons or names. Custom character artwork can be loaded from the user’s Application Support directory.
