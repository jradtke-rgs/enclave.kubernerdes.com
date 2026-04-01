#!/bin/bash
set -euo pipefail

# 02_setup_ca.sh — Generate the enclave root CA on nuc-00
#
# Run ONCE as root on nuc-00, before any service requiring TLS (e.g. 03_install_harbor.sh).
# Idempotent — exits cleanly if the CA already exists.
#
# What this does:
#   1. Generates an RSA 4096 root CA (10-year validity)
#   2. Stores it in /etc/ssl/enclave-ca/ (key is chmod 600)
#   3. Adds the root CA to the nuc-00 system trust store
#   4. Restarts Docker if running (so it picks up the new CA immediately)
#
# To sign a certificate for a new service, use the helper pattern in this script:
#   openssl genrsa -out <service>.key 4096
#   openssl req -new -key <service>.key -out <service>.csr -subj "/CN=<hostname>/O=enclave/C=US"
#   openssl x509 -req -days 730 -in <service>.csr \
#     -CA /etc/ssl/enclave-ca/ca.crt -CAkey /etc/ssl/enclave-ca/ca.key -CAcreateserial \
#     -out <service>.crt -extfile <(printf "subjectAltName=DNS:<hostname>,IP:<ip>")
#
# Distribute the root CA cert to all enclave nodes:
#   scp root@10.10.12.10:/etc/ssl/enclave-ca/ca.crt /etc/pki/trust/anchors/enclave-root-ca.crt
#   update-ca-certificates

CA_DIR="/etc/ssl/enclave-ca"
CA_CN="${CA_CN:-enclave.kubernerdes.com Root CA}"
CA_VALIDITY_DAYS="${CA_VALIDITY_DAYS:-3650}"  # 10 years
HAULER_FILES_STORE="${HAULER_FILES_STORE:-/root/hauler/store/files}"

# ---------------------------------------------------------------------------
# Pre-flight
# ---------------------------------------------------------------------------
if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: This script must be run as root."
  exit 1
fi

# ---------------------------------------------------------------------------
# Helper — add CA cert to hauler files store so nodes can fetch it via curl
# ---------------------------------------------------------------------------
add_ca_to_hauler_store() {
  if ! command -v hauler &>/dev/null; then
    echo "    hauler not installed — skipping files store update."
    echo "    Run this script again after installing hauler (00_install_hauler.sh)."
    return 0
  fi
  mkdir -p "${HAULER_FILES_STORE}"
  echo "==> Adding enclave root CA to hauler files store (${HAULER_FILES_STORE})"
  hauler store add file "${CA_DIR}/ca.crt" \
    --name enclave-root-ca.crt \
    --store "${HAULER_FILES_STORE}"
  echo "    Nodes can now fetch the CA via:"
  echo "      curl -sfL http://10.10.12.10:8080/enclave-root-ca.crt \\"
  echo "        -o /etc/pki/trust/anchors/enclave-root-ca.crt"
}

# ---------------------------------------------------------------------------
# Idempotency check — do not overwrite an existing CA
# ---------------------------------------------------------------------------
if [[ -f "${CA_DIR}/ca.crt" && -f "${CA_DIR}/ca.key" ]]; then
  echo "==> Enclave root CA already exists at ${CA_DIR} — nothing to do."
  echo "    Subject: $(openssl x509 -in "${CA_DIR}/ca.crt" -noout -subject)"
  echo "    Expires: $(openssl x509 -in "${CA_DIR}/ca.crt" -noout -enddate)"
  add_ca_to_hauler_store
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 1 — Generate root CA
# ---------------------------------------------------------------------------
echo "==> Generating enclave root CA"
mkdir -p "${CA_DIR}"
chmod 700 "${CA_DIR}"

openssl genrsa -out "${CA_DIR}/ca.key" 4096
chmod 600 "${CA_DIR}/ca.key"

openssl req -x509 -new -nodes \
  -key  "${CA_DIR}/ca.key" \
  -sha256 \
  -days "${CA_VALIDITY_DAYS}" \
  -out  "${CA_DIR}/ca.crt" \
  -subj "/CN=${CA_CN}/O=enclave/C=US" \
  -addext "basicConstraints=critical,CA:true" \
  -addext "keyUsage=critical,keyCertSign,cRLSign"

echo "    CA certificate: ${CA_DIR}/ca.crt"
echo "    CA private key: ${CA_DIR}/ca.key (keep this secure — do not distribute)"
echo "    Subject:        $(openssl x509 -in "${CA_DIR}/ca.crt" -noout -subject)"
echo "    Expires:        $(openssl x509 -in "${CA_DIR}/ca.crt" -noout -enddate)"

# ---------------------------------------------------------------------------
# Step 2 — Trust the CA on nuc-00
# ---------------------------------------------------------------------------
echo "==> Adding root CA to nuc-00 system trust store"
cp "${CA_DIR}/ca.crt" /etc/pki/trust/anchors/enclave-root-ca.crt
update-ca-certificates

# ---------------------------------------------------------------------------
# Step 3 — Add CA to hauler files store for node distribution via fileserver
# ---------------------------------------------------------------------------
add_ca_to_hauler_store

# ---------------------------------------------------------------------------
# Step 5 — Restart Docker if running (picks up the new CA for image pulls)
# ---------------------------------------------------------------------------
if systemctl is-active --quiet docker 2>/dev/null; then
  echo "==> Restarting Docker to pick up new CA"
  systemctl restart docker
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
echo "==> Root CA setup complete."
echo
echo "    Nodes fetch the CA via the hauler fileserver (install_RKE2.sh does this automatically):"
echo "      curl -sfL http://10.10.12.10:8080/enclave-root-ca.crt \\"
echo "        -o /etc/pki/trust/anchors/enclave-root-ca.crt"
echo "      update-ca-certificates"
echo
echo "    cert-manager integration (once RKE2/Rancher is running):"
echo "      Create a CA ClusterIssuer using ${CA_DIR}/ca.crt and ${CA_DIR}/ca.key"
