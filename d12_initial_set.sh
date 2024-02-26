#!/bin/bash

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi

# Step 1: Append the specified lines to /etc/profile and /root/.bashrc if not already present
BASH_COMPLETION_SNIPPET="if [ -f /etc/bash_completion ]; then
 . /etc/bash_completion
fi"

# Check if snippet is not already in /etc/profile and /root/.bashrc then append
for file in /etc/profile /root/.bashrc; do
  grep -qxF -- "$BASH_COMPLETION_SNIPPET" "$file" || echo "$BASH_COMPLETION_SNIPPET" >> "$file"
done

# Step 2: Install sudo if it's not installed
if ! command -v sudo &> /dev/null; then
    apt-get update
    apt-get install -y sudo
fi

# Step 3: create user and add user to sudo group and configure sudoers for passwordless sudo
USER="zoninp"

# Check if the user already exists
if id "$USER" &>/dev/null; then
    echo "User $USER already exists."
else
    useradd -m "$USER" # -m option creates the home directory, remove if not needed
fi

# Add user to sudo group and configure sudo for passwordless operation
if id "$USER" &>/dev/null; then
    /usr/sbin/usermod -aG sudo "$USER"
    echo "$USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99_$USER-nopasswd
    chmod 0440 /etc/sudoers.d/99_$USER-nopasswd
else
    echo "User $USER does not exist."
    exit 1
fi

# Step 4: Add existing public key to user's authorized_keys
PUBLIC_KEY_PATH="zoninp_bl.pub" # Adjust the path as necessary
USER_HOME=$(getent passwd "$USER" | cut -d: -f6)

if [ -f "$PUBLIC_KEY_PATH" ]; then
    mkdir -p "${USER_HOME}/.ssh"
    chmod 700 "${USER_HOME}/.ssh"
    touch "${USER_HOME}/.ssh/authorized_keys"
    chmod 600 "${USER_HOME}/.ssh/authorized_keys"
    cat "$PUBLIC_KEY_PATH" >> "${USER_HOME}/.ssh/authorized_keys"
    chown -R $USER:$USER "${USER_HOME}/.ssh"
else
    echo "Public key file does not exist at $PUBLIC_KEY_PATH."
    exit 1
fi

# Step 5: Disable password authentication for SSH
SSH_CONFIG_FILE="/etc/ssh/sshd_config"

# Ensure the line is present and set to 'no', adding it if not present
if ! grep -q "^PasswordAuthentication no" "$SSH_CONFIG_FILE"; then
    sed -i '/^PasswordAuthentication/c\PasswordAuthentication no' "$SSH_CONFIG_FILE"
    if ! grep -q "^PasswordAuthentication" "$SSH_CONFIG_FILE"; then
        echo "PasswordAuthentication no" >> "$SSH_CONFIG_FILE"
    fi
fi

# Additionally, handle the case where the line might be commented out
sed -i '/^#PasswordAuthentication/c\PasswordAuthentication no' "$SSH_CONFIG_FILE"

# Reload the SSH service to apply changes
systemctl reload sshd
