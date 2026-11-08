#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 ducttape3

[ "$BOOTMODE" = true ] || abort "Install from the root manager while Android is running."
[ "$ARCH" = arm64 ] || abort "This build supports arm64-v8a only."

case "$(getprop ro.product.manufacturer)" in
  samsung|Samsung|SAMSUNG) ;;
  *)
    # A OneOS guest (ColorOS, LineageOS, Pixel) does not report itself as Samsung.
    [ -f /data/local/tmp/oneos/.oneos_stage ] ||
      abort "This module targets Samsung's DMC service."
    ;;
esac

ui_print "backdownload by ducttape3"
ui_print "Requires Zygisk API v4 support (ReZygisk, Magisk, or Zygisk Next)."
ui_print "Soft Reboot (if jailbroken), or either Reboot Android"
ui_print "OneOS: if a guest switch dies part way, the next boot goes to Download Mode."

set_perm "$MODPATH/zygisk/arm64-v8a.so" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/status.sh" 0 0 0755
set_perm "$MODPATH/update-status.sh" 0 0 0755

if [ -x /data/adb/ksu/bin/ksud ]; then
  KSU_MODULE=dmc_at_zygisk
  export KSU_MODULE
  /data/adb/ksu/bin/ksud module config set --temp override.description 'Unlocks Download Mode on Samsung devices and returns there whenever a OneOS guest switch fails. Tap Action to check the policy.' >/dev/null 2>&1
fi
