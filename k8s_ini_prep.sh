#!/bin/bash

# Check if the script is being run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Exiting..."
  exit 1
fi

# Request the username for non-root user
read -p "Enter the username for kubectl completion setup: " USERNAME

# Check if the user exists
if ! id "$USERNAME" &>/dev/null; then
  echo "User $USERNAME does not exist. Exiting..."
  exit 1
fi

# Function to check if Kubernetes software is installed
check_k8s_software() {
  if command -v kubelet &>/dev/null && command -v kubeadm &>/dev/null && command -v kubectl &>/dev/null; then
    return 0  # All components are installed
  else
    return 1  # One or more components are missing
  fi
}

# Flag to track whether to run the kubectl completion setup
run_kubectl_completion="false"

# Check if Kubernetes software is installed
if check_k8s_software; then
  echo "Kubernetes software (kubelet, kubeadm, kubectl) is already installed."

  # Provide option to skip or reinstall
  while true; do
    read -p "Do you want to reinstall the Kubernetes software? (yes/no): " reinstall_choice
    case $reinstall_choice in
      yes|y)
        echo "Proceeding with Kubernetes software reinstallation..."
        run_kubectl_completion="true"
        break
        ;;
      no|n)
        echo "Skipping Kubernetes software installation..."
        break
        ;;
      *)
        echo "Please enter yes or no."
        ;;
    esac
  done

  if [ "$reinstall_choice" = "no" ] || [ "$reinstall_choice" = "n" ]; then
    echo "Skipping Kubernetes software installation."

    # Ask whether to skip kubectl completion setup
    while true; do
      read -p "Do you want to skip the kubectl completion setup? (yes/no): " skip_kubectl_completion_choice
      case $skip_kubectl_completion_choice in
        yes|y)
          echo "Skipping kubectl completion setup."
          break
          ;;
        no|n)
          echo "Proceeding with kubectl completion setup."
          run_kubectl_completion="true"
          break
          ;;
        *)
          echo "Please enter yes or no."
          ;;
      esac
    done
  else
    # Reinstallation case: kubectl completion should be executed
    run_kubectl_completion="true"
  fi
else
  echo "Kubernetes software is not installed. Proceeding with installation."
  run_kubectl_completion="true"
  install_k8s_software="true"
fi

# Install Kubernetes software if necessary
if [ "$install_k8s_software" = "true" ]; then


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
    $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" > /etc/apt/sources.list.d/docker.list

  # Update package index and install containerd
  apt update
  apt install -y containerd.io

  # Create containerd configuration directory if it doesn't exist
  mkdir -p /etc/containerd

  # Backup existing containerd configuration if present
  [ -f /etc/containerd/config.toml ] && cp /etc/containerd/config.toml /etc/containerd/config.toml.bac

  # Generate default containerd configuration
  containerd config default > /etc/containerd/config.toml

  # Edit containerd configuration to use systemd cgroup
  sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

  # Restart containerd to apply changes
  systemctl restart containerd

  # Install Kubernetes v1.31 packages
  apt update
  apt install -y apt-transport-https ca-certificates curl gpg
  curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' > /etc/apt/sources.list.d/kubernetes.list
  apt-get update
  apt-get install -y kubelet kubeadm kubectl
  apt-mark hold kubelet kubeadm kubectl
  systemctl enable --now kubelet
fi

# Run kubectl completion setup if required
if [ "$run_kubectl_completion" = "true" ]; then
  echo "Setting up kubectl completion..."

  # Set up kubectl completion for root
  echo "Setting up kubectl completion for root user..."

  # Create ~/.kube directory for root if it doesn't exist
  mkdir -p /root/.kube

  # Add kubectl completion for the current shell
  source <(kubectl completion bash)

  # Write kubectl completion script to ~/.kube/completion.bash.inc
  kubectl completion bash > /root/.kube/completion.bash.inc

  # Ensure .bash_profile exists for root and append completion setup
  if [ ! -f /root/.bash_profile ]; then
    touch /root/.bash_profile
  fi

  grep -qxF 'source /root/.kube/completion.bash.inc' /root/.bash_profile || echo "
  # kubectl shell completion
  source /root/.kube/completion.bash.inc
  " >> /root/.bash_profile

  # Source the updated .bash_profile to apply completion in the current shell
  source /root/.bash_profile

  # Set up kubectl completion for non-root user $USERNAME
  echo "Setting up kubectl completion for $USERNAME..."

  # Create ~/.kube directory for the non-root user if it doesn't exist
  su - $USERNAME -c 'mkdir -p ~/.kube'

  # Add kubectl completion for the current shell for non-root user
  su - $USERNAME -c 'source <(kubectl completion bash)'

  # Write kubectl completion script to ~/.kube/completion.bash.inc for non-root user
  su - $USERNAME -c 'kubectl completion bash > ~/.kube/completion.bash.inc'

  # Ensure .bash_profile exists for non-root user and append completion setup
  su - $USERNAME -c '[ ! -f ~/.bash_profile ] && touch ~/.bash_profile'
  su - $USERNAME -c 'grep -qxF "source ~/.kube/completion.bash.inc" ~/.bash_profile || echo "
  # kubectl shell completion
  source ~/.kube/completion.bash.inc
  " >> ~/.bash_profile'

  # Source the updated .bash_profile to apply completion in the current shell for non-root user
  su - $USERNAME -c 'source ~/.bash_profile'

  echo "Kubectl completion setup for both root and $USERNAME is complete."
