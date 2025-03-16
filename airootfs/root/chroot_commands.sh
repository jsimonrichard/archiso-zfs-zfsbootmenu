#!/bin/bash

set -e

# Copy and source the shared functions
export PROGRESS_FILE="/root/tmp/install_progress"
source /root/tmp/install_shared.sh

# Access environment variables passed from the host
source /root/tmp/install_env.sh  # We'll create this

check_required_vars "${COMMON_REQUIRED_VARS[@]}"

# Mount partitions
mount -a
zfs mount -a

if ! should_skip 8; then
    print_step "Initializing pacman keyring"
    pacman-key --init
    pacman-key --populate
    mark_completed 8
else
    print_step "Skipping pacman keyring initialization"
fi

if ! should_skip 9; then
    print_step "Setting zfs configs in chroot"
    zgenhostid $(hostid)
    mark_completed 9
else
    print_step "Skipping chroot zfs config"
fi

if ! should_skip 10; then
    print_step "Configuring mkinitcpio.conf"
    echo "Please:"
    echo "1. Add 'zfs' to MODULES=()"
    echo "2. Add 'zfs' before 'filesystems' in HOOKS"
    read -p "Press Enter to continue"
    nvim /etc/mkinitcpio.conf
    mark_completed 10
else
    print_step "Skipping mkinitcpio.conf config"
fi

if ! should_skip 11; then
    print_step "Making InitCPIO"
    mkinitcpio -P
    mark_completed 11
else
    print_step "Skipping InitCPIO"
fi

if ! should_skip 12; then
    print_step "Enabling services"
    systemctl enable zfs.target zfs-import-cache zfs-mount zfs-import.target \
        NetworkManager dhcpcd
    mark_completed 12
else
    print_step "Skipping services enablement"
fi 

if ! should_skip 13; then
    print_step "Setting hostname and timezone"
    hostnamectl set-hostname $HOSTNAME
    timedatectl set-timezone $TIMEZONE
    mark_completed 13
else
    print_step "Skipping hostname and timezone setting"
fi

if ! should_skip 14; then
    print_step "Creating sudo user"
    useradd -m -G wheel -s $(which zsh) $USERNAME
    passwd $USERNAME
    ln -s /usr/bin/nvim /usr/bin/vim

    print_step "Setting up sudo"
    echo "Please uncomment the wheel line in visudo"
    echo "    %wheel ALL=(ALL:ALL) ALL"
    read -p "Press Enter to continue"
    visudo

    mark_completed 14
else
    print_step "Skipping sudo user creation"
fi

su - $USERNAME -c "/root/tmp/su_commands.sh"
