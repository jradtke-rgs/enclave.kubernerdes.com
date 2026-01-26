#!/bin/bash

# TODO:   May need to either make the post_install script specific to 15 vs 16, or add logic to do it in a single script

# Task: create an ssh key to use for this enclave
echo | ssh-keygen -trsa -b2048 -N '' -f ~/.ssh/id_rsa-kubernerdes

# Task: Configure SUDO
MYUSER=$(whoami)
echo "$MYUSER ALL=(ALL) NOPASSWD: ALL" | sudo tee /etc/sudoers.d/$MYUSER-sudo

# Task: disable power-saving
sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target

# Task: Install/configure web server
sudo zypper install httpd # While httpd package does not exist, zypper is pretty smart and pulls what it needs
# Allow Directory Browsing via Apache Web Server
sed -i -e 's/Options None/Options +Indexes/g' /etc/apache2/default-server.conf
sudo systemctl enable apache2 --now
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --reload

sudo zypper in git
sudo mkdir /srv/www/htdocs/enclave.kubernerdes.com
sudo git clone https://github.com/jradtke-rgs/enclave.kubernerdes.com.git /srv/www/htdocs/enclave.kubernerdes.com

# Task: install libvirt
# TODO: make this non-interactive.  Also might check before to see if already installed?
sudo systemctl stop packagekit.service
sudo zypper install -t pattern kvm_server kvm_tools
sudo zypper install virt-manager virt-viewer virt-install libguestfs bridge-utils

# Task: Enable Libvirt services
sudo systemctl enable libvirt-guests.service --now
sudo systemctl enable virtqemud.socket --now
sudo systemctl enable virtnetworkd.socket --now
sudo systemctl enable virtstoraged.socket --now

# Task: create a network bridge for the virtual machines (or.. if a bridge exists, figure out what it is)
# TODO: this needs to be tested
BRIDGE=$(ip link show type bridge up | grep -v 'docker' | awk -F': ' '/^[0-9]+:/ {print $2; exit}')
[ -z "$BRIDGE" ] && {
# Find the primary interface
PRIMARY_IFACE=$(ip route | grep default | awk '{print $5}' | head -n1)
echo "Primary interface: $PRIMARY_IFACE"

# Get current connection details
CONN_NAME=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":${PRIMARY_IFACE}$" | cut -d: -f1)
echo "Current connection: $CONN_NAME"

# Capture current IP configuration
IP_CONFIG=$(nmcli -t -f IP4.ADDRESS connection show "${CONN_NAME}" | cut -d: -f2)
GATEWAY=$(nmcli -t -f IP4.GATEWAY connection show "${CONN_NAME}" | cut -d: -f2)
DNS=$(nmcli -t -f IP4.DNS connection show "${CONN_NAME}" | cut -d: -f2 | tr '\n' ' ')

echo "Current IP: $IP_CONFIG"
echo "Gateway: $GATEWAY"
echo "DNS: $DNS"

# Create the bridge WITH the IP configuration
sudo nmcli connection add type bridge \
    con-name virbr0 \
    ifname virbr0 \
    ipv4.method manual \
    ipv4.addresses "${IP_CONFIG}" \
    ipv4.gateway "${GATEWAY}" \
    ipv4.dns "${DNS}" \
    bridge.stp no

# Add the primary interface as a bridge slave
sudo nmcli connection add type ethernet \
    con-name bridge-slave-${PRIMARY_IFACE} \
    ifname ${PRIMARY_IFACE} \
    master virbr0

# Bring up the bridge (this should preserve connectivity)
sudo nmcli connection up virbr0

# NOW delete the old connection
sudo nmcli connection delete "${CONN_NAME}"

# Verify
ip addr show virbr0
ip route
}

# Create libvirt network definition
cat > /tmp/virbr0-net.xml << 'EOF'
<network>
  <name>virbr0</name>
  <forward mode="bridge"/>
  <bridge name="virbr0"/>
</network>
EOF

# Define and start the network
sudo virsh net-define /tmp/virbr0-net.xml
sudo virsh net-start virbr0
sudo virsh net-autostart virbr0

# Verify
virsh net-list --all

# Task: configure second disk
# Ensure disk is not currently in-use
DATA_DEVICE=nvme0n1

if [ "$(sudo lsblk -f /dev/$DATA_DEVICE | wc -l)" -gt 2 ]; then
  echo "ERROR: Disk appears to have existing partitions. \n  Cannot proceed"; exit 9
else
  echo "NOTE: /dev/$DATA_DEVICE appears available for use."
fi

sudo parted -s /dev/$DATA_DEVICE mklabel gpt mkpart pri 2048s 100% set 1 lvm on
sudo pvcreate /dev/${DATA_DEVICE}p1
sudo vgcreate vg_data /dev/${DATA_DEVICE}p1

sudo lvcreate -L500g -nlv_libvirt_images vg_data
sudo mkfs.ext4 /dev/mapper/vg_data-lv_libvirt_images

