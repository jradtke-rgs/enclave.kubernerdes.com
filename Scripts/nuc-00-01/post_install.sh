#!/bin/bash

# nuc-00-01 post_install.sh — Infra VM: DNS, DHCP, TFTP/PXE
#
# Run as root (or via sudo su -) after a fresh OpenSUSE Leap 15.6 install.
# Cut-and-paste execution; review each section before proceeding.
#
# Services installed:
#   BIND   — authoritative DNS for enclave.kubernerdes.com
#   DHCP   — ISC dhcpd with iPXE boot support for Harvester nodes
#   TFTP   — serves ipxe.efi for initial UEFI PXE handoff
#   kubectl — for cluster management from the infra node
#
# Config files are pulled from the admin node web root during install,
# then managed in-place (or via this repo) going forward.

ADMIN_NODE_IP=10.10.12.10
REPO_BASE="http://${ADMIN_NODE_IP}/enclave.kubernerdes.com"

# ---------------------------------------------------------------------------
# Base packages
# ---------------------------------------------------------------------------
zypper --non-interactive install sudo vim wget curl

MYUSER=$(whoami)
echo "${MYUSER} ALL=(ALL) NOPASSWD: ALL" | tee /etc/sudoers.d/${MYUSER}-nopasswd-all

# ---------------------------------------------------------------------------
# DNS + DHCP pattern (BIND + ISC dhcpd)
# ---------------------------------------------------------------------------
zypper --non-interactive install -t pattern dhcp_dns_server
zypper --non-interactive install bind-utils

# ---------------------------------------------------------------------------
# TFTP + iPXE EFI binary
# ---------------------------------------------------------------------------
case $(uname -n) in
  nuc-00-01)
    zypper --non-interactive install tftp
    mkdir -p /srv/tftpboot
    # ipxe.efi is served from the hauler fileserver on the admin node
    # so nodes load it via TFTP on first boot, then iPXE takes over via HTTP
    wget -O /srv/tftpboot/ipxe.efi http://${ADMIN_NODE_IP}:8080/ipxe.efi \
      || wget -O /srv/tftpboot/ipxe.efi https://boot.netboot.xyz/ipxe/netboot.xyz.efi
  ;;
esac

# ---------------------------------------------------------------------------
# BIND configuration
# ---------------------------------------------------------------------------
cp /etc/named.conf /etc/named.conf.$(date +%F)
curl -o /etc/named.conf ${REPO_BASE}/Files/nuc-00-01/etc/named.conf

mkdir -p /var/lib/named/master /var/lib/named/slave /var/lib/named/dyn
for ZONE_FILE in \
  db.enclave.kubernerdes.com \
  db-12.10.10.in-addr.arpa \
  db-13.10.10.in-addr.arpa \
  db-14.10.10.in-addr.arpa \
  db-15.10.10.in-addr.arpa
do
  curl -o /var/lib/named/master/${ZONE_FILE} \
    ${REPO_BASE}/Files/nuc-00-01/var/lib/named/master/${ZONE_FILE}
done

chown -R root:root /var/lib/named/master/
systemctl enable named --now
systemctl status named

# ---------------------------------------------------------------------------
# DHCP
# ---------------------------------------------------------------------------
case $(uname -n) in
  nuc-00-01)
    cp /etc/dhcpd.conf /etc/dhcpd.conf.$(date +%F)
    curl -o /etc/dhcpd.conf ${REPO_BASE}/Files/nuc-00-01/etc/dhcpd.conf
    mkdir -p /etc/dhcpd.d/
    curl -o /etc/dhcpd.d/dhcpd-hosts.conf \
      ${REPO_BASE}/Files/nuc-00-01/etc/dhcpd.d/dhcpd-hosts.conf

    sed -i -e 's/DHCPD_INTERFACE=""/DHCPD_INTERFACE="eth0"/g' /etc/sysconfig/dhcpd

    mkdir -p /etc/systemd/system/dhcpd.service.d
    printf '[Unit]\nRequires=network-online.target\nAfter=network-online.target\n' \
      | tee /etc/systemd/system/dhcpd.service.d/override.conf
    systemctl daemon-reload

    systemctl enable dhcpd --now
    systemctl status dhcpd
  ;;
esac

# ---------------------------------------------------------------------------
# Firewall
# ---------------------------------------------------------------------------
TCP_PORTS="53 80 443"
UDP_PORTS="53 67 68 69 4011"
SERVICES="http https dns dhcp tftp"

for PORT in $TCP_PORTS; do firewall-cmd --permanent --zone=public --add-port=${PORT}/tcp; done
for PORT in $UDP_PORTS; do firewall-cmd --permanent --zone=public --add-port=${PORT}/udp; done
for SVC  in $SERVICES;  do firewall-cmd --permanent --zone=public --add-service=${SVC}; done

firewall-cmd --reload
firewall-cmd --list-all

# ---------------------------------------------------------------------------
# kubectl
# ---------------------------------------------------------------------------
tee /etc/zypp/repos.d/kubernetes.repo << 'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repomd.xml.key
EOF
zypper refresh
zypper --non-interactive install kubectl

# ---------------------------------------------------------------------------
# Ansible (for future use)
# ---------------------------------------------------------------------------
zypper --non-interactive install ansible

exit 0
