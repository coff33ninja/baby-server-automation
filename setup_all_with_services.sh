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
SMB_USER=""
SMB_PASS=""
SMB_GROUP=""

# Function to get the server's IP address
get_server_ip() {
    # Get the local IP address
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
if ! systemctl is-active --quiet cockpit.socket; then
    echo "Setting up Cockpit..."
    sudo systemctl enable --now cockpit.socket
    sudo systemctl start cockpit.socket
else
    echo "Cockpit is already installed and running."
fi

# 4. Install Node.js and npm
if ! node -v &>/dev/null; then
    echo "Installing Node.js and npm..."
    curl -fsSL https://deb.nodesource.com/setup_${NODE_VERSION} | sudo -E bash -
    sudo apt install -y nodejs
    echo "Node.js version: $(node -v)"
    echo "npm version: $(npm -v)"
else
    echo "Node.js and npm are already installed."
fi

# 5. Set up SMB (Samba)
# Function to list users from /home/ and check if the user is in the root group
get_home_users() {
    USERS=$(ls /home/)
    echo "Available users based on /home/ directory:"
    echo "$USERS"
}

# Function to create SMB groups if they don't exist
create_samba_groups() {
    if ! getent group samba > /dev/null; then
        echo "Creating samba group..."
        sudo groupadd samba
    fi
    if ! getent group smb > /dev/null; then
        echo "Creating smb group..."
        sudo groupadd smb
    fi
}

# Function to check if the user is in the root group
check_user_in_root_group() {
    local user=$1
    if groups "$user" | grep -w "root" > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Function to handle SMB user creation or selection
select_smb_user() {
    get_home_users

    read -p "Enter the username to be used for Samba (or type a new user): " SMB_USER

    # Check if user exists in /home/
    if [ -d "/home/$SMB_USER" ]; then
        echo "User $SMB_USER exists."
        
        # Check if the user is in the root group
        if ! check_user_in_root_group "$SMB_USER"; then
            echo "User $SMB_USER is not in the root group. Please provide admin access to proceed."
            sudo -v
        fi
    else
        echo "User $SMB_USER does not exist, creating new user."

        read -sp "Enter password for $SMB_USER: " SMB_PASS
        echo ""
        
        # Create new user if doesn't exist
        sudo useradd -m -s /bin/bash "$SMB_USER"
        echo "$SMB_USER:$SMB_PASS" | sudo chpasswd
        # Add user to samba and smb groups
        sudo usermod -aG samba,smb "$SMB_USER"
    fi
}

# Create necessary Samba groups
create_samba_groups

# Select or create SMB user
select_smb_user

# Now proceed with the rest of the script where you use $SMB_USER for SMB share setup
# For example, you could continue to configure the SMB share directory:
sudo mkdir -p /home/$SMB_USER/smb_share
sudo chown -R $SMB_USER:smb /home/$SMB_USER/smb_share
sudo chmod 770 /home/$SMB_USER/smb_share

# Configure Samba (SMB share) with required security settings
sudo smbpasswd -a $SMB_USER <<EOF
$SMB_PASS
$SMB_PASS
EOF

# Edit smb.conf to disable guest access and require authentication
sudo tee -a /etc/samba/smb.conf > /dev/null <<EOF
[$SMB_USER]
   path = /home/$SMB_USER/smb_share
   valid users = $SMB_USER
   read only = no
   guest ok = no
   create mask = 0775
   directory mask = 0775
EOF

# Restart Samba service to apply changes
sudo systemctl restart smbd

echo "SMB share for $SMB_USER is set up with authentication required!"

# 6. Set up HFS    
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
else
    echo "HFS is already installed and running."
fi

# 7. Set up UpSnap
if ! systemctl is-active --quiet upsnap; then
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
else
    echo "UpSnap is already installed and running."
fi

# 8. Set up iVentoy
if ! systemctl is-active --quiet iventoy; then
    echo "Setting up iVentoy..."
    wget -O /tmp/iventoy.tar.gz $IVENTOY_URL
    tar -xzf /tmp/iventoy.tar.gz -C /tmp/
    cd /tmp/iventoy-* || exit

    # Run iventoy.sh instead of install.sh
    echo "Running iVentoy setup..."
    sudo bash ./iventoy.sh start
    cd -
else
    echo "iVentoy is already installed and running."
fi

# 9. Optional: Set up Tailscale if user chose to install it
if [[ "$INSTALL_TAILSCALE" == "y" || "$INSTALL_TAILSCALE" == "Y" ]]; then
    echo "Setting up Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    sudo tailscale up --authkey=$TAILSCALE_AUTH_KEY
    tailscale status
else
    echo "Tailscale installation skipped."
fi

# 10. Configure Netdata
if ! systemctl is-active --quiet netdata; then
    echo "Setting up Netdata..."
    sudo systemctl enable netdata
    sudo systemctl start netdata
else
    echo "Netdata is already installed and running."
fi

# 11. Optional: Expose services via Tailscale Funnel (if Tailscale is installed)
if [[ "$INSTALL_TAILSCALE" == "y" || "$INSTALL_TAILSCALE" == "Y" ]]; then
    echo "Exposing services via Tailscale Funnel..."
    tailscale serve https / --port=443
    tailscale serve http://localhost:8090 --port=8090 # UpSnap
    tailscale serve http://localhost:8080 --port=8080 # HFS
    tailscale serve http://localhost:19999 --port=19999 # Netdata
fi

# End Note
echo "Installation complete!"
echo "Access the following services using your server's IP address ($SERVER_IP):"
echo "HFS: http://$SERVER_IP:8080"
echo "UpSnap: http://$SERVER_IP:8090"
echo "Netdata: http://$SERVER_IP:19999"
echo "SMB Share: smb://$SERVER_IP/$SMB_USER"
echo "Cockpit: http://$SERVER_IP:9090"
