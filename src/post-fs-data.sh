#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 ducttape3

MODDIR=${0%/*}
rm -f "$MODDIR/.status-description"
sh "$MODDIR/update-status.sh" reset >/dev/null 2>&1

# OneOS switches into a guest without rebooting. If the switch leaves One UI in
# an undefined state, the phone loops without a clean boot and nothing in the
# module would report it. Any boot that starts in that state goes to Download
# Mode, the same screen the DMC policy unlocks.
. "$MODDIR/status.sh"
bd_oneos_probe

if [ -e "$MODDIR/disable" ] || [ -e "$MODDIR/remove" ] || [ -e "$MODDIR/oneos-disable" ]; then
  bd_oneos_log "oneos: $BD_ONEOS (handling disabled, no action)"
  exit 0
fi

if [ "$BD_ONEOS" = interrupted ]; then
  BD_ONEOS_WHY="started $BD_ONEOS_START, last return $BD_ONEOS_RETURNED"
  [ -n "$BD_ONEOS_SESSION_BOOT" ] && BD_ONEOS_WHY="session boot $BD_ONEOS_SESSION_BOOT, $BD_ONEOS_WHY"
  bd_oneos_log "oneos: interrupted ($BD_ONEOS_WHY), going to Download Mode"
  sync
  /system/bin/reboot download 2>/dev/null || reboot download 2>/dev/null ||
    bd_oneos_log "oneos: 'reboot download' failed"
else
  bd_oneos_log "oneos: $BD_ONEOS, no action"
fi
