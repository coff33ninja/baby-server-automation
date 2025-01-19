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

# Install Cockpit applications from GitHub
echo "Installing Cockpit applications from GitHub..."

# Cockpit applications with GitHub links
declare -A cockpit_packages=(
    # ["cockpit-cloudflared"]="https://github.com/spotsnel/cockpit-cloudflared/releases/download/v0.0.2/cockpit-cloudflared-v0.0.2-1.fc38.noarch.rpm"
    # ["cockpit-tailscale"]="https://github.com/spotsnel/cockpit-tailscale/releases/download/v0.0.6/cockpit-tailscale-v0.0.6.6.gb7dbce5-1.el9.noarch.rpm"
    ["cockpit-sensors"]="https://github.com/ocristopfer/cockpit-sensors/releases/download/1.1/cockpit-sensors.deb"
    # ["cockpit-benchmark"]="https://github.com/45Drives/cockpit-benchmark/releases/download/v2.1.1/cockpit-benchmark_2.1.1-1focal_all.deb"
    ["cockpit-navigator"]="https://github.com/45Drives/cockpit-navigator/releases/download/v0.5.10/cockpit-navigator_0.5.10-1focal_all.deb"
    ["cockpit-file-sharing"]="https://github.com/45Drives/cockpit-file-sharing/releases/download/v4.2.8/cockpit-file-sharing_4.2.8-1focal_all.deb"
    # ["cockpit-zfs-manager"]="https://github.com/45Drives/cockpit-zfs-manager/releases/download/v1.3.1/cockpit-zfs-manager_1.3.1-1focal_all.deb"
    ["cockpit-session-recording"]="https://github.com/Scribery/cockpit-session-recording/releases/download/17/cockpit-session-recording-17.tar.xz"
    ["cockpit-files"]="https://github.com/cockpit-project/cockpit-files/releases/download/14/cockpit-files-14.tar.xz"
    ["cockpit-podman"]="https://github.com/cockpit-project/cockpit-podman/releases/download/99/cockpit-podman-99.tar.xz"
    ["cockpit-ostree"]="https://github.com/cockpit-project/cockpit-ostree/releases/download/206/cockpit-ostree-206.tar.xz"
)

for pkg in "${!cockpit_packages[@]}"; do
    echo "Installing $pkg..."

    # Determine file extension
    file_url="${cockpit_packages[$pkg]}"
    file_name=$(basename "$file_url")

    # Download the package
    wget -q "$file_url" -O "/tmp/$file_name"

    # Install based on file type
    case "$file_name" in
        *.rpm)
            # Convert .rpm to .deb if needed, or install via rpm
            echo "Installing RPM package: $file_name"
            sudo dnf install -y "/tmp/$file_name"  # Use dnf for RPM installations
            ;;
        *.deb)
            echo "Installing DEB package: $file_name"
            sudo dpkg -i "/tmp/$file_name"
            sudo apt-get install -f -y  # Fix dependencies if needed
            ;;
        *.tar.xz)
            # Extract tar.xz files and attempt to install them
            echo "Extracting and installing TAR.XZ package: $file_name"
            sudo tar -xvf "/tmp/$file_name" -C /opt  # Extract to /opt
            ;;
        *)
            echo "Unsupported package type: $file_name"
            ;;
    esac

    # Clean up
    rm "/tmp/$file_name"
done


# 3. Enable and start Cockpit
if ! systemctl is-active --quiet cockpit.socket; then
    echo "Setting up Cockpit..."
    sudo systemctl enable --now cockpit.socket
    sudo systemctl start cockpit.socket
else
    echo "Cockpit is already installed and running."
fi

# Ensure NetworkManager is installed and configured for Cockpit
echo "Ensuring NetworkManager is installed and configured for Cockpit..."
if ! dpkg -l | grep -q network-manager; then
    echo "Installing NetworkManager..."
    sudo apt-get install -y network-manager
fi

# Modify Netplan configuration to use NetworkManager as renderer
echo "Configuring Netplan to use NetworkManager..."
NETPLAN_CONFIG_FILE="/etc/netplan/01-netcfg.yaml"

