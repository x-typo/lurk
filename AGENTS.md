# Lurk Agent Notes

## Project

- Work in the active checkout resolved with `git rev-parse --show-toplevel`; preserve pre-existing changes and other tasks' work.
- Personal SwiftUI Reddit client for iOS 18+. Project and scheme: `Lurk.xcodeproj` / `Lurk`; production bundle: `com.xtypo.Lurk`.
- Use Apple frameworks only. Preserve the existing `@Observable` stores, actor-based `RedditClient`, and dark native UI. Follow the detailed code conventions in [.github/copilot-instructions.md](.github/copilot-instructions.md).
- Source is in `Lurk/`; Swift Testing coverage is in `Tests/`, in the `LurkTests` target. Use existing injected loaders and `URLProtocol` session fixtures for deterministic, network-free tests.

## Local Testing and Generated State

- Use Xcode's Device Hub as the default UI for simulator and physical-phone inspection, interaction, and debugging. Report access failures before switching to another UI. Continue using Xcode command-line tools for builds, tests, installation, inventory, and cleanup.
- Run the smallest checks that establish changed behavior and all required coverage. Documentation-only edits need read-back and diff checks, not Xcode builds or simulator runs. A build does not replace required runtime or UI checks.
- Reuse one compatible, available simulator selected by exact UDID. Pass `-parallel-testing-enabled NO` for local `xcodebuild test`; the shared scheme permits parallel testing, so do not rely on its default. Additional destinations or workers need a concrete coverage reason and bounded ownership. Do not routinely create or reset devices.
- Reuse stable, checkout-local paths under ignored `DerivedData/`, separated by configuration and destination type, such as `DerivedData/SimulatorDebug` and `DerivedData/DeviceRelease`. Avoid new build directories or clean builds on every retry unless isolation or a diagnosed build issue requires them.
- One task owns each simulator and build directory at a time. Coordinate before builds or tests; do not share mutable state between concurrent tasks.
- Before testing, record the selected simulator's initial state and exact temporary resources created for the run. App presence, device name, directory age, or a before/after difference alone does not prove ownership.
- After owning processes exit, clean disposable run-owned devices and build outputs through supported tools, then verify. Restore a simulator booted solely for the run when no other task has taken ownership. Reconcile unfinished cleanup after interruption.
- Keep decisive test evidence and useful failure state outside the repository under `/Users/x-typo/qa/lurk/`. Report retained artifacts and why they remain.
- Pre-existing cleanup is separate work. Never bulk-delete `XCTestDevices`, regular simulators, runtimes, shared caches, credentials, app data, or other tasks' artifacts. Report exact leftovers when ownership or safe removal is uncertain.
- Preserve `.env.local` and Xcode user preferences during generated-output cleanup. Never run blanket `git clean -fdx`; ignored files include local configuration.
- Keep unit-test, fixture UI, live Reddit, and physical-phone evidence distinct. DEBUG fixture apps and injected clients do not establish real cookie-backed account behavior. Documentation and unit-test tasks do not authorize signing changes, phone installation, or live votes, comments, subscriptions, saved/hidden-post changes, or Inbox read-state writes.

## Physical-Phone Work

- `scripts/deploy-phone.sh` builds, installs, and launches the app; run it only within authorized phone work. It loads ignored `.env.local`; do not print that file or credentials.
- Override its shared temporary build-path default with a stable path in the active checkout, matching the intended configuration. For an authorized Release installation from the repository root:

  ```bash
  CONFIGURATION=Release DERIVED_DATA_PATH="$PWD/DerivedData/DeviceRelease" scripts/deploy-phone.sh
  ```

- Install only the exact intended build, verify the selected device and installed app independently, and preserve existing app data. Do not invoke `--restart-coredevice` as routine setup.