else
  echo "Kubectl completion setup was skipped."
fi

# Pause and offer options to exit or execute kubeadm init --dry-run
while true; do
  echo "Choose an option:"
  echo "1) Exit"
  echo "2) Execute 'kubeadm init --dry-run'"
  echo "3) Join an existing Kubernetes cluster"
  read -p "Enter your choice [1-3]: " choice

  case $choice in
    1)
      echo "Exiting..."
      exit 0
      ;;
    2)
      echo "Executing 'kubeadm init --dry-run'..."
      kubeadm init --dry-run

      # After dry-run, offer options to exit or execute kubeadm init for real
      while true; do
        echo "Dry-run completed. Choose an option:"
        echo "1) Exit"
        echo "2) Execute 'kubeadm init' for real"
        echo "3) Join an existing Kubernetes cluster"
        read -p "Enter your choice [1-3]: " post_dryrun_choice

        case $post_dryrun_choice in
          1)
            echo "Exiting..."
            exit 0
            ;;
          2)
            echo "Executing 'kubeadm init'..."
            kubeadm init

            # After kubeadm init, set up the kubeconfig for root
            echo "Setting up kubeconfig for root user..."
            mkdir -p $HOME/.kube
            cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
            chown $(id -u):$(id -g) $HOME/.kube/config

            # Set up kubeconfig for the non-root user $USERNAME
            echo "Setting up kubeconfig for $USERNAME..."
            su -c 'mkdir -p ~/.kube' $USERNAME
            cp -i /etc/kubernetes/admin.conf /home/$USERNAME/.kube/config
            chown $(id -u $USERNAME):$(id -g $USERNAME) /home/$USERNAME/.kube/config

            # Inform the user that everything was done successfully
            echo "Kubernetes initialization and configuration completed successfully!"
            exit 0
            ;;
          3)
            echo "Joining an existing Kubernetes cluster..."

            # Prompt user for join command and token
            read -p "Enter the kubeadm join command (e.g., kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>): " join_command

            # Execute the provided join command
            eval $join_command

            # After join, set up the kubeconfig for root
            echo "Setting up kubeconfig for root user..."
            mkdir -p $HOME/.kube
            cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
            chown $(id -u):$(id -g) $HOME/.kube/config

            # Set up kubeconfig for the non-root user $USERNAME
            echo "Setting up kubeconfig for $USERNAME..."
            su -c 'mkdir -p ~/.kube' $USERNAME
            cp -i /etc/kubernetes/admin.conf /home/$USERNAME/.kube/config
            chown $(id -u $USERNAME):$(id -g $USERNAME) /home/$USERNAME/.kube/config

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
      read -p "Enter the kubeadm join command (e.g., kubeadm join <control-plane-ip>:6443 --token <token> --discovery-token-ca-cert-hash <hash>): " join_command

      # Execute the provided join command
      eval $join_command

      # After join, set up the kubeconfig for root
      echo "Setting up kubeconfig for root user..."
      mkdir -p $HOME/.kube
      cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
      chown $(id -u):$(id -g) $HOME/.kube/config

      # Set up kubeconfig for the non-root user $USERNAME
      echo "Setting up kubeconfig for $USERNAME..."
      su -c 'mkdir -p ~/.kube' $USERNAME
      cp -i /etc/kubernetes/admin.conf /home/$USERNAME/.kube/config
      chown $(id -u $USERNAME):$(id -g $USERNAME) /home/$USERNAME/.kube/config

      # Inform the user that everything was done successfully
      echo "Successfully joined the existing Kubernetes cluster and configured kubeconfig!"
      exit 0
      ;;
    *)
      echo "Invalid choice. Please enter 1, 2, or 3."
      ;;
  esac
done
