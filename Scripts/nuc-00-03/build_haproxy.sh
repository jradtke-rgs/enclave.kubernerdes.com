#!/bin/bash

sudo su -

# This script assumes you have already registered your node (using post_install.sh)
reg_node() {
SUSEConnect -e <reg_email> -r <reg_code>
SUSEConnect --product sle-module-basesystem/15.7/x86_64
SUSEConnect --product sle-module-server-applications/15.7/x86_64
# TODO - add a check to see whether HA is enabled and if not, enable it
#SUSEConnect --product sle-ha/15.7/x86_64 -r (add reg code for HA Extension)
}

# Open Ports
TCP_PORTS="9000 80 443 6443"
for PORT in $TCP_PORTS
do 
  firewall-cmd --permanent --add-port=${PORT}/tcp
done
firewll-cmd --reload

# using Keepalived for floating/VIP (and to future proof)
zypper -n in haproxy keepalived

# Allow keepalive to attach before interface is up/available
echo "net.ipv4.ip_nonlocal_bind = 1" | sudo tee -a /etc/sysctl.d/20_keepalive.conf
mv /etc/keepalived/keepalived.conf /etc/keepalived/keepalived.conf.orig
curl -o  /etc/keepalived/keepalived.conf https://raw.githubusercontent.com/jradtke-rgs/enclave.kubernerdes.com/refs/heads/main/Files/nuc-00-03/etc_keepalived_keepalived.conf
sdiff /etc/keepalived/keepalived.conf /etc/keepalived/keepalived.conf.orig
sudo systemctl enable keepalived --now
sleep 15; ip a s

cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.$(uuidgen | tr -d '-' | head -c 6)
curl -o /etc/haproxy/haproxy.cfg https://raw.githubusercontent.com/jradtke-rgs/enclave.kubernerdes.com/refs/heads/main/Files/nuc-00-03/etc_haproxy_haproxy.cfg
sudo systemctl enable haproxy --now

# Fix/update AppArmor (to allow my certificate file directory location)
  1. Check what HAProxy is actually failing on:
  sudo journalctl -u haproxy -n 20 --no-pager

  2. Confirm AppArmor is the culprit (EACCES even as root = AppArmor):
  sudo strace -e openat /usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg 2>&1 | grep -i 'pem\|EACCES\|ENOENT'

  3. Review the HAProxy AppArmor profile to see what paths are allowed:
  sudo cat /etc/apparmor.d/usr.sbin.haproxy

  4. Create the local override to allow cert directory access:
  sudo tee /etc/apparmor.d/local/usr.sbin.haproxy > /dev/null << 'EOF'
  # Allow HAProxy to read SSL certificates from /etc/haproxy/certs/
  /etc/haproxy/certs/** r,
  EOF

  5. Reload the AppArmor profile:
  sudo apparmor_parser -r /etc/apparmor.d/usr.sbin.haproxy

  6. Verify the config is now valid:
  sudo /usr/sbin/haproxy -c -f /etc/haproxy/haproxy.cfg

  7. Start the service:
  sudo systemctl start haproxy
