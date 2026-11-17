# Changelog

## v0.4 — 2026-11-17

- Support older 1784605054 and newer 1790133188 firmware in one package.
- Add ASI, its framework/feature configuration, Private Compute Services and Android Auto
  to B; offer intelligence and Auto separately in A/C, defaulting to keep.
- Preserve Home/Recents and existing selections; recognize v0.3 settings.
- Keep cancellation/failure from clearing active settings or pending legacy cleanup.
- Cover reviewed paths before an OTA adds them; inspect updated copies every boot.
- Back up selected apps and check actual APK signers, verified key rotation, split-aware
  contents and version before cleanup; keep microG and unrecognized replacements.
- Retain failed work for retry and backups for manual restoration.

- Use KernelSU's custom installer protocol with the configuration script kept
  separate from the reserved legacy install.sh filename.

## v0.3

Trim Google telemetry or prepare for microG on the Foxxd A67L Gen 2.
