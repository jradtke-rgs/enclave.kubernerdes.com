#!/bin/bash
set -euo pipefail

# 00_install_hauler.sh — Install hauler and cosign on the admin node (nuc-00)
#
# Run this AFTER Scripts/nuc-00/post_install.sh.
# Requires: Carbide credentials in ~/.bashrc.d/RGS (sourced below).
#
# After this script: run Scripts/01_hauler_sync.sh to populate the store.

[ -f ~/.bashrc.d/RGS ] && source ~/.bashrc.d/RGS || {
  echo "ERROR: ~/.bashrc.d/RGS not found. Copy from Files/bashrc.d/RGS.template and fill in credentials."
  exit 1
}

# ---------------------------------------------------------------------------
# cosign — supply chain verification
# ---------------------------------------------------------------------------
COSIGN_BINARY=cosign-linux-amd64
TMPDIR="$(mktemp -d)"
trap "rm -rf ${TMPDIR}" EXIT

echo "==> Installing cosign"
curl -fsSL -o "${TMPDIR}/${COSIGN_BINARY}" \
  "https://github.com/sigstore/cosign/releases/latest/download/${COSIGN_BINARY}"
curl -fsSL -o "${TMPDIR}/cosign_checksums.txt" \
  "https://github.com/sigstore/cosign/releases/latest/download/cosign_checksums.txt"

EXPECTED_HASH=$(grep -w "${COSIGN_BINARY}" "${TMPDIR}/cosign_checksums.txt" | awk '{print $1}')
CALCULATED_HASH=$(sha256sum "${TMPDIR}/${COSIGN_BINARY}" | awk '{print $1}')

if [[ "${EXPECTED_HASH}" != "${CALCULATED_HASH}" ]]; then
  echo "ERROR: cosign checksum mismatch. Aborting."
  exit 1
fi
sudo install -m 0755 -o root "${TMPDIR}/${COSIGN_BINARY}" /usr/local/bin/cosign
echo "    cosign installed: $(cosign version 2>/dev/null | head -1)"

# ---------------------------------------------------------------------------
# hauler
# ---------------------------------------------------------------------------
echo "==> Installing hauler"
curl -sfL https://get.hauler.dev | sudo bash
echo "    hauler installed: $(hauler version 2>/dev/null | head -1)"

# ---------------------------------------------------------------------------
# hauler environment — store location and shell helpers
# ---------------------------------------------------------------------------
HAULER_STORE_DIR=/srv/www/htdocs/hauler/store
sudo mkdir -p "${HAULER_STORE_DIR}"

mkdir -p ~/.bashrc.d

cat << EOF > ~/.bashrc.d/HAULER
# Hauler environment
export HAULER_STORE_DIR=${HAULER_STORE_DIR}

# Convenience alias — login to the Carbide registry
alias hauler_login="hauler login rgcrprod.azurecr.us -u \${Carbide_Registry_Username} -p \${Carbide_Registry_Password}"
EOF

# bash completion
hauler completion bash > ~/.bashrc.d/HAULER-completion

echo
echo "==> hauler setup complete."
echo "    Store dir : ${HAULER_STORE_DIR}"
echo "    Next step : source ~/.bashrc && run Scripts/01_hauler_sync.sh"
