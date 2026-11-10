# Loop on your phone

Your Claude Code sessions, from anywhere, over your own Tailscale network. The
app works the same sessions the desktop does: open one as a conversation, send
text or a photo, answer the questions Claude asks, switch the account or the
model, give a team a goal.

It is not Claude's own Remote Control switch. That is a separate thing, with its
own switch on each session.

## Pairing

On the PC: open Loop, then **Your phone**, and turn it on. It shows an address,
a port and a pairing code. Type those three into the app once.

Use the Tailscale address (it starts with `100.`) and the app reaches your PC
from anywhere. The LAN address works only on the same network.

## Getting the app onto a phone

### Android

Build it yourself:

    cd app
    flutter build apk --release

The file lands at `build/app/outputs/flutter-apk/app-release.apk`. Copy it to
the phone and open it; Android asks once whether to allow installing it.

Or let GitHub build it: the **Phone app** workflow under Actions, then download
`loop-android` from the artifacts.

### iPhone

An iPhone app can only be compiled and signed on macOS. That is Apple's rule and
there is no way round it from Windows. So the build happens on GitHub's Mac
machines, and the signing happens on your PC with your own Apple ID:

1. On GitHub, open **Actions → Phone app → Run workflow**. When it finishes,
   download `loop-iphone`, which holds `Loop.ipa`. It is unsigned, which is why
   no Apple account was needed to build it.
2. On your PC, install [Sideloadly](https://sideloadly.io). Plug the iPhone in,
   drop `Loop.ipa` on it, sign in with your ordinary Apple ID (a free one is
   fine) and press Start. The first time, the iPhone asks you to trust the
   developer: Settings → General → VPN & Device Management.

A free Apple ID signs an app for **seven days**, and allows three sideloaded
apps at once; after that you run Sideloadly again. A paid Apple Developer
account ($99 a year) raises that to a year, and lets you install over the air
through TestFlight instead of a cable.

What is different on an iPhone: iOS stops an app that is not on screen within a
minute or so, so Loop cannot tell you a session needs you while the app is
closed. Everything else works the same.

## Building it here

    cd app
    flutter pub get
    flutter run           # a phone or an emulator plugged in
    flutter analyze       # no warnings expected

`lib/bridge.dart` is the only place that talks to the PC; `lib/chat.dart` is the
conversation; `lib/lists.dart` the lists; `lib/alerts.dart` the notifications.
