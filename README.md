# backdownload v1.0.8 (OneOS support)

A build of the `backdownload` Magisk/KernelSU module (`id=dmc_at_zygisk`, arm64)
that also sends the phone to Download Mode when a OneOS guest switch leaves it
unbootable.

The original v1.0.6 module is ducthoe's. It sits unchanged in the first commit
of this repository (see `AUTHORS`); this tree carries the OneOS changes on top.

## What v1.0.6 does

It never reboots anything. `zygisk/arm64-v8a.so` hooks VaultKeeper in
`system_server` and writes the DMC policy to `/data/system/backdownload.status`.
`action.sh` reads that record and prints whether Download Mode is blocked by the
screen lock, Maintenance Mode or AT authorization.

## What v1.0.8 adds

| File | Change |
| --- | --- |
| `status.sh` | OneOS probe (`bd_oneos_probe`, `bd_oneos_text`, `bd_oneos_log`), and an `oneos: …` line on the module description. |
| `post-fs-data.sh` | One decision per boot; a switch that never returned means `reboot download`. |
| `action.sh` | Prints the `oneos: …` line before the policy report. |
| `update-status.sh` | New `oneos` argument: prints only the OneOS line. |
| `module.prop` | `version=v1.0.8`, `versionCode=10008`, description mentions OneOS. |
| `customize.sh` | Install allowed when a OneOS stage is present; updated text. |
| `zygisk/arm64-v8a.so` | Unchanged, byte-identical (sha256 `1773dc4e…85dfc7`). |

## Detection

OneOS switches in place: it stops One UI's framework and boots a guest in a
container, so a guest that dies never reaches a clean `sys.boot_completed` and
the phone can loop with no usable UI. OneOS's own stage files say what happened:

* `/data/local/tmp/oneos/.oneos_stage`: the stage exists (JSON marker, `created`
  epoch).
* `/data/local/tmp/oneos/persist_session.active`: written when a session starts
  and removed only after One UI's persist props were restored.
* `/data/local/tmp/oneos/return_inplace.done`: one line,
  `<boot_id> <epoch>`, written on every clean in-place return ("One UI restored
  in place").
* `/data/local/tmp/oneos/takeover_app.log`: `=== OneOS app launch … epoch N …`
  marks a session start.

`post-fs-data.sh` evaluates this at every boot:

```
stage marker exists, or persist_session.active still exists
and (
      persist_session.active with boot_id != this boot's boot_id   -> interrupted
   or persist_session.active without a boot_id                     -> interrupted
   or (no persist_session.active and last launch epoch > last return epoch) -> interrupted
)
```

Any other boot with a stage is healthy: either no session was ever started, or a
return happened after the last launch. A stage with a live session in this boot
reads `session active`, and the module leaves it alone.

`interrupted` is acted on at once, with no counter and no retry limit. The
module logs the evidence, runs exactly:

```
/system/bin/reboot download
```

and that is the end of the boot. A clean return or no stage at all writes one
line and continues booting. Nothing has to be writable for the reboot to
happen, so a broken `/data/adb` cannot hold it back.

Every boot writes one line to `/data/adb/backdownload.log`, for example:

```
2026-11-08 15:49:27 oneos: interrupted (session boot 6f1c…, started 1794091968, last return 1794091700), going to Download Mode
```

The same line is offered to `log -t backdownload`, so it reaches `logcat` too.

## Install

Install the zip from Magisk, KernelSU or APatch while Android is running, then
reboot. The requirements are the same as v1.0.6: arm64 and a working Zygisk
(ReZygisk, Magisk or Zygisk Next).

## Build

`./build.sh` zips the contents of `src/` into
`backdownload-v<version>-arm64.zip`, with `module.prop` at the archive root. The
version is read from `src/module.prop`.

## Disable

* Whole module: the root manager's own disable switch (the module's `disable`
  file), as before.
* Only the OneOS path: create an empty file
  `/data/adb/modules/dmc_at_zygisk/oneos-disable`. The boot check then logs the
  state and does nothing.

There is no threshold to tune. A failed switch goes to Download Mode on the next
boot.

## Credits

@ducthoe wrote the original module. Telegram: [@ducttape33](https://t.me/ducttape33).

## Accountability

```cpp
#include <std_disclaimer.h>

/*
* I am not responsible for bricked devices, dead SD cards,
* thermonuclear war, or you getting fired because the alarm app failed. Please
* do some research if you have any concerns about doing this to your device
* YOU are choosing to make these modifications, and if
* you point the finger at me for messing up your device, I will laugh at you.
*
* I am also not responsible for you getting in trouble for using any of the
* features in this module, including but not limited to hiding root, patching
* system properties, or flashing files to your device.
*/
```

## License

GPL-3.0-only. The full text is in `LICENSE`, and every script in `src/` carries
the matching SPDX header.

## State files

Read:

```
/data/local/tmp/oneos/.oneos_stage
/data/local/tmp/oneos/persist_session.active
/data/local/tmp/oneos/return_inplace.done
/data/local/tmp/oneos/takeover_app.log
/proc/sys/kernel/random/boot_id
```

Written:

```
/data/adb/backdownload.log                 one line per boot
```

Nothing under `/data/local/tmp/oneos` is ever modified.
