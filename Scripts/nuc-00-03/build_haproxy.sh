#!/bin/bash

sudo su -

# Open Ports
TCP_PORTS="9000 80 443 6443 11434 12000 9345"
for PORT in $TCP_PORTS
do 
  firewall-cmd --permanent --add-port=${PORT}/tcp
done
UDP_PORTS="9345"
for PORT in $UDP_PORTS
do
  firewall-cmd --permanent --add-port=${PORT}/udp
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

