#!/bin/bash

# initial steps and copy key.pub for USER
# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root" 1>&2
  exit 1
fi


# Step 1: Append the specified lines to /etc/profile and /root/.bashrc
BASH_COMPLETION_SNIPPET="if [ -f /etc/bash_completion ]; then
 . /etc/bash_completion
fi"

echo "$BASH_COMPLETION_SNIPPET" >> /etc/profile
echo "$BASH_COMPLETION_SNIPPET" >> /root/.bashrc


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
    # Create the user without a home directory
    # Remove '-M' if you want to create a home directory for the user
    useradd -M "$USER"
fi

if id "$USER" &>/dev/null; then
    /usr/sbin/usermod -aG sudo "$USER"
    echo "$USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/99_$USER-nopasswd
else
    echo "User $USER does not exist."
    exit 1
fi

# Step 4: Add existing public key to user's authorized_keys
PUBLIC_KEY_PATH="zoninp_bl.pub"
if [ -f "$PUBLIC_KEY_PATH" ]; then
    su - $USER -c "mkdir -p ~/.ssh && chmod 700 ~/.ssh"
    su - $USER -c "touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
    su - $USER -c "cat $PUBLIC_KEY_PATH >> ~/.ssh/authorized_keys"
else
    echo "Public key file does not exist at $PUBLIC_KEY_PATH."
    exit 1
fi

# Step 5: Disable password authentication for SSH
SSH_CONFIG_FILE="/etc/ssh/sshd_config"

# Ensure the line is present and set to 'no', adding it if not present
if grep -q "^PasswordAuthentication" "$SSH_CONFIG_FILE"; then
    # Line present, ensure it is set to 'no'
    sed -i '/^PasswordAuthentication/c\PasswordAuthentication no' "$SSH_CONFIG_FILE"
else
    # Line not present, add it
    echo "PasswordAuthentication no" >> "$SSH_CONFIG_FILE"
fi

# Additionally, handle the case where the line might be commented out
if grep -q "^#PasswordAuthentication" "$SSH_CONFIG_FILE"; then
    sed -i '/^#PasswordAuthentication/c\PasswordAuthentication no' "$SSH_CONFIG_FILE"
fi

# Reload the SSH service to apply changes
systemctl reload sshd
