# MARK: Functions

# --- Logging ---
# levels: DEBUG < INFO < WARN < ERROR < REQ
declare -A levels=( [DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3 [REQ]=4 )
log_location="/private/var/log/Uninstallomator.log"

printlog() { # $1 message, $2 level (default INFO)
  local msg="$1" lvl="${2:-INFO}" ts
  ts=$(date +%F\ %T)

  # de-dup consecutive lines
  if [[ "$msg" == "${previous_log_message:-}" ]]; then
    ((logrepeat=logrepeat+1))
    return
  fi
  if (( logrepeat > 1 )); then
    echo "$ts : ${lvl} : $label : Last Log repeated ${logrepeat} times" | tee -a "$log_location"
    logrepeat=0
  fi
  previous_log_message="$msg"

  # honor LOGGING threshold
  if (( ${levels[$lvl]:-1} >= ${levels[${LOGGING:-INFO}]:-1} )); then
    if [[ $EUID -eq 0 ]]; then
      echo "$ts : ${lvl} : $label : $msg" | tee -a "$log_location"
    else
      echo "$ts : ${lvl} : $label : $msg"
    fi
  fi
}

# --- Cleanup and exit ---
cleanupAndExit() { # $1 code, $2 message, $3 level (default INFO)
  local code="${1:-0}" msg="${2:-}" lvl="${3:-INFO}"
  [[ -n "$msg" ]] && printlog "$msg" "$lvl"
  printlog "################## End Uninstallomator, exit code $code" REQ
  exit "$code"
}

# --- Current user / run as user ---
get_current_user() { scutil <<<"show State:/Users/ConsoleUser" | awk '/Name :/ {print $3}'; }
runAsUser() {
  local cu; cu=$(get_current_user)
  [[ -z "$cu" || "$cu" == "loginwindow" ]] && return 0
  local uid; uid=$(id -u "$cu")
  launchctl asuser "$uid" sudo -u "$cu" "$@"
}

# --- Notifications (optional) ---
displaynotification(){ # $1 msg, $2 title
  local message="${1:-Message}" title="${2:-Notification}"
  local manageaction="/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action"
  local hubcli="/usr/local/bin/hubcli" swiftdialog="/usr/local/bin/dialog"
  if [[ -x "$swiftdialog" && "${NOTIFY_DIALOG:-0}" -eq 1 ]]; then
    "$swiftdialog" --notification --title "$title" --message "$message"
  elif [[ -x "$manageaction" ]]; then
    "$manageaction" -message "$message" -title "$title" &
  elif [[ -x "$hubcli" ]]; then
    "$hubcli" notify -t "$title" -i "$message" -c "Dismiss"
  else
    runAsUser osascript -e "display notification \"$message\" with title \"$title\""
  fi
}

# --- Blocking processes (simple kill policy; extend later if needed) ---
checkRunningProcesses() {
  # DEBUG==1 → skip enforcement
  [[ "${DEBUG:-0}" -eq 1 ]] && { printlog "DEBUG mode: skipping blocking process checks" DEBUG; return; }
  local counted=0 x
  for _ in {1..4}; do
    for x in "${blockingProcesses[@]}"; do
      [[ "$x" == "NONE" || -z "$x" ]] && continue
      if pgrep -xq "$x"; then
        printlog "Found blocking process: $x" INFO
        pkill "$x" || true
        sleep 5
        ((counted++))
      fi
    done
  done
  if (( counted > 0 )) && pgrep -fq "${bundle_id:-__nope__}"; then
    cleanupAndExit 11 "Could not quit all processes for $app_name; aborting." ERROR
  fi
  printlog "No blocking processes remain" INFO
}

# --- Launchd unload + file removal + receipts ---
unload_launch(){
  local p="$1" failed=0
  [[ -f "$p" ]] || return 0

  if [[ "${DEBUG:-0}" -eq 1 ]]; then
    printlog "[DEBUG] would unload launch item: $p" DEBUG
    printlog "[DEBUG] would remove launch item: $p" DEBUG
    return 0
  fi

  if [[ "$p" == *"/LaunchAgents/"* ]]; then
    local cu uid
    cu=$(get_current_user)
    if [[ -z "$cu" || "$cu" == "loginwindow" ]]; then
      printlog "Failed to unload launch item without a logged-in user: $p" ERROR
      failed=1
    else
      uid=$(id -u "$cu" 2>/dev/null)
      if [[ -z "$uid" ]]; then
        printlog "Failed to resolve user ID for launch item: $p" ERROR
        failed=1
      elif ! runAsUser launchctl bootout "gui/$uid" "$p"; then
        printlog "Failed to unload launch item: $p" ERROR
        failed=1
      fi
    fi
  else
    if ! launchctl bootout system "$p"; then
      printlog "Failed to unload launch item: $p" ERROR
      failed=1
    fi
  fi

  printlog "Removing launch item: $p" INFO
  if ! rm -f -- "$p"; then
    printlog "Failed to remove launch item: $p" ERROR
    failed=1
  elif [[ -e "$p" || -L "$p" ]]; then
    printlog "Launch item still present after removal: $p" ERROR
    failed=1
  fi

  return "$failed"
}

# --- File removal (with confirmation and debug support) ---
confirm_rm(){
  local t="$1"
  [[ -e "$t" || -L "$t" ]] || return 0

  if [[ "${DEBUG:-0}" -eq 1 ]]; then
    printlog "[DEBUG] would remove: $t" DEBUG
    return 0
  fi

  printlog "Removing: $t" INFO
  if ! rm -rf -- "$t"; then
    printlog "Failed to remove: $t" ERROR
    return 1
  elif [[ -e "$t" || -L "$t" ]]; then
    printlog "Target still present after removal: $t" ERROR
    return 1
  fi

  return 0
}

# --- Receipts ---
forget_pkg(){
  local id="$1"
  pkgutil --pkgs | grep -qx "$id" || return 0

  if [[ "${DEBUG:-0}" -eq 1 ]]; then
    printlog "[DEBUG] would pkgutil --forget '$id'" DEBUG
    return 0
  fi

  if ! pkgutil --forget "$id"; then
    printlog "Failed to forget package receipt: $id" ERROR
    return 1
  elif pkgutil --pkgs | grep -qx "$id"; then
    printlog "Package receipt still present after forgetting: $id" ERROR
    return 1
  fi

  return 0
}

# --- Userscope helpers ---
list_user_homes(){
  dscl . -readall /Users NFSHomeDirectory UniqueID 2>/dev/null \
  | awk '/^NFSHomeDirectory:/{h=$2} /^UniqueID:/{uid=$2; if (uid>=500) print h}' \
  | sort -u | grep -E '^/Users/[^/]+' | grep -vE '^/Users/(Shared|Guest)$'
}
expand_user_path(){
  local tpl="$1" home="$2"
  if [[ "$tpl" == "%USER_HOME%"* ]]; then
    printf '%s' "${home}${tpl#"%USER_HOME%"}"
  else
    printf '%s' "$tpl"
  fi
}

# --- Uninstall engine (runs after label case sets arrays) ---
do_uninstall(){
  # sanity for arrays
  (( ${#app_paths[@]} == 0 ))   && cleanupAndExit 1 "Label missing app_paths" ERROR
  [[ -z "${bundle_id:-}" ]]     && cleanupAndExit 1 "Label missing bundle_id" ERROR
  [[ -z "${app_name:-}" ]]      && app_name="$bundle_id"

  # optional notification at start
  [[ "${NOTIFY:-silent}" != "silent" && "${NOTIFY:-silent}" != "none" && "${NOTIFY:-silent}" != "error" ]] \
    && displaynotification "Removing ${app_name}…" "Uninstallomator"

  # Kill/quit processes (basic)
  blockingProcesses=("${blockingProcesses[@]:-}" "${app_name}")
  checkRunningProcesses

  local cleanup_failed=0 p

  # unload launch items
  for p in "${agents[@]:-}";  do [[ -n "$p" ]] && { unload_launch "$p" || cleanup_failed=1; }; done
  for p in "${daemons[@]:-}"; do [[ -n "$p" ]] && { unload_launch "$p" || cleanup_failed=1; }; done

  # remove app bundles and system files
  found=0
  for p in "${app_paths[@]}"; do [[ -n "$p" && -e "$p" ]] && found=1; done
  (( found == 0 )) && printlog "$app_name not found in defined app paths; continuing cleanup" INFO
  for p in "${app_paths[@]}"; do [[ -n "$p" ]] && { confirm_rm "$p" || cleanup_failed=1; }; done
  for p in "${files[@]:-}";   do [[ -n "$p" ]] && { confirm_rm "$p" || cleanup_failed=1; }; done

  # per-user files
  if [[ "${USERSCOPE:-0}" -eq 1 ]]; then
    local uh tgt
    while IFS= read -r uh; do
      for p in "${user_files[@]:-}"; do
        [[ -z "$p" ]] && continue
        tgt="$(expand_user_path "$p" "$uh")"
        [[ -n "$tgt" ]] && { confirm_rm "$tgt" || cleanup_failed=1; }
      done
    done < <(list_user_homes)
  else
    local cu_name; cu_name="$(get_current_user)"
   if [[ "$cu_name" == "loginwindow" || -z "$cu_name" ]]; then
     printlog "No user session; skipping per-user file removals (USERSCOPE=0)" INFO
   else
     local cu_home="/Users/$cu_name" tgt
    for p in "${user_files[@]:-}"; do
      [[ -z "$p" ]] && continue
      if [[ "$p" == %USER_HOME%* ]]; then
        tgt="$(expand_user_path "$p" "$cu_home")"
      elif [[ "$p" == ~/* ]]; then
        tgt="${p/#~\//$cu_home/}"
      else
        tgt="$p"
      fi
      [[ -n "$tgt" ]] && { confirm_rm "$tgt" || cleanup_failed=1; }
    done
   fi
  fi

  # receipts
  local id
  for id in "${pkgs[@]:-}"; do [[ -n "$id" ]] && { forget_pkg "$id" || cleanup_failed=1; }; done

  # success check: app bundles are gone and every attempted cleanup succeeded
  local any_left=0
  if [[ "${DEBUG:-0}" -ne 1 ]]; then
    for p in "${app_paths[@]}"; do [[ -e "$p" ]] && any_left=1; done
  fi

  if (( any_left == 0 && cleanup_failed == 0 )); then
    [[ "${NOTIFY:-silent}" == "success" || "${NOTIFY:-silent}" == "all" ]] \
      && displaynotification "${app_name} removed." "Uninstall complete"
    printlog "Completed uninstall of ${app_name}" REQ
    return 0
  else
    [[ "$(get_current_user)" != "loginwindow" && "${NOTIFY:-silent}" == "all" ]] \
      && displaynotification "Failed to remove ${app_name}" "Uninstall failed"
    (( any_left != 0 )) && printlog "Some app bundles still present for ${app_name}" ERROR
    (( cleanup_failed != 0 )) && printlog "One or more cleanup operations failed for ${app_name}" ERROR
    return 1
  fi
}
