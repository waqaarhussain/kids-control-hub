# Kids Control Hub

A parent dashboard plus native iPhone/iPad helper built around Apple's **FamilyControls** and **ManagedSettings** frameworks.

## What is already built

- Slick mobile-first web/PWA dashboard.
- Nevaeh and Inaara device records.
- Individual app/group allow/block state.
- **Block All / Allow All**.
- 6-digit helper pairing codes.
- Per-device helper tokens.
- Helper heartbeat and online status.
- Native app/group registration using Apple's `FamilyActivityPicker` token data.
- Desired-state API consumed by the child helper.
- ManagedSettings shield application on the iPad.
- Silent APNs wake-up path, ready once Apple credentials exist.
- GitHub Actions unsigned compile check on the current `xcode-27` runner.
- Manual TestFlight workflow scaffold for when signing/provisioning is ready.

## Important architecture choice

The first real-device build uses the **picker on the child's iPad** to register a live control such as Disney+ once. After registration, the web dashboard can toggle that control remotely without touching the child's iPad again.

Why start this way? Apple's documentation says a parent-side `FamilyActivityPicker` can surface authorized child apps, but there are current developer reports of child app lists not always appearing correctly on the guardian device. We should prove shielding and remote state first, then add the parent-side picker as a second path.

## Real-device proof we want

1. Install Kids Control on a child iPad.
2. Request `.child` Family Controls authorization and approve it as parent/guardian.
3. Pair the helper using a 6-digit code from the web dashboard.
4. On the iPad, choose Disney+ using Apple's picker and name the dashboard control `Disney+`.
5. On the web dashboard, switch Disney+ to **Blocked**.
6. The VPS sends a silent APNs wake-up if APNs is configured. The helper fetches desired state and applies `ManagedSettingsStore.shield.applications`.
7. Disney+ should remain in place and show Apple's shield when opened.

There is also a **Sync & apply now** button in the helper so we can test the full mechanism even before APNs is configured.

## Block All

The helper uses Apple's supported category policy:

```swift
store.shield.applicationCategories = .all()
store.shield.webDomainCategories = .all()
```

This shields essentially all third-party app categories, but Apple intentionally exempts some system apps. It is not equivalent to locking the entire iPad.

## Current Apple requirements

- `com.apple.developer.family-controls` capability on the app.
- Child device authorization via `AuthorizationCenter.shared.requestAuthorization(for: .child)`.
- For TestFlight/App Store distribution, Apple must approve the Family Controls distribution entitlement for the App ID.
- Push Notifications capability / APNs credentials are required for near-real-time remote wakes.

## GitHub CI

`.github/workflows/ios-build.yml` runs an **unsigned compile check** using GitHub's `xcode-27` runner. This can run before the paid developer account and entitlement approval are ready.

The TestFlight workflow is present but will not succeed until the following secrets and Apple assets exist:

- `APPLE_TEAM_ID`
- `APPLE_DISTRIBUTION_P12_BASE64`
- `APPLE_DISTRIBUTION_P12_PASSWORD`
- `APPLE_PROVISIONING_PROFILE_BASE64`
- `CI_KEYCHAIN_PASSWORD`
- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_PRIVATE_KEY_BASE64`

The provisioning profile must include Family Controls and Push Notifications for `com.kidscontrol.hub`.

## Xcode project generation

The repo uses XcodeGen so the `.xcodeproj` does not need to be hand-maintained:

```bash
cd ios
brew install xcodegen
xcodegen generate
open KidsControl.xcodeproj
```

## VPS update

From a checked-out repository:

```bash
sudo ./scripts/deploy-vps.sh
```

After the project is placed on GitHub, the VPS workflow becomes:

```bash
./scripts/update-live
```

The deployment script preserves `/opt/kids-control/data/kids-control.db` and `/etc/kids-control.env`.

## APNs configuration later

Once the developer account is active, add an APNs `.p8` key and configure `/etc/kids-control.env`:

```text
PUBLIC_BASE_URL=https://kids.example.com
APPLE_TEAM_ID=YOUR_TEAM_ID
APPLE_KEY_ID=YOUR_KEY_ID
APPLE_BUNDLE_ID=com.kidscontrol.hub
APNS_KEY_PATH=/etc/kids-control/AuthKey.p8
APNS_ENV=production
```

The `.p8` file must be readable by the service and should never be committed to Git.

## Temporary HTTP allowance

The prototype iOS `Info.plist` currently enables `NSAllowsArbitraryLoads` because the test VPS is being used over plain HTTP. Before App Store submission this should be removed and the backend should use HTTPS.

## Next work after the first successful Disney+ shield

- Parent-mode native app with Apple's picker on Waqaar/Adiba's phones.
- Custom Apple shield appearance and parent-request action.
- Local bedtime/homework scheduling with DeviceActivity.
- StoreKit purchase layer.
- Proper multi-family accounts and tenant separation.
- App Store privacy disclosures and production hardening.
