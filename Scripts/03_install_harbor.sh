#!/bin/bash
set -euo pipefail

# 03_install_harbor.sh — Install Harbor OCI registry on nuc-00 and import hauler stores
#
# Run as root on nuc-00 AFTER:
#   01_hauler_sync.sh   — hauler stores populated
#   02_setup_ca.sh      — enclave root CA generated and trusted
#
# What this does:
#   1. Installs Docker and docker-compose
#   2. Creates a 200G LVM volume for Harbor data (on vg_data) and mounts it
#   3. Fetches the Harbor offline installer (from hauler files store if pre-synced,
#      otherwise downloads from GitHub — requires network connectivity)
#   4. Generates a CA-signed TLS certificate for Harbor
#   5. Installs and starts Harbor
#   6. Creates a Harbor project per hauler image store
#   7. Pushes all hauler image stores to their Harbor projects via hauler store copy
#
# Environment variable overrides:
#   HARBOR_VERSION        (default: v2.12.2)
#   HARBOR_HOSTNAME       (default: nuc-00.enclave.kubernerdes.com)
#   HARBOR_ADMIN_PASSWORD (prompted interactively if not set)

HARBOR_VERSION="${HARBOR_VERSION:-v2.12.2}"
HARBOR_HOSTNAME="${HARBOR_HOSTNAME:-nuc-00.enclave.kubernerdes.com}"
HARBOR_DATA_DIR="${HARBOR_DATA_DIR:-/data/harbor}"
HARBOR_INSTALL_DIR="/opt/harbor"
HARBOR_CERT_DIR="${HARBOR_INSTALL_DIR}/certs"
HAULER_STORE_DIR="${HAULER_STORE_DIR:-/root/hauler/store}"
HARBOR_LV_SIZE="${HARBOR_LV_SIZE:-200G}"
VG_NAME="vg_data"
LV_NAME="lv_harbor_data"
CA_DIR="/etc/ssl/enclave-ca"

HARBOR_INSTALLER="harbor-offline-installer-${HARBOR_VERSION}.tgz"
HARBOR_INSTALLER_URL="https://github.com/goharbor/harbor/releases/download/${HARBOR_VERSION}/${HARBOR_INSTALLER}"
HARBOR_DOWNLOAD_DIR="/root/harbor-install"

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

if [[ ! -f "${CA_DIR}/ca.crt" || ! -f "${CA_DIR}/ca.key" ]]; then
  echo "ERROR: Enclave root CA not found at ${CA_DIR}."
  echo "       Run 02_setup_ca.sh first."
  exit 1
fi

if [[ -z "${HARBOR_ADMIN_PASSWORD:-}" ]]; then
  read -rsp "Harbor admin password: " HARBOR_ADMIN_PASSWORD
  echo
fi

# ---------------------------------------------------------------------------
# Step 1 — Install Docker and docker-compose
# ---------------------------------------------------------------------------
echo "==> Installing Docker"
if ! command -v docker &>/dev/null; then
  zypper --non-interactive install docker docker-compose
  systemctl enable --now docker
  echo "    Docker installed: $(docker --version)"
else
  echo "    Docker already installed: $(docker --version)"
  systemctl is-active --quiet docker || systemctl start docker
fi

# ---------------------------------------------------------------------------
# Step 2 — Create LVM volume for Harbor data
# ---------------------------------------------------------------------------
echo "==> Preparing Harbor data volume (${HARBOR_LV_SIZE} on ${VG_NAME})"
if ! lvs "${VG_NAME}/${LV_NAME}" &>/dev/null 2>&1; then
  lvcreate -L "${HARBOR_LV_SIZE}" -n "${LV_NAME}" "${VG_NAME}"
  mkfs.xfs "/dev/${VG_NAME}/${LV_NAME}"
  echo "    Created /dev/${VG_NAME}/${LV_NAME} (${HARBOR_LV_SIZE})"
else
  echo "    LV ${LV_NAME} already exists"
fi

mkdir -p "${HARBOR_DATA_DIR}"
if ! mountpoint -q "${HARBOR_DATA_DIR}"; then
  mount "/dev/mapper/${VG_NAME}-${LV_NAME}" "${HARBOR_DATA_DIR}"
  if ! grep -q "${LV_NAME}" /etc/fstab; then
    echo "/dev/mapper/${VG_NAME}-${LV_NAME} ${HARBOR_DATA_DIR} xfs defaults 0 0" >> /etc/fstab
  fi
  echo "    Mounted at ${HARBOR_DATA_DIR}"
