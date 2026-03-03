#!/bin/bash

# Prereqs:  haproxy is installed/working/configured

sudo su -

# Install AWS client and other dependencies


if command -v aws &>/dev/null; then
  echo "AWS CLI is already installed: $(aws --version)"
else
  echo "AWS CLI not found — installing..."
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  rm -rf awscliv2.zip aws
fi
sudo zypper install python3-boto3

# Install certbot and required dependencies
sudo zypper --non-interactive install python3-certbot 

# Install Certbot DNS Route53
sudo zypper install python3-pip
pip3 install certbot-dns-route53

# Create the HAProxy certs directory
sudo mkdir -p /etc/haproxy/certs

# TODO:  ummm... where are the actual steps to request the cert.


# Create combined PEM for spark-e
sudo cat /etc/letsencrypt/live/spark-e.enclave.kubernerdes.com/fullchain.pem \
        /etc/letsencrypt/live/spark-e.enclave.kubernerdes.com/privkey.pem \
        > /etc/haproxy/certs/spark-e.enclave.kubernerdes.com.pem

sudo cat /etc/letsencrypt/live/spark-e-api.enclave.kubernerdes.com/fullchain.pem \
        /etc/letsencrypt/live/spark-e-api.enclave.kubernerdes.com/privkey.pem \
        > /etc/haproxy/certs/spark-e-api.enclave.kubernerdes.com.pem

# Set proper permissions
sudo chmod 600 /etc/haproxy/certs/*.pem
sudo chown haproxy:haproxy /etc/haproxy/certs/*.pem  # Adjust user if different

exit 0

# #####################
# AppArmor Update for Cert repo (manual steps at this point)
#  TODO: make this scripted as it will be universally applied
# #####################

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
