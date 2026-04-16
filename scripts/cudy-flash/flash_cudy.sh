#!/usr/bin/env bash

set -euo pipefail

ROUTER_MODEL="wr3000p"
SIGNED_DIR="signed"
OPENWRT_DIR="openwrt"
SIGNED_FW=""
OPENWRT_FW=""

STOCK_IP="192.168.10.1"
OPENWRT_IP="192.168.1.1"

STOCK_USER="admin"
STOCK_PASS="admin"
OPENWRT_PASS=""
STOCK_NEW_PASS="TempPass123!"
STOCK_TIMEZONE="Europe/Moscow"

WAIT_TIMEOUT="300"
WAIT_INTERVAL="5"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"

usage() {
  cat <<'EOF'
Usage: ./flash_wr3000p.sh [options]

Options:
  --model NAME            Router model / image basename (default: wr3000p)
  --signed-fw PATH        Signed factory image path relative to script dir
  --openwrt-fw PATH       OpenWrt sysupgrade image path relative to script dir
  --stock-user USER       Stock Cudy username (default: admin)
  --stock-pass PASS       Stock Cudy password (default: admin)
  --stock-new-pass PASS   Password to set if stock firmware shows first-boot wizard
  --openwrt-pass PASS     OpenWrt root password after first boot (default: empty)
  --stock-ip IP           Stock firmware IP (default: 192.168.10.1)
  --openwrt-ip IP         OpenWrt IP after first boot (default: 192.168.1.1)
  --stock-timezone TZ     Timezone sent to the stock wizard/login flow (default: Europe/Moscow)
  --timeout SEC           Wait timeout per reboot stage (default: 300)
  --help                  Show this help

Notes:
  - Requires: curl, ssh, scp, ping
  - The script uses the signed factory image first, then sysupgrades to OpenWrt.
  - By default, image paths are derived from --model as signed/<model>.bin and
    openwrt/<model>.bin.
  - On first boot, OpenWrt is assumed to allow SSH as root with no password unless
    --openwrt-pass is supplied.
EOF
}

set_firmware_paths() {
  if [[ -z "$SIGNED_FW" ]]; then
    SIGNED_FW="${SIGNED_DIR}/${ROUTER_MODEL}.bin"
  fi

  if [[ -z "$OPENWRT_FW" ]]; then
    OPENWRT_FW="${OPENWRT_DIR}/${ROUTER_MODEL}.bin"
  fi
}

log() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

debug() {
  if [[ "${DEBUG:-0}" == "1" ]]; then
    log "DEBUG: $*"
  fi
}

cleanup_temp_files() {
  rm -f /tmp/cudy_wizard_body.$$ /tmp/cudy_wizard_headers.$$
}

extract_hidden_input_value() {
  local html="$1"
  local name="$2"

  printf '%s' "$html" | sed -nE "s/.*name=\"${name}\"[^>]*value=\"([^\"]*)\".*/\1/p" | head -n1 || true
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

wait_for_ping() {
  local ip="$1"
  local timeout="$2"
  local start
  start="$(date +%s)"

  while true; do
    if ping -c 1 -W 1 "$ip" >/dev/null 2>&1; then
      return 0
    fi

    if (( $(date +%s) - start >= timeout )); then
      return 1
    fi

    sleep "$WAIT_INTERVAL"
  done
}

wait_for_http() {
  local url="$1"
  local timeout="$2"
  local start
  start="$(date +%s)"

  while true; do
    if curl -fsS --connect-timeout 2 "$url" >/dev/null 2>&1; then
      return 0
    fi

    if (( $(date +%s) - start >= timeout )); then
      return 1
    fi

    sleep "$WAIT_INTERVAL"
  done
}

wait_for_https() {
  local url="$1"
  local timeout="$2"
  local start
  start="$(date +%s)"

  while true; do
    if curl -k -fsS --connect-timeout 2 "$url" >/dev/null 2>&1; then
      return 0
    fi

    if (( $(date +%s) - start >= timeout )); then
      return 1
    fi

    sleep "$WAIT_INTERVAL"
  done
}

sha256_hex() {
  local value="$1"

  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$value" | sha256sum | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    printf '%s' "$value" | openssl dgst -sha256 | sed 's/^.*= //'
  elif command -v python3 >/dev/null 2>&1; then
    python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest())' "$value"
  else
    die "Need one of: sha256sum, openssl, python3"
  fi
}

