#!/bin/bash

# Atlas is the primary "infrastructure node" - it will run: bind, dhcp, tftp, http

# build box with minimal with SSH port open

# su -
zypper --non-interactive in sudo vim wget curl
echo 'mansible  ALL=(ALL) NOPASSWD: ALL' | tee /etc/sudoers.d/mansible-nopasswd-all

# Install DHCP/DNS using the following pattern:
zypper --non-interactive in -t pattern dhcp_dns_server

#### #### ####
## Setup BIND 
zypper --non-interactive in bind-utils
cp /etc/named.conf /etc/named.conf.$(date +%F)
# This is fugly
curl -o /etc/named.conf https://raw.githubusercontent.com/jradtke-rgs/enclave.kubernerdes.com/refs/heads/main/Files/$(uname -n)_etc_named.conf

case $(uname -n) in 
  nuc-00-01)
    for FILE in enclave.kubernerdes.com db-12.10.10.in-addr.arpa db-13.10.10.in-addr.arpa db-14.10.10.in-addr.arpa db-15.10.10.in-addr.arpa
    do
      curl -o /var/lib/named/master/$FILE https://raw.githubusercontent.com/jradtke-rgs/enclave.kubernerdes.com/refs/heads/main/Files/$FILE
    done
  ;;
esac

chown -R root:root /var/lib/named/master/*
#chmod 755 /var/lib/named/master; chmod 744 /var/lib/named/master/*
systemctl enable named --now

#### #### ####
## Setup DHCP
case $(uname -n) in 
  nuc-00-01)
    cp /etc/dhcpd.conf /etc/dhcpd.conf.$(date +%F)
    curl -o /etc/dhcpd.conf https://raw.githubusercontent.com/jradtke-rgs/enclave.kubernerdes.com/refs/heads/main/Files/nuc-00-01_etc_dhcpd.conf
    mkdir /etc/dhcpd.d/
    curl -o /etc/dhcpd.d/dhcpd-hosts.conf https://raw.githubusercontent.com/jradtke-rgs/enclave.kubernerdes.com/refs/heads/main/Files/nuc-00-01_etc_dhcpd.d_dhcpd-hosts.conf

  sed -i -e 's/DHCPD_INTERFACE=""/DHCPD_INTERFACE="eth0"/g' /etc/sysconfig/dhcpd
  systemctl enable dhcpd --now
  systemctl status dhcpd
  ;;
esac 

#### #### ####
## Install/configure SNMP
zypper install net-snmp
mv /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.$(date +%F)
curl -o /etc/snmp/snmpd.conf https:....
systemctl enable snmpd.service --now

#### #### ####
### Install kubectl
sudo tee /etc/zypp/repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.33/rpm/repomd.xml.key
EOF
sudo zypper refresh
sudo zypper --non-interactive in kubectl

#### #### ####
# Manage Firewall
TCP_PORTS="53 80 443"
for PORT in $TCP_PORTS
do 
  firewall-cmd --permanent --zone=public --add-port=${PORT}/tcp
done
UDP_PORTS="67 68 69 4011"
for PORT in $UDP_PORTS
do
  firewall-cmd --permanent --zone=public --add-port=${PORT}/udp
done

SERVICES="http https dns dhcp snmp"
for SERVICE in $SERVICES
do 
  firewall-cmd --permanent --zone=public --add-service=$SERVICE
done

firewall-cmd --reload
firewall-cmd --list-all

#### #### ####
### Install Ansible (future use)
zypper -n in ansible
