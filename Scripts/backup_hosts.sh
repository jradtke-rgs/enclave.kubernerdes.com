#!/usr/bin/env bash

# Backup configuration files from enclave hosts
# Usage: ./backup_hosts.sh [hostname...]
#   With no arguments, backs up all hosts.
#   With arguments, backs up only the specified hosts.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_BASE="${SCRIPT_DIR}/../Files"

# Domain appended to short hostnames for SSH connections
DOMAIN="enclave.kubernerdes.com"
DEFAULT_SSH_USER="root"

# --- Per-host file lists ---

NUC_00_FILES=(
  /etc/apache2/httpd.conf
)

NUC_00_01_FILES=(
  /etc/dhcpd.conf
  /etc/dhcpd.d/dhcpd-hosts.conf
  /etc/named.conf
  /var/lib/named/master/db.enclave.kubernerdes.com
  /var/lib/named/master/db-12.10.10.in-addr.arpa
  /var/lib/named/master/db-13.10.10.in-addr.arpa
  /var/lib/named/master/db-14.10.10.in-addr.arpa
  /var/lib/named/master/db-15.10.10.in-addr.arpa
)

NUC_00_02_FILES=(
  /etc/named.conf
)

# --- Functions ---

backup_host() {
  local host="$1"
  shift
  local files=("$@")
  local dest="${BACKUP_BASE}/${host}"
  local errors=0

  local fqdn="${host}.${DOMAIN}"
  echo "=== Backing up ${host} (${fqdn}) ==="
  for file in "${files[@]}"; do
    local target_dir="${dest}$(dirname "$file")"
    mkdir -p "$target_dir"
    if scp -q "${DEFAULT_SSH_USER}@${fqdn}:${file}" "${dest}${file}"; then
      echo "  OK: ${file}"
    else
      echo "  FAIL: ${file}"
      ((errors++))
    fi
  done

  if [ "$errors" -gt 0 ]; then
    echo "  ${errors} file(s) failed for ${host}"
  fi
  echo
  return "$errors"
}

# --- Main ---

# Map hostnames to their file lists
declare -A HOST_FILES_REF
HOST_FILES_REF=(
  [nuc-00]="NUC_00_FILES"
  [nuc-00-01]="NUC_00_01_FILES"
  [nuc-00-02]="NUC_00_02_FILES"
)

ALL_HOSTS=(nuc-00 nuc-00-01 nuc-00-02)
TARGETS=("${@:-${ALL_HOSTS[@]}}")
# If no args provided, default to all hosts
if [ "$#" -eq 0 ]; then
  TARGETS=("${ALL_HOSTS[@]}")
fi

total_errors=0
for host in "${TARGETS[@]}"; do
  ref="${HOST_FILES_REF[$host]}"
  if [ -z "$ref" ]; then
    echo "Unknown host: ${host}" >&2
    ((total_errors++))
    continue
  fi

  # Use nameref to resolve the array
  declare -n file_list="$ref"
  backup_host "$host" "${file_list[@]}"
  ((total_errors += $?))
done

if [ "$total_errors" -gt 0 ]; then
  echo "Completed with ${total_errors} error(s)."
  exit 1
fi

echo "All backups completed successfully."