wait_for_ssh() {
  local user_host="$1"
  local timeout="$2"
  local sshpass_bin="${3:-}"
  local start
  start="$(date +%s)"

  while true; do
    if [[ -n "$sshpass_bin" ]]; then
      if SSH_ASKPASS_REQUIRE=never "$sshpass_bin" -p "$OPENWRT_PASS" \
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=3 "$user_host" true >/dev/null 2>&1; then
        return 0
      fi
    else
      if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          -o BatchMode=yes -o ConnectTimeout=3 "$user_host" true >/dev/null 2>&1; then
        return 0
      fi
    fi

    if (( $(date +%s) - start >= timeout )); then
      return 1
    fi

    sleep "$WAIT_INTERVAL"
  done
}

stock_login() {
  local cookie_file="$1"
  local base_url="https://${STOCK_IP}"

  local response csrf salt token hashed_pass final_hash post_status location_header
  local login_response
  local password_form_present=0
  trap cleanup_temp_files RETURN
  response="$(curl -k -sS -c "$cookie_file" "$base_url/cgi-bin/luci")" || \
    die "Unable to open stock firmware login page at $base_url"
  debug "Initial stock login page fetched (${#response} bytes)"

  if printf '%s' "$response" | grep -q 'action="/cgi-bin/luci/admin/wizard"'; then
    csrf="$(extract_hidden_input_value "$response" '_csrf')"
    salt="$(extract_hidden_input_value "$response" 'salt')"
    token="$(extract_hidden_input_value "$response" 'token')"
    debug "Initial wizard fields: csrf=${csrf:+yes} salt=${salt:+yes} token=${token:+yes}"
    [[ -n "$csrf" ]] || die "Failed to extract wizard CSRF token"
    [[ -n "$salt" ]] || die "Failed to extract wizard salt"

    if printf '%s' "$response" | grep -q 'Create an administrator password'; then
      log "Stock firmware requires first-boot password creation"
      hashed_pass="$(sha256_hex "${STOCK_NEW_PASS}${salt}")"
      if [[ -n "$token" ]]; then
        final_hash="$(sha256_hex "${hashed_pass}${token}")"
      else
        final_hash="$hashed_pass"
      fi
      post_status="$(curl -k -sS -o /tmp/cudy_wizard_body.$$ -D /tmp/cudy_wizard_headers.$$ \
        -b "$cookie_file" -c "$cookie_file" \
        -H 'Content-Type: application/x-www-form-urlencoded' \
        --data "_csrf=${csrf}&salt=${salt}&zonename=${STOCK_TIMEZONE}&timeclock=$(date +%s)&luci_username=${STOCK_USER}&luci_password=${final_hash}" \
        -w '%{http_code}' \
        "$base_url/cgi-bin/luci/admin/wizard")" || die "Failed to submit stock first-boot wizard"
      debug "First-boot wizard POST returned HTTP ${post_status}"

      location_header="$(grep -i '^Location:' /tmp/cudy_wizard_headers.$$ | tail -n1 | tr -d '\r' | sed 's/^Location:[[:space:]]*//')"

      case "$post_status" in
        200|302|303) ;;
        *) die "Unexpected response from first-boot wizard: HTTP $post_status" ;;
      esac

      STOCK_PASS="$STOCK_NEW_PASS"
      log "Stock password set successfully"

      if login_response="$(curl -k -fsS -b "$cookie_file" -c "$cookie_file" "$base_url/cgi-bin/luci/admin/status" 2>/dev/null)"; then
        if ! printf '%s' "$login_response" | grep -q 'action="/cgi-bin/luci/admin/wizard"'; then
          debug "First-boot wizard appears to have authenticated the session directly"
          response="$login_response"
        else
          response=""
        fi
      else
        response=""
      fi

      if [[ -z "$response" ]]; then
      if [[ -n "$location_header" ]]; then
        if [[ "$location_header" = /* ]]; then
          response="$(curl -k -fsS -b "$cookie_file" -c "$cookie_file" "$base_url$location_header")" || \
            die "Unable to open redirected page after wizard password setup"
        else
          response="$(curl -k -fsS -b "$cookie_file" -c "$cookie_file" "$location_header")" || \
            die "Unable to open redirected page after wizard password setup"
        fi
      else
        response="$(curl -k -fsS -b "$cookie_file" -c "$cookie_file" "$base_url/cgi-bin/luci")" || \
          die "Unable to reopen login page after wizard password setup"
      fi
      fi

      csrf="$(extract_hidden_input_value "$response" '_csrf')"
      salt="$(extract_hidden_input_value "$response" 'salt')"
      token="$(extract_hidden_input_value "$response" 'token')"
      debug "Post-wizard login fields: csrf=${csrf:+yes} salt=${salt:+yes} token=${token:+yes}"

      if printf '%s' "$response" | grep -q 'placeholder="Password"'; then
        [[ -n "$csrf" ]] || die "Failed to extract login CSRF token after password setup"
        [[ -n "$salt" ]] || die "Failed to extract login salt after password setup"
        [[ -n "$token" ]] || die "Failed to extract login token after password setup"
        password_form_present=1
      else
        debug "No password form shown after password setup; continuing with authenticated session"
        password_form_present=0
      fi
    elif printf '%s' "$response" | grep -q 'placeholder="Password"'; then
      password_form_present=1
    fi

    if (( password_form_present )); then
      [[ -n "$token" ]] || die "Failed to extract wizard token"
      log "Stock firmware requires password login"
      local login_pass
      for login_pass in "$STOCK_PASS" "$STOCK_NEW_PASS"; do
        debug "Trying stock login with password candidate length ${#login_pass}"
        hashed_pass="$(sha256_hex "${login_pass}${salt}")"
        final_hash="$(sha256_hex "${hashed_pass}${token}")"

        post_status="$(curl -k -sS -o /tmp/cudy_wizard_body.$$ -D /tmp/cudy_wizard_headers.$$ \
          -b "$cookie_file" -c "$cookie_file" \
          -H 'Content-Type: application/x-www-form-urlencoded' \
          --data "_csrf=${csrf}&token=${token}&salt=${salt}&zonename=${STOCK_TIMEZONE}&timeclock=$(date +%s)&luci_language=auto&luci_username=${STOCK_USER}&luci_password=${final_hash}" \
          -w '%{http_code}' \
          "$base_url/cgi-bin/luci/admin/wizard")" || die "Failed to submit stock login"
        debug "Stock login POST returned HTTP ${post_status}"

        if [[ "$post_status" != "200" && "$post_status" != "302" && "$post_status" != "303" ]]; then
          continue
        fi

        if login_response="$(curl -k -fsS -b "$cookie_file" -c "$cookie_file" "$base_url/cgi-bin/luci/admin/status" 2>/dev/null)"; then
          debug "Status page after login attempt fetched (${#login_response} bytes)"
          if ! printf '%s' "$login_response" | grep -q 'action="/cgi-bin/luci/admin/wizard"'; then
            STOCK_PASS="$login_pass"
            log "Stock login succeeded"
            break
          fi
        fi
      done

      login_response="$(curl -k -fsS -b "$cookie_file" -c "$cookie_file" "$base_url/cgi-bin/luci/admin/status")" || \
        die "Unable to open stock firmware admin page after stock login"

      if printf '%s' "$login_response" | grep -q 'action="/cgi-bin/luci/admin/wizard"'; then
        die "Stock login returned to wizard page instead of authenticated admin session"
      fi
    else
      debug "Password placeholder not found on response page; assuming wizard already authenticated"
    fi
  else
    die "Unsupported stock login page format: expected wizard form"
  fi

  curl -k -fsS -b "$cookie_file" -c "$cookie_file" "$base_url/cgi-bin/luci/admin/status" >/dev/null || \
    die "Unable to open stock firmware admin page after wizard setup"
}

flash_signed_from_stock() {
  local cookie_file="$1"
  local base_url="https://${STOCK_IP}"
  local fw_path="$SCRIPT_DIR/$SIGNED_FW"
  local upload_name
  local form_page token confirm_page proceed_token

  [[ -f "$fw_path" ]] || die "Signed firmware not found: $fw_path"
  upload_name="$(basename "$fw_path")"

  form_page="$(curl -k -fsS -b "$cookie_file" -c "$cookie_file" "$base_url/cgi-bin/luci/admin/system/upgrade")" || \
    die "Unable to open stock firmware autoupgrade page"
  token="$(printf '%s' "$form_page" | grep -oE 'name="token" value="[^"]+"' | sed -E 's/.*value="([^"]+)"/\1/' | head -n1)"
  [[ -n "$token" ]] || die "Failed to extract stock firmware upload token"

  log "Uploading signed image $SIGNED_FW to stock firmware"
  curl -k --trace-ascii - -fS -b "$cookie_file" -c "$cookie_file" \
    -H 'X-Requested-With: XMLHttpRequest' \
    -H "Referer: ${base_url}/cgi-bin/luci/admin/panel" \
    "$base_url/cgi-bin/luci/admin/network/mesh/batupgrade" >/dev/null || \
    die "Mesh batupgrade pre-trigger failed"

  confirm_page="$(curl -k --trace-ascii - -fS -b "$cookie_file" -c "$cookie_file" \
    -H 'X-Requested-With: XMLHttpRequest' \
    -H "Referer: ${base_url}/cgi-bin/luci/admin/panel" \
    -F 'cbid.upgrade.1.firmware.upload=true' \
    -F "cbid.upgrade.1.firmware=@${fw_path};filename=${upload_name};type=application/octet-stream" \
    -F "token=${token}" \
    "$base_url/cgi-bin/luci/admin/system/upgrade")" || \
    die "Signed firmware upload or flash trigger failed"

  proceed_token="$(printf '%s' "$confirm_page" | grep -oE 'name="token" value="[^"]+"' | sed -E 's/.*value="([^"]+)"/\1/' | head -n1)"
  [[ -n "$proceed_token" ]] || die "Failed to extract proceed token after upload"

  if ! printf '%s' "$confirm_page" | grep -q 'name="cbid.upgrade.1.proceed"'; then
    die "Stock firmware did not return a proceed confirmation page"
  fi

  log "Firmware uploaded; confirming flash procedure"
  curl -k --trace-ascii - -fS -b "$cookie_file" -c "$cookie_file" \
    -H 'X-Requested-With: XMLHttpRequest' \
    -H "Referer: ${base_url}/cgi-bin/luci/admin/panel" \
    --data "token=${proceed_token}&timeclock=$(date +%s)&cbi.submit=1&cbid.upgrade.1.proceed=Proceed" \
    "$base_url/cgi-bin/luci/admin/system/upgrade" >/dev/null || \
    die "Signed firmware proceed trigger failed"

  log "Triggering upgrade reboot sequence"
  curl -k --trace-ascii - -fS -b "$cookie_file" -c "$cookie_file" \
    -H 'X-Requested-With: XMLHttpRequest' \
    -H "Referer: ${base_url}/cgi-bin/luci/admin/panel" \
    "${base_url}/cgi-bin/luci/admin/system/reboot?upgrade=" >/dev/null || \
    die "Upgrade reboot pre-check failed"

  curl -k --trace-ascii - -fS -b "$cookie_file" -c "$cookie_file" \
    -H 'X-Requested-With: XMLHttpRequest' \
    -H "Referer: ${base_url}/cgi-bin/luci/admin/panel" \
    "${base_url}/cgi-bin/luci/admin/system/reboot/apply?upgrade=true" >/dev/null || \
    die "Upgrade reboot apply failed"

  log "Signed image upload request finished; waiting for device reboot"
}

openwrt_ssh_cmd() {
  local sshpass_bin="${1:-}"
  shift || true

  if [[ -n "$sshpass_bin" ]]; then
    SSH_ASKPASS_REQUIRE=never "$sshpass_bin" -p "$OPENWRT_PASS" \
      ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          root@"$OPENWRT_IP" "$@"
  else
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        root@"$OPENWRT_IP" "$@"
  fi
}

openwrt_scp() {
  local sshpass_bin="${1:-}"
  local src="$2"
  local dst="$3"

  if [[ -n "$sshpass_bin" ]]; then
    SSH_ASKPASS_REQUIRE=never "$sshpass_bin" -p "$OPENWRT_PASS" \
      scp -O -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
          "$src" root@"$OPENWRT_IP":"$dst"
  else
    scp -O -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
        "$src" root@"$OPENWRT_IP":"$dst"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --stock-user)
        STOCK_USER="$2"
        shift 2
        ;;
      --model)
        ROUTER_MODEL="$2"
        shift 2
        ;;
      --signed-fw)
        SIGNED_FW="$2"
        shift 2
        ;;
      --openwrt-fw)
        OPENWRT_FW="$2"
        shift 2
        ;;
      --stock-pass)
        STOCK_PASS="$2"
        shift 2
        ;;
      --stock-new-pass)
        STOCK_NEW_PASS="$2"
        shift 2
        ;;
      --openwrt-pass)
        OPENWRT_PASS="$2"
        shift 2
        ;;
      --stock-ip)
        STOCK_IP="$2"
        shift 2
        ;;
      --openwrt-ip)
        OPENWRT_IP="$2"
        shift 2
        ;;
      --timeout)
        WAIT_TIMEOUT="$2"
        shift 2
        ;;
      --stock-timezone)
        STOCK_TIMEZONE="$2"
        shift 2
        ;;
      --help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  set_firmware_paths

  debug "Using stock IP ${STOCK_IP}, OpenWrt IP ${OPENWRT_IP}, signed image ${SIGNED_FW}, OpenWrt image ${OPENWRT_FW}"

  require_cmd curl
  require_cmd ssh
  require_cmd scp
  require_cmd ping

  local sshpass_bin=""
  if [[ -n "$OPENWRT_PASS" ]]; then
    require_cmd sshpass
    sshpass_bin="$(command -v sshpass)"
  fi

  [[ -f "$SCRIPT_DIR/$SIGNED_FW" ]] || die "Missing signed firmware file: $SCRIPT_DIR/$SIGNED_FW"
  [[ -f "$SCRIPT_DIR/$OPENWRT_FW" ]] || die "Missing OpenWrt firmware file: $SCRIPT_DIR/$OPENWRT_FW"

  log "Waiting for stock router at https://${STOCK_IP}"
  wait_for_ping "$STOCK_IP" "$WAIT_TIMEOUT" || die "Router at $STOCK_IP did not respond to ping"
  wait_for_https "https://${STOCK_IP}" "$WAIT_TIMEOUT" || die "Router at $STOCK_IP did not respond over HTTPS"

  local cookie_file
  cookie_file="$(mktemp)"
  trap '[[ -n "${cookie_file:-}" ]] && rm -f "$cookie_file"' EXIT

  log "Logging into stock Cudy firmware"
  stock_login "$cookie_file"

  flash_signed_from_stock "$cookie_file"

  log "Waiting for router to reboot into OpenWrt at ${OPENWRT_IP}"
  sleep 10
  wait_for_ping "$OPENWRT_IP" "$WAIT_TIMEOUT" || die "OpenWrt at $OPENWRT_IP did not respond to ping after signed flash"
  wait_for_ssh "root@${OPENWRT_IP}" "$WAIT_TIMEOUT" "$sshpass_bin" || \
    die "OpenWrt SSH on $OPENWRT_IP did not become available"

  log "Uploading final OpenWrt sysupgrade image ${OPENWRT_FW}"
  openwrt_scp "$sshpass_bin" "$SCRIPT_DIR/$OPENWRT_FW" /tmp/sysupgrade.bin

  log "Starting final sysupgrade"
  openwrt_ssh_cmd "$sshpass_bin" "sysupgrade -n /tmp/sysupgrade.bin" || true

  log "Waiting for router to finish final reboot"
  sleep 10
  wait_for_ping "$OPENWRT_IP" "$WAIT_TIMEOUT" || die "Router did not come back after final sysupgrade"
  wait_for_ssh "root@${OPENWRT_IP}" "$WAIT_TIMEOUT" "$sshpass_bin" || \
    die "OpenWrt SSH did not become available after final sysupgrade"

  log "Flash sequence completed successfully"
}

main "$@"
