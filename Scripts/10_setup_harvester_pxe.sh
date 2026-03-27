#!/bin/bash
set -euo pipefail

# 10_setup_harvester_pxe.sh — Prepare admin node to PXE-boot Harvester
#
# Run on nuc-00 AFTER Scripts/00_hauler_sync.sh has completed.
# This script extracts the Harvester boot files from the hauler store and
# places them in the Apache web root so iPXE can load them.
#
# Hauler stores Harvester artifacts as OCI objects. We use `hauler store copy`
# to export them to the filesystem, then arrange them at the expected paths.
#
# After this script:
#   1. Verify http://10.10.12.10/harvester/<version>/ serves the boot files
#   2. Update NIC names and tokens in Files/nuc-00/srv/www/htdocs/harvester/config-*.yaml
#   3. Copy config files to web root (step below)
#   4. Power on nuc-01 → PXE boot → select nuc-01 from menu → cluster creates
#   5. Power on nuc-02/03 → PXE boot → select their entry → nodes join

HARVESTER_VERSION="v1.4.1"
ADMIN_NODE_IP="10.10.12.10"
WEB_ROOT="/srv/www/htdocs"
HARVESTER_WEB_DIR="${WEB_ROOT}/harvester"
VERSION_DIR="${HARVESTER_WEB_DIR}/${HARVESTER_VERSION}"
REPO_DIR="${WEB_ROOT}/enclave.kubernerdes.com"

HAULER_STORE_DIR="${HAULER_STORE_DIR:-/srv/www/htdocs/hauler/store}"

# ---------------------------------------------------------------------------
# Step 1 — Export Harvester files from hauler store
# ---------------------------------------------------------------------------
echo "==> Exporting Harvester ${HARVESTER_VERSION} files from hauler store"
sudo mkdir -p "${VERSION_DIR}"

# hauler store copy exports OCI artifacts; Harvester product artifacts include
# the ISO, vmlinuz, initrd, and rootfs squashfs.
# Adjust the OCI reference if hauler uses a different tag format.
hauler store copy \
  --store "${HAULER_STORE_DIR}" \
  dir:"${VERSION_DIR}" \
  || {
    echo "NOTE: 'hauler store copy' to dir failed — attempting manual extraction."
    echo "      Check 'hauler store list' for the correct Harvester artifact reference."
    echo "      Then manually copy files to ${VERSION_DIR}/"
    hauler store list --store "${HAULER_STORE_DIR}" | grep -i harvester || true
    exit 1
  }

echo "==> Files in ${VERSION_DIR}:"
ls -lh "${VERSION_DIR}/"

# ---------------------------------------------------------------------------
# Step 2 — Copy iPXE menu and node configs to web root
# ---------------------------------------------------------------------------
echo "==> Copying iPXE menu and Harvester node configs to web root"
sudo mkdir -p "${HARVESTER_WEB_DIR}"

sudo cp "${REPO_DIR}/Files/nuc-00/srv/www/htdocs/harvester/harvester/ipxe-menu" \
        "${HARVESTER_WEB_DIR}/ipxe-menu"

for CONFIG in config-create-nuc-01.yaml config-join-nuc-02.yaml config-join-nuc-03.yaml; do
  sudo cp "${REPO_DIR}/Files/nuc-00/srv/www/htdocs/harvester/harvester/${CONFIG}" \
          "${HARVESTER_WEB_DIR}/${CONFIG}"
  echo "    Copied: ${CONFIG}"
done

# ---------------------------------------------------------------------------
# Step 3 — Verify web server is serving the files
# ---------------------------------------------------------------------------
echo "==> Verifying web server"
curl -sI "http://${ADMIN_NODE_IP}/harvester/${HARVESTER_VERSION}/" | head -5

echo
echo "==> Setup complete."
echo "    iPXE menu : http://${ADMIN_NODE_IP}/harvester/ipxe-menu"
echo "    Boot files: http://${ADMIN_NODE_IP}/harvester/${HARVESTER_VERSION}/"
echo
echo "    BEFORE BOOTING: review and update these files on the web root:"
echo "      ${HARVESTER_WEB_DIR}/config-create-nuc-01.yaml  — ssh key, token, NIC name"
echo "      ${HARVESTER_WEB_DIR}/config-join-nuc-02.yaml"
echo "      ${HARVESTER_WEB_DIR}/config-join-nuc-03.yaml"
echo
echo "    Then: power on nuc-01, select 'Deploy Harvester to nuc-01' from iPXE menu."
echo "    Wait for nuc-01 install to complete, then power on nuc-02 and nuc-03."
