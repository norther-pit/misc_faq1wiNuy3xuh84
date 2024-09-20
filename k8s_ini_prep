#!/bin/bash

# Request the username for non-root user
read -p "Enter the username for kubectl completion setup: " USERNAME

# Check if the user exists
if ! id "$USERNAME" &>/dev/null; then
  echo "User $USERNAME does not exist. Exiting..."
  exit 1
fi

# sysctl params required by setup, params persist across reboots
if [ -f /etc/sysctl.d/k8s.conf ]; then
  echo "/etc/sysctl.d/k8s.conf already exists, proceeding..."
else
  cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward = 1
EOF
fi

# Apply sysctl params
sudo sysctl --system

# Add Docker's official GPG key
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index and install containerd
sudo apt update
sudo apt install -y containerd.io

# Create containerd configuration directory if it doesn't exist
sudo mkdir -p /etc/containerd

# Backup existing containerd configuration if present
[ -f /etc/containerd/config.toml ] && cp /etc/containerd/config.toml /etc/containerd/config.toml.bac

# Generate default containerd configuration
containerd config default > /etc/containerd/config.toml

# Edit containerd configuration to use systemd cgroup
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart containerd to apply changes
sudo systemctl restart containerd

# Install Kubernetes v1.31 packages
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl gpg
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

# Load kubectl completion code for bash into the current shell for root
echo "Setting up kubectl completion for root user..."
kubectl completion bash > /root/.kube/completion.bash.inc

# Ensure .bash_profile exists for root and add kubectl completion
if [ ! -f /root/.bash_profile ]; then
  touch /root/.bash_profile
fi

grep -qxF 'source /root/.kube/completion.bash.inc' /root/.bash_profile || echo "
# kubectl shell completion
source /root/.kube/completion.bash.inc
" >> /root/.bash_profile

# Load kubectl completion for the current shell of root user
source /root/.bash_profile


# Load kubectl completion code for bash into the current shell for non-root user $USERNAME
echo "Setting up kubectl completion for $USERNAME..."
sudo -u $USERNAME bash -c 'kubectl completion bash > ~/.kube/completion.bash.inc'

# Ensure .bash_profile exists for the non-root user and add kubectl completion
sudo -u $USERNAME bash -c '[ ! -f ~/.bash_profile ] && touch ~/.bash_profile'
sudo -u $USERNAME bash -c 'grep -qxF "source ~/.kube/completion.bash.inc" ~/.bash_profile || echo "
# kubectl shell completion
source ~/.kube/completion.bash.inc
" >> ~/.bash_profile'

# Load kubectl completion for the current shell of the non-root user
sudo -u $USERNAME bash -c 'source ~/.bash_profile'


# Pause and offer options to exit, execute kubeadm init --dry-run, or join an existing cluster
while true; do
  echo "Choose an option:"
  echo "1) Exit"
  echo "2) Execute 'sudo kubeadm init --dry-run'"
  echo "3) Join an existing Kubernetes cluster"
  read -p "Enter your choice [1-3]: " choice

  case $choice in
    1)
      echo "Exiting..."
      exit 0
      ;;
    2)
      echo "Executing 'sudo kubeadm init --dry-run'..."
      sudo kubeadm init --dry-run

      # After dry-run, offer options to exit or execute kubeadm init for real
      while true; do
        echo "Dry-run completed. Choose an option:"
        echo "1) Exit"
        echo "2) Execute 'sudo kubeadm init' for real"
        echo "3) Join an existing Kubernetes cluster"
        read -p "Enter your choice [1-3]: " post_dryrun_choice

        case $post_dryrun_choice in
          1)
            echo "Exiting..."
            exit 0
            ;;
          2)
            echo "Executing 'sudo kubeadm init'..."
            sudo kubeadm init

            # After kubeadm init, set up the kubeconfig for root
            echo "Setting up kubeconfig for root user..."
            mkdir -p $HOME/.kube
            sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
            sudo chown $(id -u):$(id -g) $HOME/.kube/config

            # Set up kubeconfig for the non-root user $USERNAME
            echo "Setting up kubeconfig for $USERNAME..."
            sudo -u $USERNAME bash -c 'mkdir -p $HOME/.kube'
            sudo cp -i /etc/kubernetes/admin.conf /home/$USERNAME/.kube/config
            sudo chown $(id -u $USERNAME):$(id -g $USERNAME) /home/$USERNAME/.kube/config

            # Inform the user that everything was done successfully
            echo "Kubernetes initialization and configuration completed successfully!"
            exit 0
            ;;
          3)
            echo "Joining an existing Kubernetes cluster..."

            # Prompt user for join command and token
            read -p "Enter the kubeadm join command (e.g., sudo kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>): " join_command

            # Execute the provided join command
            eval $join_command

            # After join, set up the kubeconfig for root
            echo "Setting up kubeconfig for root user..."
            mkdir -p $HOME/.kube
            sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
            sudo chown $(id -u):$(id -g) $HOME/.kube/config

            # Set up kubeconfig for the non-root user $USERNAME
            echo "Setting up kubeconfig for $USERNAME..."
            sudo -u $USERNAME bash -c 'mkdir -p $HOME/.kube'
            sudo cp -i /etc/kubernetes/admin.conf /home/$USERNAME/.kube/config
            sudo chown $(id -u $USERNAME):$(id -g $USERNAME) /home/$USERNAME/.kube/config

            # Inform the user that everything was done successfully
            echo "Successfully joined the existing Kubernetes cluster and configured kubeconfig!"
            exit 0
            ;;
          *)
            echo "Invalid choice. Please enter 1, 2, or 3."
            ;;
        esac
      done
      ;;
    3)
      echo "Joining an existing Kubernetes cluster..."

      # Prompt user for join command and token
      read -p "Enter the kubeadm join command (e.g., sudo kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>): " join_command

      # Execute the provided join command
      eval $join_command

      # After join, set up the kubeconfig for root
      echo "Setting up kubeconfig for root user..."
      mkdir -p $HOME/.kube
      sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
      sudo chown $(id -u):$(id -g) $HOME/.kube/config

      # Set up kubeconfig for the non-root user $USERNAME
      echo "Setting up kubeconfig for $USERNAME..."
      sudo -u $USERNAME bash -c 'mkdir -p $HOME/.kube'
      sudo cp -i /etc/kubernetes/admin.conf /home/$USERNAME/.kube/config
      sudo chown $(id -u $USERNAME):$(id -g $USERNAME) /home/$USERNAME/.kube/config

      # Inform the user that everything was done successfully
      echo "Successfully joined the existing Kubernetes cluster and configured kubeconfig!"
      exit 0
      ;;
    *)
      echo "Invalid choice. Please enter 1, 2, or 3."
      ;;
  esac
done
