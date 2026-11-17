# Degoogler

**[Download degoogler-a67lg2.zip](https://github.com/CyberspaceVii/degoogler-a67lg2/releases/download/v0.4/degoogler-a67lg2.zip)**


*CyberspaceVII. For the Foxxd A67L Gen 2 with KernelSU Next.*

This module lets you choose how much Google to keep on the phone. It is **systemless**: it hides
Google's preinstalled apps with the module and never writes to `/system`. Disable the module and
reboot, and the hidden apps come back.

## Firmware and upgrades

Supports older firmware **1784605054** and **1790133188** with one package.
Reviewed removal paths are covered even when absent on the older firmware, so
an OTA cannot introduce ASI or the Android Auto stub outside a selected removal
group. Home and Recents are preserved on both firmware versions.

On an update, **Up or a 10-second timeout keeps previous choices**; Down opens
the menu below. v0.3 choices are recognized too. Mode B now also removes
intelligence and Android Auto. Existing microG replacements are kept using
actual APK signing identities, rather than package names alone. Cancelling
or failing an installation leaves the active choices and old cleanup marker
untouched. New choices belong to the staged module until it is activated.

## Choosing during install

When you install the zip in the KSU Next app, a menu appears:

| Key | Action |
|---|---|
| **Volume Down** | move to the next choice |
| **Volume Up** | select the shown choice |
| no key for 30 s | **Cancel** (nothing is installed) |

The choices are **A**, **B**, **C** and **Cancel**. Choice B asks you to confirm with Volume Up
a second time. Your choice only takes effect at the **next reboot**. If you change your mind before
then, remove the module in KSU Next and nothing will have changed. (App backups are made
during installation and retained. See below.)

Every choice (A, B and C) removes three Google telemetry stubs:

- **Google Location History** (the Timeline stub)
- **Google Feedback** (crash and feedback uploads)
- **Go telemetry** (a mainline telemetry marker)

These are the same three trim targets on both reviewed firmware versions.

---

## A. Keep Google, trim telemetry, Morphe with root mount

**What it does:** removes the three telemetry stubs. Google Play services (GMS), the Play Store and
other Google apps stay unless you choose the optional removals below.

**Impact:**
- Google sign-in, Play Store, push notifications, Find My Device and Google
  backup remain available. Play Integrity still depends on the device and apps.
- GMS and the Play Store remain running. No RAM or battery saving is promised.

**What you should do afterwards:**
1. Turn off Google's own tracking in Settings → Google:
   - **Ads** → *Delete advertising ID*.
   - **Usage & diagnostics** → off.
   - **Location** → *Google Location History / Timeline* → off.
2. For ad-free YouTube / YouTube Music, install **[Morphe Manager](https://github.com/MorpheApp/morphe-manager)**.
   When it asks, pick **Root Mount install**. The patched app is mounted over the real one, keeps its
   real package name and signs in with the real Google account. You don't need microG.
   Patches: [morphe-patches](https://github.com/MorpheApp/morphe-patches).

**Caveats:**
- Morphe patches target **specific app versions**. In the Play Store, open each patched app → ⋮ →
  untick **Enable auto update**. If you don't, a Play update replaces the app and the patch goes away
  until you patch again.
- This is the least de-Googled choice. Google still sees the device through GMS.

---

## Optional intelligence and Android Auto removal in A/C

After choosing A or C, you can separately remove:

- **Android System Intelligence and Private Compute Services**: removes their
  stock apps and ASI's feature declaration and framework overlay together.
  Smart text selection, predictions, captions, attention, autofill suggestions,
  on-device speech and related features may be lost. Availability varies by device.
- **Android Auto**: removes the preloaded car-integration stub and any recognized
  updated copy. Car integration is lost.

Up removes the shown group; Down or timeout keeps it. Both default to **keep**
on a fresh A/C install. Private Compute Services was already present on older
firmware; ASI and Android Auto are new on 1790133188. These choices leave the
launcher and its Recents integration in place. The search bar may still appear;
this module does not replace or modify the launcher.

## B. Replace Google Play services with microG

**What it does:**
- Removes the three telemetry stubs.
- Hides **Google Play services**, **Google Services Framework**, the **Play Store**, **Partner
  Setup**, **Device Health Services (Turbo)**, **ConfigUpdater**, **One Time Initializer**, **Google
  Restore**, **Google Assistant Go** and **Google Search Go** as part of the
  Google-services replacement profile.
- Also removes **Android System Intelligence**, **Private Compute Services** and
  the **Android Auto stub**, with ASI's framework overlay and feature declaration.
- Backs up recognized selected apps before installation completes. After boot,
  removes surviving updated copies only after signer, backup, content and version
  checks. Checks repeat on subsequent boots, including after an OTA. Failures
  remain pending and are logged; replacements such as microG are kept.


**Impact (what you lose):**
- **Google sign-in, the Play Store, Google backup and restore, Find My Device, Assistant, Google
  Search and the home-screen search bar's Google results.** Your Google account is removed from the
  phone.
- **Play Integrity.** With microG, banking, payment and Wallet apps that check integrity will
  refuse to run. Integrity modules (Play Integrity Fix and the like) only matter with real Play
  services.
- **Device Health Services (Turbo):** Adaptive Battery predictions.
- **Intelligence features and Android Auto:** see the optional-removal descriptions above.
- Apps that *require* Play services and aren't supported by microG may fail. microG covers most push
  notifications, Google sign-in, Maps API and location. It does not cover everything.

**What changes:** the selected Google processes and services are removed. RAM,
battery and network impact depend on your apps and replacements; savings on
the new firmware have not been measured.

**What you must do after the reboot (in this order):**
1. **Signature spoofing.** Stock Android 16 doesn't allow microG to pose as Google, so add it with
   an Xposed framework (a Zygisk module such as Vector / LSPosed, which needs Zygisk, e.g. ReZygisk):
   install **[FakeGApps](https://github.com/whew-inc/FakeGApps)**, enable it in the framework manager, scope it to
   **System Framework**, then reboot. Background: [microG wiki: Signature Spoofing](https://github.com/microg/GmsCore/wiki/Signature-Spoofing).
2. **Install microG.** Get **[microG Services (GmsCore)](https://github.com/microg/GmsCore/releases)**
   and **microG Companion** (the Play Store stand-in) from the
   [microG releases](https://github.com/microg/GmsCore/releases). You can also get them through
   F-Droid by adding the repo `https://microg.org/fdroid/repo`. Project page:
   [github.com/microg/GmsCore](https://github.com/microg/GmsCore), docs in the
   [wiki](https://github.com/microg/GmsCore/wiki).
3. Open **microG Settings → Self-Check** and fix everything it flags. Grant every permission it asks
   for, and confirm that *signature spoofing* is ticked.
4. In microG Settings, turn on **Google device registration** and **Cloud Messaging** if you want
   push notifications. Sign in to a Google account there only if you want one.
5. **Location:** without Google, network location needs a provider. In microG's location settings,
   pick a network location service such as **[BeaconDB](https://beacondb.net)**.
6. **Apps:** install **[Aurora Store](https://auroraoss.com)**
   ([source](https://gitlab.com/AuroraOSS/AuroraStore)) for Play Store apps (anonymous login works)
   and **[F-Droid](https://f-droid.org)** for open-source apps.
7. **Patched YouTube / Music:** **[Morphe Manager](https://github.com/MorpheApp/morphe-manager)**
   works with real microG. Use a standard (non-root) install, or a root mount if you prefer.

**Caveats:**
- Install microG after the first reboot, once stock Google services are absent.
  Cleanup checks the actual APK signer and verified rotation lineage. A repeated
  module update keeps microG instead of uninstalling it by package name.
- This replaces the Google services stack; it does **not** remove every Google
  app or every Google-provided system component.
- microG uses the same package name as Google Play services but a different signature. You can never
  have both installed at once.
- Apps you installed from the Play Store stay installed, but nothing updates them until you use
  Aurora Store.
- Google's own apps that stay (YouTube, Gmail, Maps, Drive and so on) run through microG, and some of
  their features may break.

**To go back to Google:**
1. Uninstall microG Services and microG Companion first (same package names as Google's, different
   signatures).
2. Disable or remove this module in KSU Next, then reboot. The *factory* versions of Play services
   and the Play Store come back, with empty data.
3. Open the Play Store, sign in again and let it update Google's apps. Your account data syncs back
   from Google. Local Play-services data does not.
4. New backups are under
   `/data/adb/cyberspacevii/degoogler-a67lg2/backups/<package>/<fingerprint>/`.
   Copy all APKs from a complete private backup to your computer using root
   access, then run `adb install-multiple -r <local-backup-directory>/*.apk`. Existing v0.3 `backup-*`
   directories are retained too. Data archives are for manual restoration with
   correct ownership and SELinux labels; nothing is restored over microG automatically.

---

## C. Keep Google, trim telemetry, Morphe without root (MicroG-RE)

**What it does on the phone:** the same trim targets and optional removal groups as **A**.
Google services stay. The difference is how you run patched apps.

**Impact:** the same as A. On top of that, Morphe apps run on their **own** copy of microG next to
real Play services. Two Play-services stacks on 3 GB of RAM is the worst choice for performance per
dollar. It's here because it doesn't depend on root mounts or on blocking Play updates.

**What you should do afterwards:**
1. The same Google privacy switches as A (delete the ad ID, usage & diagnostics off, Location
   History off).
2. Install **[MicroG-RE](https://github.com/MorpheApp/MicroG-RE)**. It's Morphe's microG fork, with
   its own package name, so it runs next to Google Play services without signature spoofing.
3. Install **[Morphe Manager](https://github.com/MorpheApp/morphe-manager)** and pick a **Standard
   install**. The patched apps get new package names and sign in through MicroG-RE.

**Caveats:**
- Patched apps are separate from the stock YouTube / Music apps. Disable the stock ones if you don't
  want both.
- This doesn't de-Google anything. It only makes the patched apps independent of root and of Play
  updates.

---

## Which one?

- **Do you need banking, payment or Wallet apps, or anything that checks Play Integrity?** Pick
  **A**.
- **Want to replace Google's services stack with microG?** Pick **B**.
- **C** only if you want patched apps that survive without root.

## Undo, any choice

In KSU Next, toggle the module **off** (or remove it) and reboot. Everything it hid comes back. For
choice B, follow "To go back to Google" above.

## Backups and cleanup status

Selected stock apps are backed up during installation because hiding them may
make Android discard their data at boot. Recognized updated copies are backed
up before cleanup. Backups include numbered base/split APKs, their source paths,
and available owner-user app data. These are live file copies, not guaranteed
transaction-consistent app snapshots. Backup failure aborts installation or keeps
a cleanup pending; it never authorizes deletion. Backups survive module removal.
Additional Android users' data is outside the backup scope; updated-copy removal
applies device-wide.

`/data/adb/cyberspacevii/degoogler-a67lg2/cleanup.log` records cleanup;
`cleanup-pending` records failures for the next boot. A stock APK still visible
indicates a mount problem. Unknown signing identities are kept for manual review.
Stock signing certificates from both reviewed firmware versions are pinned;
Android's verified APK key-rotation history allows legitimate Play updates.

## Build and validation

Build the module from the checked-in source with:

```sh
python build.py --output /tmp/degoogler-a67lg2.zip
python tests/test_module.py
```

The builder uses `ANDROID_SDK_ROOT` (default `/opt/android-sdk`), with
`ANDROID_JAR`, `D8`, and `JAVAC` overrides. See [VALIDATION.md](VALIDATION.md).

## Links

- microG: <https://github.com/microg/GmsCore> · [releases](https://github.com/microg/GmsCore/releases)
  · [wiki](https://github.com/microg/GmsCore/wiki) · F-Droid repo `https://microg.org/fdroid/repo`
- FakeGApps (signature spoofing via an Xposed framework): <https://github.com/whew-inc/FakeGApps>
- Morphe: [Manager](https://github.com/MorpheApp/morphe-manager) ·
  [Patches](https://github.com/MorpheApp/morphe-patches) ·
  [MicroG-RE](https://github.com/MorpheApp/MicroG-RE)
- Aurora Store: <https://auroraoss.com> · [source](https://gitlab.com/AuroraOSS/AuroraStore)
- F-Droid: <https://f-droid.org>
- BeaconDB (network location for microG): <https://beacondb.net>
