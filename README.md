# Making `setup_all_with_services.sh` Executable in Ubuntu

## Steps to Make the Script Executable

### 1. **Download the Script**
Use `wget` to download the script from the GitHub repository:
```bash
wget https://raw.githubusercontent.com/coff33ninja/baby-server-automation/main/setup_all_with_services.sh
```

### 2. **Set Execute Permissions**
Grant execute permissions to the script:
```bash
chmod +x setup_all_with_services.sh
```

### 3. **Run the Script**
Execute the script by running:
```bash
./setup_all_with_services.sh
```

### 4. **Alternative: Specify Full Path**
If the script is located in another directory, specify the full path when making it executable and running it:
```bash
chmod +x /path/to/setup_all_with_services.sh
/path/to/setup_all_with_services.sh
```

### 5. **Move to a System-Wide Location (Optional)**
To make the script accessible system-wide, move it to a directory in your `$PATH`, like `/usr/local/bin`:
```bash
sudo mv setup_all_with_services.sh /usr/local/bin/setup_all_with_services
sudo chmod +x /usr/local/bin/setup_all_with_services
```
You can now run the script from anywhere using:
```bash
setup_all_with_services
```

## Handling Script Replacement
If the script is downloaded to a specific location and needs to be replaced, follow these steps:

### Move Old Script to `old` Folder with a Sequential Name
1. Ensure the `old` directory exists in the script's location:
   ```bash
   mkdir -p /path/to/scripts/old
   ```

2. If a previous version of the script exists, move it to the `old` folder and rename it with a sequential number:
   ```bash
   if [ -f /path/to/scripts/setup_all_with_services.sh ]; then
       count=$(ls /path/to/scripts/old | grep 'setup_all_with_services_' | wc -l)
       mv /path/to/scripts/setup_all_with_services.sh /path/to/scripts/old/setup_all_with_services_$((count + 1)).sh
   fi
   ```

3. Place the new script in the desired location:
   ```bash
   mv setup_all_with_services.sh /path/to/scripts/
   chmod +x /path/to/scripts/setup_all_with_services.sh
   ```

### Automate This Process
To automate these steps, create a helper script:
```bash
#!/bin/bash

SCRIPT_DIR="/path/to/scripts"
OLD_DIR="$SCRIPT_DIR/old"
SCRIPT_NAME="setup_all_with_services.sh"

# Ensure the `old` directory exists
mkdir -p "$OLD_DIR"

# Move existing script to `old` with a sequential name
if [ -f "$SCRIPT_DIR/$SCRIPT_NAME" ]; then
    count=$(ls "$OLD_DIR" | grep "${SCRIPT_NAME%.*}_" | wc -l)
    mv "$SCRIPT_DIR/$SCRIPT_NAME" "$OLD_DIR/${SCRIPT_NAME%.*}_$((count + 1)).${SCRIPT_NAME##*.}"
fi

# Move the new script into place
mv "$SCRIPT_NAME" "$SCRIPT_DIR/"
chmod +x "$SCRIPT_DIR/$SCRIPT_NAME"
```
Save this script, make it executable (`chmod +x`), and use it whenever you update the script.