sudo lvcreate -L100g -nlv_www vg_data
sudo mkfs.ext4 /dev/mapper/vg_data-lv_www

sudo cp /etc/fstab /etc/fstab-$(date +%F)
echo "# Managed devices and directories follow..." | sudo tee -a /etc/fstab

sudo mkdir -p /data/var/lib/libvirt/images/
echo "/dev/mapper/vg_data-lv_libvirt_images /data/var/lib/libvirt/images/ ext4 defaults 0 0" | sudo tee -a /etc/fstab
sudo mount -a
echo "/data/var/lib/libvirt/images/ /var/lib/libvirt/images/ none bind 0 0" | sudo tee -a /etc/fstab
sudo mount -a

mkdir -p /data/srv/www
echo "/dev/mapper/vg_data-lv_www /data/srv/www/ ext4 defaults 0 0" | sudo tee -a /etc/fstab
sudo mount -a
mv /srv/www/* /data/srv/www/
echo "/data/srv/www/ /srv/www none bind 0 0" | sudo tee -a /etc/fstab
sudo mount -a

# This is a multi-step process to download and mount the ISOS to be available as install source
sudo mkdir -p /srv/www/htdocs/OS/openSUSE-Leap-15.6-DVD-x86_64-Media /srv/www/htdocs/OS/Leap-16.0-offline-installer-x86_64.install
sudo mkdir -p /srv/www/htdocs/images/

# Task: Download ISO Image to build VMs and store in KVM images directory
SLES_VERSION=15
case $SLES_VERSION in
  16)
    ISO_DOWNLOAD=https://download.opensuse.org/distribution/leap/16.0/offline/Leap-16.0-offline-installer-x86_64.install.iso
    ISO_LOCATION=/srv/www/htdocs/images/Leap-16.0-offline-installer-x86_64.install.iso
    ISO_NAME=Leap-16.0-offline-installer-x86_64.install.iso
    OS_VARIANT=opensuse15.6
  ;;
  15)
    ISO_DOWNLOAD=https://download.opensuse.org/distribution/leap/15.6/iso/openSUSE-Leap-15.6-DVD-x86_64-Media.iso
    ISO_LOCATION=/srv/www/htdocs/images/openSUSE-Leap-15.6-DVD-x86_64-Media.iso
    OS_VARIANT=opensuse15.6
    ISO_NAME=openSUSE-Leap-15.6-DVD-x86_64-Media.iso
  ;;
esac

[ ! -f  ${ISO_LOCATION} ] && { echo "NOTE: downloading ISO"; curl -L ${ISO_DOWNLOAD} -O ${ISO_LOCATION};  } || { echo "NOTE: ISO already exists"; }
# https://download.opensuse.org/distribution/leap/15.6/iso/
INSTALL_DESTINATION=$(echo ${ISO_NAME} | sed 's/.iso$//g')
echo "# ISO Mounts follow..." | sudo tee -a /etc/fstab
echo "${ISO_LOCATION} /srv/www/htdocs/OS/${INSTALL_DESTINATION} iso9660 defaults 0 0" | sudo tee -a /etc/fstab
mount -a

# Task: install VM (nuc-00-01)
# Note:  I determined it is probably not a good idea, in the long run, to use capital letters in the hostname
# TODO:  I will need to reference a "local/enclave version of autoinst.xml"
VM_HOSTNAME=nuc-00-01
[ ! -d  /var/lib/libvirt/images/${VM_HOSTNAME} ] && { sudo mkdir /var/lib/libvirt/images/${VM_HOSTNAME}; } 
sudo virt-install \
  --name ${VM_HOSTNAME} \
  --memory 4096 \
  --vcpus 4 \
  --disk path=/var/lib/libvirt/images/${VM_HOSTNAME}/${VM_HOSTNAME}.qcow2,size=40,format=qcow2 \
  --os-variant ${OS_VARIANT} \
  --network network=virbr0 \
  --graphics none \
  --location http://10.10.12.10/OS/${INSTALL_DESTINATION} \
  --extra-args="console=ttyS0 textmode=1 inst.auto=http://10.10.12.10/enclave.kubernerdes.com/Files/${VM_HOSTNAME}-autoinst.xml ifcfg=eth0=10.10.12.8/22,10.10.12.1,8.8.8.8 hostname=${VM_HOSTNAME}.enclave.kubernerdes.com"


exit 0
vm_cleanup() {
sudo virsh destroy ${VM_HOSTNAME}
sudo virsh undefine ${VM_HOSTNAME}
sudo rm /var/lib/libvirt/images/${VM_HOSTNAME}/${VM_HOSTNAME}.qcow2
}

ifcfg=eth0=10.0.10.50/24,10.0.10.1,10.0.10.1,10.0.10.2
       └────┬────┘ └─────┬─────┘ └───┬───┘ └────┬────┘
         interface  IP/mask   gateway   DNS1    DNS2

