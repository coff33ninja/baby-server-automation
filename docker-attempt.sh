#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define variables
COMPOSE_FILE_PATH="/opt/docker-compose.yml"
NODE_VERSION="16.x"
HFS_VERSION="0.55.4"
HFS_URL="https://github.com/rejetto/hfs/releases/download/v${HFS_VERSION}/hfs-linux-x64-${HFS_VERSION}.zip"
HFS_BINARY="/usr/local/bin/hfs"
HFS_CWD="/var/lib/hfs"
SMB_USER=""
SMB_PASS=""
SMB_GROUP=""

# Function to get the server's IP address
get_server_ip() {
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo "Your server's IP address is: $SERVER_IP"
    echo "You can access the services through this IP address."
    echo ""
}

# Prompt for IP address display
echo "Fetching the server's IP address..."
get_server_ip

# Prompt for Tailscale installation
read -p "Do you want to install Tailscale? (y/n): " INSTALL_TAILSCALE
if [[ "$INSTALL_TAILSCALE" == "y" || "$INSTALL_TAILSCALE" == "Y" ]]; then
    read -p "Please enter your Tailscale Auth Key: " TAILSCALE_AUTH_KEY
fi

# Summary of services that will be installed
echo "This script will install the following services:"
echo "1. Cockpit"
echo "2. Node.js and npm"
echo "3. HFS (HTTP File Server)"
echo "4. UpSnap (Wake-on-LAN)"
echo "5. iVentoy"
echo "6. Netdata"
echo "7. Tailscale (Optional)"
echo "8. Samba (SMB shares)"
echo "9. Docker, Docker Compose, and Docker CLI"
echo ""
read -p "Do you want to proceed with the installation? (y/n): " PROCEED_INSTALLATION
if [[ "$PROCEED_INSTALLATION" != "y" && "$PROCEED_INSTALLATION" != "Y" ]]; then
    echo "Installation aborted."
    exit 0
fi

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

# 4. Install Node.js and npm
echo "Installing Node.js and npm..."
curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | sudo -E bash -
sudo apt install -y nodejs

echo "Node.js version: $(node -v)"
echo "npm version: $(npm -v)"

# 5. Install Docker, Docker Compose, and Docker CLI
echo "Installing Docker, Docker Compose, and Docker CLI..."
sudo apt install -y ca-certificates gnupg

# Add Docker's official GPG key
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up the Docker repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker packages
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add current user to the docker group
sudo usermod -aG docker $USER

# Verify Docker installation
echo "Docker version: $(docker --version)"
echo "Docker Compose version: $(docker compose version)"

# Start and enable Docker service
sudo systemctl enable --now docker

# Test Docker installation
docker run hello-world || echo "Docker test failed. Check your installation."

# 6. Create Docker Compose file
echo "Creating Docker Compose file for iVentoy and UpSnap..."
sudo mkdir -p /opt
cat << EOF | sudo tee $COMPOSE_FILE_PATH
version: "3.9"

services:
  iventoy:
    network_mode: host
    image: ziggyds/iventoy:latest
    container_name: iventoy
    restart: always
    privileged: true
    ports:
      - 26000:26000
      - 16000:16000
      - 10809:10809
      - 67:67/udp
      - 69:69/udp
    volumes:
      - isos:/app/iso
      - config:/app/data
      - /var/log/iventoy:/app/log
    environment:
      - AUTO_START_PXE=true

  upsnap:
    container_name: upsnap
    image: ghcr.io/seriousm4x/upsnap:4
    network_mode: host
    restart: unless-stopped
    volumes:
      - /opt/upsnap/data:/app/pb_data
    ports:
      - 8090:8090
    environment:
      - TZ=Europe/Berlin
      - UPSNAP_INTERVAL=@every 10s
      - UPSNAP_SCAN_RANGE=192.168.1.0/24
      - UPSNAP_SCAN_TIMEOUT=500ms
      - UPSNAP_PING_PRIVILEGED=true
      - UPSNAP_WEBSITE_TITLE=My Wake-on-LAN Manager
    dns:
      - 192.168.1.1

volumes:
  isos:
    external: true
  config:
    external: true

networks: {}
EOF

# 7. Run Docker Compose
echo "Starting Docker Compose services..."
sudo docker compose -f $COMPOSE_FILE_PATH up -d

# 8. Set up SMB (Samba)
echo "Setting up Samba..."
sudo mkdir -p /srv/samba/share
sudo chown -R $USER:$USER /srv/samba/share
sudo chmod 2770 /srv/samba/share

cat << EOF | sudo tee -a /etc/samba/smb.conf
[Share]
   path = /srv/samba/share
   browseable = yes
   writable = yes
   guest ok = no
   create mask = 0660
   directory mask = 2770
EOF

sudo systemctl restart smbd

# Final summary
echo "All services installed successfully. Please reboot the system to apply group changes."

echo "Services installed:"
echo "- Cockpit"
echo "- Node.js and npm"
echo "- Docker, Docker Compose, and Docker CLI"
echo "- Samba (SMB shares)"
echo "- HFS (HTTP File Server)"
echo "- UpSnap (Wake-on-LAN)"
echo "- iVentoy"
echo "- Netdata"

echo "Script execution complete."