else
  echo "    ${HARBOR_DATA_DIR} already mounted"
fi

# ---------------------------------------------------------------------------
# Step 3 — Fetch Harbor offline installer
# ---------------------------------------------------------------------------
mkdir -p "${HARBOR_DOWNLOAD_DIR}"

if [[ -f "${HARBOR_DOWNLOAD_DIR}/${HARBOR_INSTALLER}" ]]; then
  echo "==> Harbor installer already present: ${HARBOR_DOWNLOAD_DIR}/${HARBOR_INSTALLER}"
else
  # Try the hauler files store first (if 01_hauler_sync.sh pre-pulled it)
  RETRIEVED=false
  if [[ -d "${HAULER_STORE_DIR}/files" ]]; then
    echo "==> Checking hauler files store for Harbor installer"
    hauler store serve fileserver \
      --store "${HAULER_STORE_DIR}/files" \
      --port 18080 &>/dev/null &
    FILESERVER_PID=$!
    sleep 3
    if curl -fsSL "http://localhost:18080/${HARBOR_INSTALLER}" \
        -o "${HARBOR_DOWNLOAD_DIR}/${HARBOR_INSTALLER}" 2>/dev/null; then
      echo "    Retrieved ${HARBOR_INSTALLER} from hauler files store"
      RETRIEVED=true
    else
      rm -f "${HARBOR_DOWNLOAD_DIR}/${HARBOR_INSTALLER}"
    fi
    kill "${FILESERVER_PID}" 2>/dev/null || true
    wait "${FILESERVER_PID}" 2>/dev/null || true
  fi

  if [[ "${RETRIEVED}" == "false" ]]; then
    echo "==> Downloading Harbor ${HARBOR_VERSION} offline installer from GitHub"
    curl -fL "${HARBOR_INSTALLER_URL}" -o "${HARBOR_DOWNLOAD_DIR}/${HARBOR_INSTALLER}"
  fi
fi

# ---------------------------------------------------------------------------
# Step 4 — Extract Harbor and generate CA-signed TLS certificate
# ---------------------------------------------------------------------------
if [[ ! -d "${HARBOR_INSTALL_DIR}" ]]; then
  echo "==> Extracting Harbor installer to /opt"
  tar -xzf "${HARBOR_DOWNLOAD_DIR}/${HARBOR_INSTALLER}" -C /opt
  # tarball always extracts to /opt/harbor
fi

echo "==> Generating CA-signed TLS certificate for ${HARBOR_HOSTNAME}"
mkdir -p "${HARBOR_CERT_DIR}"
if [[ ! -f "${HARBOR_CERT_DIR}/harbor.crt" ]]; then
  openssl genrsa -out "${HARBOR_CERT_DIR}/harbor.key" 4096
  openssl req -new \
    -key "${HARBOR_CERT_DIR}/harbor.key" \
    -out "${HARBOR_CERT_DIR}/harbor.csr" \
    -subj "/CN=${HARBOR_HOSTNAME}/O=enclave/C=US"
  openssl x509 -req -days 730 \
    -in     "${HARBOR_CERT_DIR}/harbor.csr" \
    -CA     "${CA_DIR}/ca.crt" \
    -CAkey  "${CA_DIR}/ca.key" \
    -CAcreateserial \
    -out    "${HARBOR_CERT_DIR}/harbor.crt" \
    -extfile <(printf "subjectAltName=IP:10.10.12.10,DNS:%s" "${HARBOR_HOSTNAME}")
  rm -f "${HARBOR_CERT_DIR}/harbor.csr"
  echo "    Certificate: ${HARBOR_CERT_DIR}/harbor.crt (signed by enclave CA, valid 2 years)"
else
  echo "    Certificate already exists: ${HARBOR_CERT_DIR}/harbor.crt"
fi

echo "==> Writing harbor.yml"
cat > "${HARBOR_INSTALL_DIR}/harbor.yml" << HARBORYML
hostname: ${HARBOR_HOSTNAME}

https:
  port: 443
  certificate: ${HARBOR_CERT_DIR}/harbor.crt
  private_key: ${HARBOR_CERT_DIR}/harbor.key

