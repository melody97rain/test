#!/bin/bash
# del-ssh-clean.sh
# Safely remove a user: remove home (only if under /home), remove mail spool, remove crontab, then remove account
# Usage: run as root and enter username when prompted

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/sbin:/usr/bin:/bin:$PATH"

# ensure running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Run this script as root." >&2
  exit 1
fi

read -p "Username SSH to Delete : " Pengguna
if [ -z "$Pengguna" ]; then
  echo "No username provided." >&2
  exit 1
fi

# validate user exists
passwd_entry="$(getent passwd -- "$Pengguna")"
if [ -z "$passwd_entry" ]; then
  echo "Failure: User $Pengguna Not Exist."
  exit 1
fi

# get uid and home dir
uid="$(printf '%s' "$passwd_entry" | cut -d: -f3)"
home_dir="$(printf '%s' "$passwd_entry" | cut -d: -f6)"

# protect system accounts
if [ -z "$uid" ] || [ "$uid" -lt 1000 ]; then
  echo "Refuse to delete system account $Pengguna (UID=$uid)."
  exit 1
fi

# safety: ensure home_dir is not empty and not dangerous
# only auto-delete home if it is under /home or /home/USERNAME
delete_home=false
if [ -n "$home_dir" ] && [ -d "$home_dir" ]; then
  case "$home_dir" in
    /home/*|/home)
      delete_home=true
      ;;
    *)
      delete_home=false
      ;;
  esac
fi

# paths for mail spool (two common locations)
mail1="/var/mail/$Pengguna"
mail2="/var/spool/mail/$Pengguna"

# function to attempt account removal using available tools
remove_account() {
  local u="$1"
  if command -v userdel >/dev/null 2>&1; then
    userdel -- "$u"
    return $?
  elif command -v deluser >/dev/null 2>&1; then
    deluser -- "$u"
    return $?
  elif [ -x /usr/sbin/userdel ]; then
    /usr/sbin/userdel -- "$u"
    return $?
  else
    return 127
  fi
}

echo "Preparing to remove user: $Pengguna (UID=$uid)"
# remove crontab for user (if any)
if crontab -u "$Pengguna" -l >/dev/null 2>&1; then
  crontab -r -u "$Pengguna" 2>/dev/null && echo "Removed crontab for $Pengguna" || echo "No crontab or failed to remove crontab for $Pengguna"
else
  echo "No crontab for $Pengguna"
fi

# remove mail spool if exists
if [ -f "$mail1" ]; then
  rm -f -- "$mail1" && echo "Removed mail spool $mail1"
elif [ -f "$mail2" ]; then
  rm -f -- "$mail2" && echo "Removed mail spool $mail2"
else
  echo "No mail spool found for $Pengguna"
fi

# remove home dir if allowed
if [ "$delete_home" = true ]; then
  # double safety: ensure home_dir is not / or /root
  if [ "$home_dir" = "/" ] || [ "$home_dir" = "/root" ]; then
    echo "Refusing to remove suspicious home_dir: $home_dir"
  else
    echo "Removing home directory: $home_dir"
    rm -rf -- "$home_dir" && echo "Removed $home_dir" || echo "Failed to remove $home_dir"
  fi
else
  if [ -n "$home_dir" ]; then
    echo "Skipping removal of home directory $home_dir (not under /home)."
  else
    echo "User had no home directory set."
  fi
fi

# finally remove the user account (without -r because we handled files)
remove_account "$Pengguna"
rc=$?
if [ $rc -eq 0 ]; then
  echo "User $Pengguna was removed."
elif [ $rc -eq 127 ]; then
  echo "ERROR: No userdel/deluser found. Install 'adduser' (Debian/Ubuntu) or 'shadow-utils' (RHEL) and try again."
else
  echo "Failed to remove user $Pengguna (exit $rc)."
fi

exit $rc
