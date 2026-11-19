# Privacy

Sol collects nothing.

- No ads, no analytics, no crash reporters, no third-party SDKs.
- No accounts and no network access: the app never connects to the internet.
- No tracking: `NSPrivacyTracking` is false and the privacy manifest lists no collected data.
- Free, with no in-app purchases.

The only data the app keeps is the game in progress and the draw-1/draw-3 setting, in `UserDefaults` on your
device. Deleting the app deletes them.

On the App Store this is declared as **Data Not Collected**.

## Keeping it that way

Pull requests must not add advertising, analytics, tracking, network calls, third-party SDKs, or purchases.
Reviewers check `App/PrivacyInfo.xcprivacy` and the dependency list (`Packages/`, `project.yml`) on every change.
