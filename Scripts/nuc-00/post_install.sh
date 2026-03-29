#!/bin/bash

# nuc-00 post_install.sh — Admin node setup
#
# Run as the initial user after a fresh OpenSUSE Leap 15.6 install.
# This script is node-aware and intended for cut-and-paste execution
# rather than being run headlessly — review each section before proceeding.
#
# What this does:
#   1. SSH key + sudo configuration
#   2. Disable power-saving (server role)
#   3. Configure second NVMe disk (LVM: libvirt images + www data)
#   4. Install and configure Apache web server
#   5. Install libvirt / KVM
#   6. Create network bridge for VMs
#   7. Download OpenSUSE Leap 15.6 ISO and mount it for VM installs
#   8. Deploy infra VMs (nuc-00-01, nuc-00-02)
#   9. Install tools (git, kubectl)
#
# NOTE: Hauler install and content sync are handled separately in:
#   Scripts/00_install_hauler.sh
#   Scripts/01_hauler_sync.sh

# ---------------------------------------------------------------------------
# 1. SSH key + sudo
# ---------------------------------------------------------------------------
echo | ssh-keygen -t rsa -b 4096 -N '' -f ~/.ssh/id_rsa-enclave

MYUSER=$(whoami)
echo "$MYUSER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/${MYUSER}-sudo

# Wire up ~/.bashrc.d/ sourcing
cat << 'EOF' >> ~/.bashrc

