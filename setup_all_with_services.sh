#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define variables
NODE_VERSION="16.x"
HFS_VERSION="0.55.4"
HFS_URL="https://github.com/rejetto/hfs/releases/download/v${HFS_VERSION}/hfs-linux-x64-${HFS_VERSION}.zip"
HFS_BINARY="/usr/local/bin/hfs"
HFS_CWD="/var/lib/hfs"
UPSNAP_VERSION="4.5.1"
UPSNAP_URL="https://github.com/seriousm4x/UpSnap/releases/download/${UPSNAP_VERSION}/UpSnap_${UPSNAP_VERSION}_linux_amd64.zip"
IVENTOY_VERSION="1.0.20"
IVENTOY_URL="https://github.com/ventoy/PXE/releases/download/v${IVENTOY_VERSION}/iventoy-${IVENTOY_VERSION}-linux-free.tar.gz"
SMB_USER="shareduser"
SMB_PASS="sharedpassword"
TAILSCALE_AUTH_KEY="your-tailscale-auth-key" # Replace with your actual key from Tailscale admin console

echo "Starting the full system setup..."

# 1. Update the system
echo "Updating the system..."
sudo apt update && sudo apt upgrade -y

# 2. Install essential tools
echo "Installing essential tools..."
sudo apt install -y curl wget git unzip tar nmap cockpit samba netdata

# 3. Enable and start Cockpit
echo "Setting up Cockpit..."
sudo systemctl enable --now cockpit.socket
sudo systemctl start cockpit.socket

# 4. Install Node.js and npm
echo "Installing Node.js and npm..."
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | sudo -E bash -
sudo apt install -y nodejs
echo "Node.js version: $(node -v)"
echo "npm version: $(npm -v)"

# 5. Set up HFS
echo "Setting up HFS..."
sudo adduser --system hfs
sudo mkdir -p $HFS_CWD
wget -O /tmp/hfs.zip $HFS_URL
unzip /tmp/hfs.zip -d /tmp/hfs
sudo mv /tmp/hfs/hfs $HFS_BINARY
sudo mv /tmp/hfs/plugins $HFS_CWD/plugins
sudo chown -R hfs:nogroup $HFS_CWD
sudo setcap CAP_NET_BIND_SERVICE=+eip $HFS_BINARY

sudo tee /etc/systemd/system/hfs.service > /dev/null <<EOF
[Unit]
Description=HFS
After=network.target

[Service]
Type=simple
User=hfs
Restart=always
ExecStart=$HFS_BINARY --cwd $HFS_CWD

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable hfs
sudo systemctl start hfs

# 6. Set up UpSnap
echo "Setting up UpSnap..."
wget -O /tmp/upsnap.zip $UPSNAP_URL
unzip /tmp/upsnap.zip -d /tmp/upsnap
sudo mv /tmp/upsnap/upsnap /usr/local/bin/upsnap
sudo setcap cap_net_raw=+ep /usr/local/bin/upsnap

sudo tee /etc/systemd/system/upsnap.service > /dev/null <<EOF
[Unit]
Description=UpSnap Wake-on-LAN Service
After=network.target

[Service]
ExecStart=/usr/local/bin/upsnap serve --http=0.0.0.0:8090
Restart=always
User=root
Environment=PATH=/usr/bin:/usr/local/bin

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable upsnap
sudo systemctl start upsnap

# 7. Set up iVentoy
echo "Setting up iVentoy..."
wget -O /tmp/iventoy.tar.gz $IVENTOY_URL
tar -xzf /tmp/iventoy.tar.gz -C /tmp/
cd /tmp/iventoy-* || exit
sudo bash ./install.sh
sudo bash ./iventoy.sh start
cd -

# 8. Configure SMB (Samba)
echo "Setting up SMB..."
sudo smbpasswd -a $SMB_USER <<EOF
$SMB_PASS
$SMB_PASS
EOF

sudo tee -a /etc/samba/smb.conf > /dev/null <<EOF
[iventoy]
   path = /opt/iventoy
   valid users = $SMB_USER
   read only = no

[hfs]
   path = $HFS_CWD
   valid users = $SMB_USER
   read only = no
EOF

sudo systemctl restart smbd

# 9. Set up Tailscale
echo "Setting up Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --authkey=$TAILSCALE_AUTH_KEY
tailscale status

# 10. Configure Netdata
echo "Setting up Netdata..."
sudo systemctl enable netdata
sudo systemctl start netdata

# 11. Optional: Expose services via Tailscale Funnel
echo "Exposing services via Tailscale Funnel..."
tailscale serve https / --port=443
tailscale serve http://localhost:8090 --port=8090 # UpSnap
tailscale serve http://localhost:8080 --port=8080 # HFS
tailscale serve http://localhost:19999 --port=19999 # Netdata

echo "All services have been set up successfully!"
echo "HFS is available on port 8080."
echo "UpSnap is available on port 8090."
echo "Netdata is available on port 19999."
echo "SMB shares are available for $SMB_USER on 'iventoy' and 'hfs' directories."