# Check if the Netplan config file exists before modifying
if [ -f "$NETPLAN_CONFIG_FILE" ]; then
    sudo sed -i 's/renderer: .*/renderer: NetworkManager/' "$NETPLAN_CONFIG_FILE"
    echo "Netplan configured to use NetworkManager."
else
    echo "Netplan config file not found. Skipping renderer modification."
fi

# Apply Netplan configuration
echo "Applying Netplan configuration..."
sudo netplan apply

# Restart NetworkManager and Cockpit to apply changes
echo "Restarting NetworkManager and Cockpit..."
sudo systemctl restart NetworkManager
sudo systemctl restart cockpit.socket

echo "Cockpit and NetworkManager configured successfully."

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
    # Check if the user is part of the 'root' group by parsing /etc/group
    if grep -q "\b$user\b" /etc/group | grep -w "root" > /dev/null; then
        return 0  # User is in the root group
    else
        return 1  # User is not in the root group
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

# 6. Install HFS via Node.js (using npx)
# Ensure Node.js is installed
install_hfs_nodejs() {
    echo "Installing HFS via Node.js..."

    # Update package list and install dependencies
    sudo apt update
    sudo apt install -y nodejs npm || { echo "Failed to install Node.js"; exit 1; }

    # Verify npx installation
    if ! command -v npx &>/dev/null; then
        echo "npx is not installed, installing npx..."
        sudo npm install -g npx || { echo "Failed to install npx"; exit 1; }
    fi

    # Create systemd service for HFS using npx
    sudo tee /etc/systemd/system/hfs.service > /dev/null <<EOF
[Unit]
Description=HFS
After=network.target

[Service]
Type=simple
Restart=always
ExecStart=/usr/bin/npx -y hfs@latest

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd and start HFS service
    sudo systemctl daemon-reload
    sudo systemctl enable hfs
    sudo systemctl start hfs
}

install_hfs_nodejs

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
# Set installation and service paths
USER_HOME="/home/$USER"
IVENTOY_INSTALL_DIR="$USER_HOME/iventoy"
IVENTOY_SERVICE_FILE="/etc/systemd/system/iventoy.service"

# Check if iVentoy is installed
check_iventoy_installed() {
    if [ -f "$IVENTOY_INSTALL_DIR/iventoy.sh" ]; then
        echo "iVentoy is already installed."
        return 0
    else
        echo "iVentoy is not installed."
        return 1
    fi
}

# Install iVentoy if not already installed
if ! check_iventoy_installed; then
    echo "Downloading and installing iVentoy..."
    wget -O /tmp/iventoy.tar.gz $IVENTOY_URL
    tar -xzf /tmp/iventoy.tar.gz -C /tmp/
    mv /tmp/iventoy-* $IVENTOY_INSTALL_DIR
    chown -R $USER:$USER $IVENTOY_INSTALL_DIR
    echo "iVentoy installed successfully."
else
    echo "Skipping iVentoy installation."
fi

# Create systemd service for iVentoy
echo "Creating systemd service for iVentoy..."
sudo tee $IVENTOY_SERVICE_FILE > /dev/null <<EOF
[Unit]
Description=iVentoy Service
After=network.target

[Service]
Type=simple
ExecStart=$IVENTOY_INSTALL_DIR/iventoy.sh start
Restart=always
User=$USER
WorkingDirectory=$IVENTOY_INSTALL_DIR
Environment=PATH=/usr/bin:/usr/local/bin

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable the service
sudo systemctl daemon-reload
sudo systemctl enable iventoy
sudo systemctl start iventoy

echo "iVentoy service created and started successfully."

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
    tailscale funnel https+insecure://localhost:443
    tailscale serve http://localhost:8090 --port=8090 # UpSnap
    tailscale serve http://localhost:80 --port=80 # HFS
    tailscale serve http://localhost:19999 --port=19999 # Netdata
fi

# End Note
echo "Installation complete!"
echo "Access the following services using your server's IP address ($SERVER_IP):"
echo "HFS: http://$SERVER_IP"
echo "UpSnap: http://$SERVER_IP:8090"
echo "IVentoy: http://$SERVER_IP:26000"
echo "Netdata: http://$SERVER_IP:19999"
echo "SMB Share: smb://$SERVER_IP/$SMB_USER"
echo "Cockpit: http://$SERVER_IP:9090"