if [ -d ~/.bashrc.d ]; then
  for rc in ~/.bashrc.d/*; do
    [ -f "$rc" ] && . "$rc"
  done
fi
unset rc
EOF

# Copy in Carbide credentials template — fill in values before sourcing
mkdir -p ~/.bashrc.d
cp /srv/www/htdocs/enclave.kubernerdes.com/Files/bashrc.d/RGS.template ~/.bashrc.d/RGS
echo "NOTE: Edit ~/.bashrc.d/RGS and fill in your Carbide credentials before continuing."

# ---------------------------------------------------------------------------
# 2. Disable power-saving (nuc-00 runs as a server)
# ---------------------------------------------------------------------------
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# ---------------------------------------------------------------------------
# 3. Storage — second NVMe disk (LVM)
# ---------------------------------------------------------------------------
DATA_DEVICE=nvme0n1

if sudo lsblk -f /dev/$DATA_DEVICE | grep -q part; then
  echo "ERROR: /dev/$DATA_DEVICE already has partitions. Verify before proceeding."
  exit 9
fi

sudo parted -s /dev/$DATA_DEVICE mklabel gpt mkpart pri 2048s 100% set 1 lvm on
sudo pvcreate /dev/${DATA_DEVICE}p1
sudo vgcreate vg_data /dev/${DATA_DEVICE}p1

# 500GB for libvirt VM images
sudo lvcreate -L500g -n lv_libvirt_images vg_data
sudo mkfs.ext4 /dev/mapper/vg_data-lv_libvirt_images

# 100GB for web/hauler store
sudo lvcreate -L100g -n lv_www vg_data
sudo mkfs.ext4 /dev/mapper/vg_data-lv_www

sudo cp /etc/fstab /etc/fstab-$(date +%F)
echo "# Managed volumes" | sudo tee -a /etc/fstab

sudo mkdir -p /data/var/lib/libvirt/images
echo "/dev/mapper/vg_data-lv_libvirt_images /data/var/lib/libvirt/images ext4 defaults 0 0" | sudo tee -a /etc/fstab
sudo mount -a
echo "/data/var/lib/libvirt/images /var/lib/libvirt/images none bind 0 0" | sudo tee -a /etc/fstab
sudo mount -a

sudo mkdir -p /data/srv/www
echo "/dev/mapper/vg_data-lv_www /data/srv/www ext4 defaults 0 0" | sudo tee -a /etc/fstab
sudo mount -a
sudo mv /srv/www/* /data/srv/www/ 2>/dev/null || true
echo "/data/srv/www /srv/www none bind 0 0" | sudo tee -a /etc/fstab
sudo mount -a

# ---------------------------------------------------------------------------
# 4. Web server (Apache) — serves ISOs, the hauler fileserver, and this repo
# ---------------------------------------------------------------------------
sudo zypper --non-interactive install apache2
sudo sed -i -e 's/Options None/Options +Indexes/g' /etc/apache2/default-server.conf
sudo systemctl enable apache2 --now
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --reload

# ---------------------------------------------------------------------------
# 5. Virtualization (libvirt / KVM)
# ---------------------------------------------------------------------------
sudo systemctl stop packagekit.service
sudo zypper install -t pattern kvm_server kvm_tools
sudo zypper --non-interactive install virt-manager virt-viewer virt-install libguestfs bridge-utils

sudo systemctl enable libvirt-guests.service --now
sudo systemctl enable virtqemud.socket --now
sudo systemctl enable virtnetworkd.socket --now
sudo systemctl enable virtstoraged.socket --now

# ---------------------------------------------------------------------------
# 6. Network bridge for VMs
# ---------------------------------------------------------------------------
BRIDGE=$(ip link show type bridge up 2>/dev/null | grep -v docker | awk -F': ' '/^[0-9]+:/ {print $2; exit}')

if [ -z "$BRIDGE" ]; then
  PRIMARY_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
  CONN_NAME=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":${PRIMARY_IFACE}$" | cut -d: -f1)
  IP_CONFIG=$(nmcli -t -f IP4.ADDRESS connection show "${CONN_NAME}" | cut -d: -f2)
  GATEWAY=$(nmcli -t -f IP4.GATEWAY connection show "${CONN_NAME}" | cut -d: -f2)
  DNS=$(nmcli -t -f IP4.DNS connection show "${CONN_NAME}" | cut -d: -f2 | tr '\n' ' ')

  sudo nmcli connection add type bridge \
    con-name virbr0 ifname virbr0 \
    ipv4.method manual \
    ipv4.addresses "${IP_CONFIG}" \
    ipv4.gateway "${GATEWAY}" \
    ipv4.dns "${DNS}" \
    bridge.stp no

  sudo nmcli connection add type ethernet \
    con-name bridge-slave-${PRIMARY_IFACE} \
    ifname ${PRIMARY_IFACE} \
    master virbr0

  sudo nmcli connection up virbr0
  sudo nmcli connection delete "${CONN_NAME}"
fi

cat > /tmp/virbr0-net.xml << 'EOF'
<network>
  <name>virbr0</name>
  <forward mode="bridge"/>
  <bridge name="virbr0"/>
</network>
EOF
sudo virsh net-define /tmp/virbr0-net.xml
sudo virsh net-start virbr0
sudo virsh net-autostart virbr0
virsh net-list --all

# ---------------------------------------------------------------------------
# 7. OpenSUSE Leap 15.6 ISO (for building infra VMs)
#    Public bits are OK for the admin node and its VMs.
# ---------------------------------------------------------------------------
ISO_URL=https://download.opensuse.org/distribution/leap/15.6/iso/openSUSE-Leap-15.6-DVD-x86_64-Media.iso
ISO_NAME=openSUSE-Leap-15.6-DVD-x86_64-Media.iso
ISO_DIR=/srv/www/htdocs/images
ISO_MOUNT=/srv/www/htdocs/OS/openSUSE-Leap-15.6-DVD-x86_64-Media
OS_VARIANT=opensuse15.6

sudo mkdir -p "${ISO_DIR}" "${ISO_MOUNT}"

[ ! -f "${ISO_DIR}/${ISO_NAME}" ] \
  && { echo "Downloading Leap 15.6 ISO..."; sudo curl -L "${ISO_URL}" -o "${ISO_DIR}/${ISO_NAME}"; } \
  || echo "ISO already present."

echo "# ISO mounts" | sudo tee -a /etc/fstab
echo "${ISO_DIR}/${ISO_NAME} ${ISO_MOUNT} iso9660 defaults,ro 0 0" | sudo tee -a /etc/fstab
sudo mount -a

# ---------------------------------------------------------------------------
# 8. Deploy infra VMs
# ---------------------------------------------------------------------------
ADMIN_NODE_IP=$(ip -4 addr show virbr0 | grep -oP '(?<=inet )\d+\.\d+\.\d+\.\d+')

for VM_HOSTNAME in nuc-00-01 nuc-00-02; do
  sudo mkdir -p /var/lib/libvirt/images/${VM_HOSTNAME}
  sudo virt-install \
    --name ${VM_HOSTNAME} \
    --memory 4096 \
    --vcpus 4 \
    --disk path=/var/lib/libvirt/images/${VM_HOSTNAME}/${VM_HOSTNAME}.qcow2,size=40,format=qcow2 \
    --os-variant ${OS_VARIANT} \
    --network network=virbr0 \
    --graphics none \
    --location "http://${ADMIN_NODE_IP}/OS/openSUSE-Leap-15.6-DVD-x86_64-Media" \
    --extra-args "console=ttyS0 textmode=1 hostname=${VM_HOSTNAME}.enclave.kubernerdes.com" \
    --noautoconsole
done

# ---------------------------------------------------------------------------
# 9. Tools
# ---------------------------------------------------------------------------
sudo zypper --non-interactive install git vim curl wget iotop

# Clone this repo to the web root so it is accessible to all enclave nodes
sudo mkdir -p /srv/www/htdocs/enclave.kubernerdes.com
sudo git clone https://github.com/jradtke-rgs/enclave.kubernerdes.com.git \
  /srv/www/htdocs/enclave.kubernerdes.com

# kubectl
sudo tee /etc/zypp/repos.d/kubernetes.repo << 'EOF'
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repomd.xml.key
EOF
sudo zypper refresh
sudo zypper --non-interactive install kubectl

exit 0
