#!/system/bin/sh
# SPDX-License-Identifier: GPL-3.0-only
# Copyright (c) 2026 ducttape3

BD_STATUS_FILE=/data/system/backdownload.status
BD_REQUEST_FILE=/data/system/backdownload.request
BD_PROC=/proc
BD_DEFAULT='Unlocks Download Mode on Samsung devices and returns there whenever a OneOS guest switch fails. Tap Action to check the policy.'

# OneOS switches to a guest in place, so a switch that dies part way leaves One
# UI in an undefined state and Magisk never sees a clean boot again. The stage
# belongs to OneOS. return_inplace.done ("<boot_id> <epoch>") is written after
# "One UI restored in place", and persist_session.active is removed only once
# One UI's persist props are back. The OneOS switch scripts write both files.
BD_ONEOS_STAGE=/data/local/tmp/oneos
BD_ONEOS_LOG=/data/adb/backdownload.log

bd_snapshot() {
  BD_STATE=unavailable
  [ -f "$BD_STATUS_FILE" ] && [ ! -L "$BD_STATUS_FILE" ] || return 1
  IFS=' ' read -r BD_MAGIC BD_BOOT BD_PID BD_TOKEN BD_TIME BD_STATE BD_LOCK BD_MAINT BD_AT BD_EXTRA < "$BD_STATUS_FILE" || return 1
  [ "$BD_MAGIC" = BD1 ] && [ -z "$BD_EXTRA" ] || return 1
  [ -f "$BD_REQUEST_FILE" ] && [ ! -L "$BD_REQUEST_FILE" ] || return 1
  BD_EXPECTED=$(cat "$BD_REQUEST_FILE" 2>/dev/null)
  [ -n "$BD_EXPECTED" ] || BD_EXPECTED=0
  [ "$BD_TOKEN" = "$BD_EXPECTED" ] || return 1
  [ "$BD_BOOT" = "$(cat "$BD_PROC/sys/kernel/random/boot_id" 2>/dev/null)" ] || return 1
  case "$BD_PID:$BD_TIME" in *[!0-9:]*|:*|*:) return 1 ;; esac
  [ "$BD_PID" -gt 1 ] || return 1
  [ "$(cat "$BD_PROC/$BD_PID/comm" 2>/dev/null)" = system_server ] || return 1
  IFS=' ' read -r BD_NOW BD_IDLE < "$BD_PROC/uptime" || return 1
  BD_NOW=${BD_NOW%%.*}
  case "$BD_NOW" in ''|*[!0-9]*) return 1 ;; esac
  [ "$BD_TIME" -le "$BD_NOW" ] && [ "$((BD_NOW - BD_TIME))" -le 60 ] || return 1
  case "$BD_STATE" in
    valid)
      case "$BD_LOCK:$BD_MAINT:$BD_AT" in
        [01]:[01]:[01]) return 0 ;;
      esac
      ;;
    starting|read_failed|unsupported)
      [ "$BD_LOCK:$BD_MAINT:$BD_AT" = '-1:-1:-1' ] && return 0
      ;;
  esac
  return 1
}

# OneOS bookkeeping. One log line per boot, beside the module, so it survives a
# reboot into a broken One UI.
bd_oneos_log() {
  BD_ONEOS_STAMP=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)
  BD_ONEOS_SIZE=$(stat -c %s "$BD_ONEOS_LOG" 2>/dev/null)
  case "$BD_ONEOS_SIZE" in ''|*[!0-9]*) BD_ONEOS_SIZE=0 ;; esac
  if [ "$BD_ONEOS_SIZE" -gt 65536 ]; then
    tail -n 200 "$BD_ONEOS_LOG" > "$BD_ONEOS_LOG.tmp" 2>/dev/null &&
      chmod 0644 "$BD_ONEOS_LOG.tmp" 2>/dev/null &&
      mv -f "$BD_ONEOS_LOG.tmp" "$BD_ONEOS_LOG" 2>/dev/null
  fi
  printf '%s %s\n' "$BD_ONEOS_STAMP" "$*" >> "$BD_ONEOS_LOG" 2>/dev/null
  rm -f "$BD_ONEOS_LOG.tmp" 2>/dev/null
  log -t backdownload "$*" 2>/dev/null
  return 0
}

