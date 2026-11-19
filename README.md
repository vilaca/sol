# Sol

A free, open-source solitaire collection for iPhone and iPad. No ads, no tracking, no in-app purchases, no network access.
See [PRIVACY.md](PRIVACY.md).

- Games: Klondike (draw 1 or draw 3), FreeCell, Yukon and Scorpion, picked from the New menu. Each game keeps its own game in progress.
- Unlimited undo, hints, tap a card to send it where it fits, or drag it.
- Finishes the game for you once nothing is left to find out, then celebrates with confetti (a plain fade with Reduce Motion).
- Timer and move count; statistics per game and rule options (games, wins, streaks, best time, fewest moves), kept on the device.
- Haptics, which can be turned off in Settings, like the timer.
- Playable with VoiceOver: every card says where it is, and the Actions rotor offers each legal move.
- In English, Portuguese (Portugal and Brazil), Spanish, French and German.
- The games in progress are saved on the device; the last one played comes back on the next launch.
- Runs on **iOS 16 and later**: iPhone 8, X, SE (2nd gen) and every newer iPhone in portrait, and iPad in any orientation.

## Layout

| Path | What |
|---|---|
| `Packages/SolitaireCore` | Game rules as a plain Swift package (no UI); tests run on the Mac in a second |
| `App/` | SwiftUI app: board layout, cards, gestures, saving, statistics, VoiceOver; translations in `Localizable.xcstrings` |
| `App/Games/` | What each game adds to the app (name, board, rule settings); [docs/adding-a-game.md](docs/adding-a-game.md) is the checklist for a new one |
| `AppTests/` | App unit tests (model, undo, saving, timer, statistics, drop targets, VoiceOver text) |
| `AppUITests/` | UI tests driving the app on a simulator or iPhone, with a fixed deal |
| `project.yml` | XcodeGen spec; `Sol.xcodeproj` is generated, not committed |
| `Art/court/` | Source SVGs of the classic court cards (CC0); `scripts/make-court-art.py` renders them |
| `Config/*.xcconfig` | Build configurations and signing |
| `scripts/`, `Makefile` | Simulator, device, test, icon and translation tooling |
| `fastlane/` | Dev IPA, TestFlight and App Store uploads |
| `.github/workflows/` | CI tests on every push; nightly tests on other iOS versions, devices and Xcodes; release uploads on `v*` tags |

## Getting started

Needs a Mac with Xcode 16 or later and [Homebrew](https://brew.sh).

```sh
make bootstrap   # installs xcodegen, xcbeautify, ios-deploy, fastlane; generates Sol.xcodeproj
make sim         # build and run on an iPhone 13 simulator
```

Run `make` with no arguments to list every target.

## Builds

| Build | Configuration | Bundle id | Home-screen name | How |
|---|---|---|---|---|
| Dev | Debug | `<APP_BUNDLE_ID>.dev` | Sol Dev | `make sim`, `make device`, `make dev-ipa` |
| Test release | Release | `<APP_BUNDLE_ID>` | Sol | `make beta` → TestFlight |
| Store release | Release | `<APP_BUNDLE_ID>` | Sol | `make release` → App Store Connect |

Dev and release builds have different bundle ids, so both can be installed on the same iPhone.

## Translations

`scripts/translations.py` is the source of the translations (English, Portuguese for Portugal and Brazil,
Spanish, French, German). Add strings there, then run it: `python3 scripts/translations.py` rewrites
`App/Localizable.xcstrings`. Don't edit the catalog in Xcode; the next run overwrites it.

## Testing

```sh
make test-core     # game rules, on the Mac
make test-app      # app unit + UI tests, iPhone 13 simulator, newest iOS
make test-oldest   # same on an iPhone 8 simulator with iOS 16, the oldest supported
make test-device   # same on a connected iPhone
```

Any simulator: `SIM_DEVICE="iPhone SE (2nd generation)" SIM_RUNTIME=16 scripts/test-app.sh`. A simulator for each
device and iOS pair is created on first use. Older iOS runtimes are installed from **Xcode → Settings → Components**.

UI tests launch the app with `-seed 42 -reset`: the same deal each time and no saved game. You can pass the same
arguments yourself, e.g. `scripts/simulator.sh -seed 42`; add `-game freecell` to start on another game.

Test results, including screenshots and code coverage, are saved in `.build/TestResults.xcresult`.

### On GitHub Actions

| Workflow | When | Runner | Xcode | iOS | Device |
|---|---|---|---|---|---|
| CI | every push and pull request | macOS 15 | runner default | newest installed | iPhone 13 |
| Nightly | 03:00 UTC, or **Run workflow** | macOS 15 | 16.4 | 18.5 | iPhone SE (3rd generation) |
| | | macOS 15 | 16.4 | 18.6 | iPhone 16 Pro Max |
| | | macOS 15 | 26.0.1 | 26.0 | iPad (A16) |
| | | macOS 26 | 26.6 | 26.5 | iPhone 17e |

CI also runs the game-rule tests on the Mac. The nightly uses only simulators and Xcodes already installed on [GitHub's runner images](https://github.com/actions/runner-images/tree/main/images/macos).
None has iOS 16, the oldest supported version, or iOS 17, so test those locally with `make test-oldest`. When an image drops one
of these versions, its nightly job fails at "Select Xcode" or when creating the simulator; update the matrix in
`.github/workflows/nightly.yml` and this table.

## Running on your iPhone

1. `cp Config/Signing.local.xcconfig.example Config/Signing.local.xcconfig` (`make bootstrap` does this) and set
   `DEVELOPMENT_TEAM` (your Apple developer team id) and `APP_BUNDLE_ID` (any reverse-DNS id you own).
   A free Apple ID works for your own phone. Its builds expire after 7 days.
2. Connect the iPhone by cable, unlock it and tap **Trust**.
3. On iOS 16 or later: **Settings → Privacy & Security → Developer Mode → On**.
4. `make device`. On the first install, trust the developer profile on the phone under
   **Settings → General → VPN & Device Management**.

iPhones on iOS 17 or later install through `xcrun devicectl`. Older ones (iOS 16) install through
`ios-deploy`. Once the phone has been paired by cable, Xcode can also install over Wi-Fi.

To give a build to testers without TestFlight, register their iPhones in your developer account, then run
`make dev-ipa`. That makes `dist/Sol-Dev.ipa`, which you install through Xcode → Devices and Simulators or
Apple Configurator. This needs a paid developer account.

## Releasing

Needs a paid Apple Developer Program membership and an app record in App Store Connect for `APP_BUNDLE_ID`.

- **Locally:** `make beta` builds the next build number and uploads it to TestFlight. `make release` uploads to
  App Store Connect, where you submit the build for review.
- **CI:** push a tag such as `v0.1.0` to upload to TestFlight, or run the *Release* workflow by hand and pick
  `beta` or `release`. Set these repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`
  (the text of an App Store Connect API key with the App Manager role), `DEVELOPMENT_TEAM`, `APP_BUNDLE_ID`.

Set the version in `project.yml` (`MARKETING_VERSION`). Build numbers are counted up automatically from TestFlight.

When you fill in the App Store privacy questions, answer **Data Not Collected**. Set the price to **Free**.

## Contributing

Issues and pull requests are welcome. Run `make test` before you open a pull request. Changes must keep the
privacy promise in [PRIVACY.md](PRIVACY.md).

## License

Code: [MIT](LICENSE). Court card figures: English-pattern cards by Dmitry Fomin, Wikimedia Commons,
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/); see [Art/court/README.md](Art/court/README.md).