harbor_admin_password: ${HARBOR_ADMIN_PASSWORD}

database:
  password: ${HARBOR_ADMIN_PASSWORD}
  max_idle_conns: 100
  max_open_conns: 900

data_volume: ${HARBOR_DATA_DIR}

log:
  level: info
  local:
    rotate_count: 50
    rotate_size: 200M
    location: /var/log/harbor
HARBORYML

# ---------------------------------------------------------------------------
# Step 5 — Install and start Harbor
# ---------------------------------------------------------------------------
echo "==> Running Harbor installer"
cd "${HARBOR_INSTALL_DIR}"
./install.sh

# ---------------------------------------------------------------------------
# Step 6 — Wait for Harbor to become healthy
# ---------------------------------------------------------------------------
echo "==> Waiting for Harbor to be ready (up to 5 minutes)"
for i in $(seq 1 30); do
  if curl -sk "https://${HARBOR_HOSTNAME}/api/v2.0/health" 2>/dev/null | grep -q "healthy"; then
    echo "    Harbor is ready."
    break
  fi
  if [[ "${i}" -eq 30 ]]; then
    echo "ERROR: Harbor did not become healthy in time."
    echo "       Check status: docker compose -f ${HARBOR_INSTALL_DIR}/docker-compose.yml ps"
    exit 1
  fi
  echo "    Waiting... (${i}/30)"
  sleep 10
done

# ---------------------------------------------------------------------------
# Step 7 — Create Harbor projects
# ---------------------------------------------------------------------------
echo "==> Creating Harbor projects"
HARBOR_API="https://${HARBOR_HOSTNAME}/api/v2.0"

for PROJECT in rancher rke2 neuvector harvester carbide third-party-charts; do
  HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" \
    -u "admin:${HARBOR_ADMIN_PASSWORD}" \
    -H "Content-Type: application/json" \
    -X POST "${HARBOR_API}/projects" \
    -d "{\"project_name\":\"${PROJECT}\",\"public\":false}")
  case "${HTTP_CODE}" in
    201) echo "    Created: ${PROJECT}" ;;
    409) echo "    Already exists: ${PROJECT}" ;;
    *)   echo "    WARNING: HTTP ${HTTP_CODE} for project ${PROJECT}" ;;
  esac
done

# ---------------------------------------------------------------------------
# Step 8 — Push hauler stores to Harbor
#
# Map: hauler store directory name → Harbor project name
# 'files' is intentionally excluded — binaries are served separately via:
#   hauler store serve fileserver --store /root/hauler/store/files
# ---------------------------------------------------------------------------
echo "==> Logging hauler into Harbor"
hauler login "${HARBOR_HOSTNAME}" \
  -u admin \
  -p "${HARBOR_ADMIN_PASSWORD}"

declare -A STORE_PROJECTS=(
  ["rancher"]="rancher"
  ["rke2"]="rke2"
  ["neuvector"]="neuvector"
  ["harvester"]="harvester"
  ["carbide-images"]="carbide"
  ["third-party-charts"]="third-party-charts"
)

for STORE in "${!STORE_PROJECTS[@]}"; do
  STORE_PATH="${HAULER_STORE_DIR}/${STORE}"
  if [[ ! -d "${STORE_PATH}" ]]; then
    echo "    Skipping ${STORE} — store not found at ${STORE_PATH}"
    continue
  fi
  PROJECT="${STORE_PROJECTS[${STORE}]}"
  echo "==> Pushing ${STORE} → ${HARBOR_HOSTNAME}/${PROJECT}"
  hauler store copy \
    --store "${STORE_PATH}" \
    "registry://${HARBOR_HOSTNAME}/${PROJECT}"
done

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
echo "==> Harbor installation and import complete."
echo
echo "    URL:       https://${HARBOR_HOSTNAME}"
echo "    Username:  admin"
echo
echo "    Harbor TLS is signed by the enclave root CA."
echo "    Nodes that do not yet have the CA trusted:"
echo "      scp root@10.10.12.10:${CA_DIR}/ca.crt /etc/pki/trust/anchors/enclave-root-ca.crt"
echo "      update-ca-certificates"
echo
echo "    Binary artifacts (RKE2 install script, cosign, etc.) are NOT in Harbor."
echo "    Serve them via: hauler store serve fileserver --store ${HAULER_STORE_DIR}/files"