# Sets BD_ONEOS to absent, healthy, active or interrupted, with the evidence
# (BD_ONEOS_SESSION_BOOT, BD_ONEOS_START, BD_ONEOS_RETURNED). It changes
# nothing on disk; post-fs-data.sh acts on it.
bd_oneos_probe() {
  BD_ONEOS=absent
  BD_ONEOS_ACTIVE=0
  BD_ONEOS_SESSION_BOOT=
  BD_ONEOS_START=0
  BD_ONEOS_RETURNED=0

  # A live session file is reason enough to look: it is written by a switch and
  # removed only after One UI's persist props are back, so a stage whose marker
  # went missing mid-session still tells us the phone never returned.
  if [ -f "$BD_ONEOS_STAGE/.oneos_stage" ] && [ ! -L "$BD_ONEOS_STAGE/.oneos_stage" ]; then
    :
  elif [ ! -f "$BD_ONEOS_STAGE/persist_session.active" ] ||
       [ -L "$BD_ONEOS_STAGE/persist_session.active" ]; then
    return 0
  fi

  if [ -f "$BD_ONEOS_STAGE/persist_session.active" ] && [ ! -L "$BD_ONEOS_STAGE/persist_session.active" ]; then
    BD_ONEOS_ACTIVE=1
    BD_ONEOS_SESSION_BOOT=$(sed -n 's/^boot_id=//p' "$BD_ONEOS_STAGE/persist_session.active" 2>/dev/null | head -n 1)
    BD_ONEOS_TMP=$(sed -n 's/^epoch=\([0-9][0-9]*\)$/\1/p' "$BD_ONEOS_STAGE/persist_session.active" 2>/dev/null | head -n 1)
    [ -n "$BD_ONEOS_TMP" ] && BD_ONEOS_START=$BD_ONEOS_TMP
  fi

  # "=== OneOS app launch <id> <mode> <date> epoch <epoch> ..." starts a session.
  BD_ONEOS_TMP=$(sed -n 's/.*=== OneOS app launch .* epoch \([0-9][0-9]*\) .*/\1/p' "$BD_ONEOS_STAGE/takeover_app.log" 2>/dev/null | tail -n 1)
  if [ -n "$BD_ONEOS_TMP" ] && [ "$BD_ONEOS_TMP" -gt "$BD_ONEOS_START" ]; then BD_ONEOS_START=$BD_ONEOS_TMP; fi

  # return_inplace.done: one line, "<boot_id> <epoch>", written on a clean return.
  BD_ONEOS_TMP=$(sed -n '1s/^[^ ]* \([0-9][0-9]*\).*$/\1/p' "$BD_ONEOS_STAGE/return_inplace.done" 2>/dev/null)
  [ -n "$BD_ONEOS_TMP" ] && BD_ONEOS_RETURNED=$BD_ONEOS_TMP

  BD_ONEOS_CUR=$(cat "$BD_PROC/sys/kernel/random/boot_id" 2>/dev/null)
  if [ "$BD_ONEOS_ACTIVE" = 1 ]; then
    # The file is removed only after One UI's persist props were restored.
    if [ -n "$BD_ONEOS_SESSION_BOOT" ] && [ "$BD_ONEOS_SESSION_BOOT" = "$BD_ONEOS_CUR" ]; then
      BD_ONEOS=active
    else
      BD_ONEOS=interrupted
    fi
  elif [ "$BD_ONEOS_START" -gt "$BD_ONEOS_RETURNED" ]; then
    BD_ONEOS=interrupted
  else
    BD_ONEOS=healthy
  fi
  return 0
}

bd_oneos_text() {
  case "$BD_ONEOS" in
    healthy) echo 'oneos: no session' ;;
    active) echo 'oneos: session active' ;;
    interrupted) echo 'oneos: interrupted, goes to Download Mode on next boot' ;;
    *) echo 'oneos: no stage' ;;
  esac
}

bd_description() {
  bd_description_policy
  bd_oneos_probe
  [ "$BD_ONEOS" = absent ] || BD_DESCRIPTION="$BD_DESCRIPTION | $(bd_oneos_text)"
}

bd_description_policy() {
  BD_DESCRIPTION='⚠️ Policy not verified. Tap Action to check.'
  if [ -e "$MODDIR/disable" ] || [ -e "$MODDIR/remove" ]; then
    BD_DESCRIPTION='Module disabled. Policy not verified.'
    return
  fi
  bd_snapshot || return
  case "$BD_STATE" in
    valid)
      if [ "$BD_AT" = 1 ]; then
        BD_DESCRIPTION='✅ Last policy check: AT authorization enabled.'
      elif [ "$BD_LOCK" = 0 ] || [ "$BD_MAINT" = 1 ]; then
        BD_DESCRIPTION='⚠️ Last policy check: AT patch inactive; Download Mode allowed.'
      else
        BD_DESCRIPTION='❌ Last policy check: Download Mode blocked; AT patch inactive.'
      fi
      ;;
    starting) BD_DESCRIPTION='Checking policy after Android startup.' ;;
    read_failed) BD_DESCRIPTION='⚠️ Policy read failed. Tap Action to retry.' ;;
    unsupported) BD_DESCRIPTION='⚠️ Unsupported DMC policy. Patch not verified.' ;;
  esac
}
