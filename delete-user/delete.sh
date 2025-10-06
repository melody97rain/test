#!/bin/bash
# remove-expired-users-clean.sh
# Remove expired accounts (based on /etc/shadow field 8) with a safe removal routine:
# - remove user's crontab
# - remove mail spool (/var/mail or /var/spool/mail)
# - remove home dir ONLY if under /home
# - then remove account (without -r) using userdel/deluser
#
# Usage: run as root (can be cron'ed). Logs: /usr/local/bin/alluser and /usr/local/bin/deleteduser
# NOTE: Skips system accounts (UID < 1000) and root.

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin:$PATH"

LOG_DELETED="/usr/local/bin/deleteduser"   # log when deleted
LOG_ALL="/usr/local/bin/alluser"           # log all accounts with expiry
LOG_SYS="/var/log/expired_users.log"
hariini="$(date +%d-%m-%Y)"
todaysecs="$(date +%s)"

# ensure running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root." >&2
  exit 1
fi

# safe remove function: remove crontab, mail, home (only under /home), then remove account
safe_remove_user() {
  local u="$1"
  local passwd_entry home_dir uid mail1 mail2 rc

  passwd_entry="$(getent passwd -- "$u")" || return 1
  uid="$(printf '%s' "$passwd_entry" | cut -d: -f3)"
  home_dir="$(printf '%s' "$passwd_entry" | cut -d: -f6)"
  mail1="/var/mail/$u"
  mail2="/var/spool/mail/$u"

  echo "Preparing to remove user: $u (UID=$uid)" >> "$LOG_SYS"

  # remove crontab if present
  if crontab -u "$u" -l >/dev/null 2>&1; then
    crontab -r -u "$u" 2>/dev/null && echo "Removed crontab for $u" >> "$LOG_SYS" || echo "Failed to remove crontab for $u" >> "$LOG_SYS"
  else
    echo "No crontab for $u" >> "$LOG_SYS"
  fi

  # remove mail spool if exists
  if [ -f "$mail1" ]; then
    rm -f -- "$mail1" && echo "Removed mail spool $mail1" >> "$LOG_SYS" || echo "Failed to remove $mail1" >> "$LOG_SYS"
  elif [ -f "$mail2" ]; then
    rm -f -- "$mail2" && echo "Removed mail spool $mail2" >> "$LOG_SYS" || echo "Failed to remove $mail2" >> "$LOG_SYS"
  else
    echo "No mail spool for $u" >> "$LOG_SYS"
  fi

  # remove home dir only if under /home (e.g. /home/username or /home/username/)
  if [ -n "$home_dir" ] && [ -d "$home_dir" ]; then
    case "$home_dir" in
      /home/*)
        # extra safety: don't remove '/' or '/root' etc.
        if [ "$home_dir" = "/" ] || [ "$home_dir" = "/root" ]; then
          echo "Refusing to remove suspicious home_dir: $home_dir" >> "$LOG_SYS"
        else
          echo "Removing home directory: $home_dir" >> "$LOG_SYS"
          rm -rf -- "$home_dir" && echo "Removed $home_dir" >> "$LOG_SYS" || echo "Failed to remove $home_dir" >> "$LOG_SYS"
        fi
        ;;
      *)
        echo "Skipping removal of home directory $home_dir (not under /home)." >> "$LOG_SYS"
        ;;
    esac
  else
    echo "No home directory to remove for $u" >> "$LOG_SYS"
  fi

  # finally remove the account (without -r because we handled files)
  if command -v userdel >/dev/null 2>&1; then
    userdel -- "$u"
    rc=$?
  elif command -v deluser >/dev/null 2>&1; then
    deluser -- "$u"
    rc=$?
  elif [ -x /usr/sbin/userdel ]; then
    /usr/sbin/userdel -- "$u"
    rc=$?
  else
    rc=127
  fi

  if [ $rc -eq 0 ]; then
    echo "Account $u removed (exit 0)" >> "$LOG_SYS"
    return 0
  elif [ $rc -eq 127 ]; then
    echo "No userdel/deluser found. Cannot remove $u" >> "$LOG_SYS"
    return 127
  else
    echo "userdel/deluser failed for $u (exit $rc)" >> "$LOG_SYS"
    return $rc
  fi
}

# prepare temp file
tmpfile="$(mktemp /tmp/expirelist.XXXXXX)" || { echo "Failed to mktemp"; exit 1; }
trap 'rm -f "$tmpfile"' EXIT

# collect username:expiryfield (skip if expiry empty)
awk -F: '($8 != "" && $1 !~ /^$/){print $1 ":" $8}' /etc/shadow > "$tmpfile"

totalaccounts=$(wc -l < "$tmpfile" | tr -d ' ')
echo "Thank you for removing the EXPIRED USERS"
echo "--------------------------------------"
printf "Found %s accounts with expiry field set\n\n" "$totalaccounts"

touch "$LOG_DELETED" "$LOG_ALL" "$LOG_SYS"

while IFS=: read -r username userexpdays; do
  # sanity checks
  if [ -z "$username" ]; then
    continue
  fi

  # ensure passwd entry exists
  if ! getent passwd "$username" >/dev/null 2>&1; then
    printf "Skipping %s (no passwd entry)\n" "$username"
    echo "Skipping $username: no passwd entry" >> "$LOG_SYS"
    continue
  fi

  # protect system accounts (UID < 1000)
  uid=$(getent passwd "$username" | cut -d: -f3)
  if [ -z "$uid" ] || [ "$uid" -lt 1000 ]; then
    printf "Skipping system account %s (UID=%s)\n" "$username" "$uid"
    echo "Skipping system account $username (UID=$uid)" >> "$LOG_SYS"
    continue
  fi

  # ensure userexpdays numeric
  if ! [[ "$userexpdays" =~ ^[0-9]+$ ]] ; then
    printf "Skipping %s (expiry not numeric: %s)\n" "$username" "$userexpdays"
    echo "Skipping $username: expiry not numeric ($userexpdays)" >> "$LOG_SYS"
    continue
  fi

  # compute expiry time
  userexpiresecs=$(( userexpdays * 86400 ))
  tglexp="$(date -d "@$userexpiresecs" '+%d %b %Y' 2>/dev/null || date -d "1970-01-01 +${userexpdays} days" '+%d %b %Y' 2>/dev/null)"

  # log all users with expiry
  echo "Expired- User : $username Expire at : $tglexp" >> "$LOG_ALL"

  # if expired (expiry timestamp < now) -> remove
  if [ "$userexpiresecs" -lt "$todaysecs" ]; then
    echo "Removing expired user: $username (expired $tglexp)" | tee -a "$LOG_DELETED" "$LOG_SYS"
    if safe_remove_user "$username"; then
      echo "Expired- Username : $username are expired at: $tglexp and removed : $hariini" | tee -a "$LOG_DELETED" "$LOG_SYS"
      echo "Username $username that are expired at $tglexp removed from the VPS $hariini"
    else
      rc=$?
      if [ "$rc" -eq 127 ]; then
        echo "ERROR: No userdel/deluser found. Cannot remove $username." | tee -a "$LOG_SYS"
      else
        echo "ERROR: Failed to remove $username (exit $rc)." | tee -a "$LOG_SYS"
      fi
    fi
  fi

done < "$tmpfile"

echo
echo "--------------------------------------"
echo "Script successfully run"
exit 0
