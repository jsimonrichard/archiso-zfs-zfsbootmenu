#!/bin/zsh

set -e
source "$(dirname $0)/install_shared.sh"

# Parse command line options
START_STEP=0
IGNORE_PROGRESS=false

while getopts "s:f" opt; do
    case $opt in
        s)
            IGNORE_PROGRESS=true
            START_STEP=$OPTARG
            if ! [[ $START_STEP =~ ^[0-9]+$ ]]; then
                echo "Error: Start step must be a number"
                exit 1
            fi
            ;;
        f)
            IGNORE_PROGRESS=true
            ;;
        \?)
            echo "Usage: $0 [-s STEP] [-f]"
            echo "  -s STEP  Start from specific step"
            echo "  -f       Force fresh start (ignore saved progress)"
            exit 1
            ;;
    esac
done


# Initialize progress tracking
init_progress $START_STEP $IGNORE_PROGRESS


# Function to detect CPU vendor
detect_cpu_vendor() {
    local vendor
    vendor=$(grep -m1 'vendor_id' /proc/cpuinfo | awk '{print $3}')
    
    case "$vendor" in
        "GenuineIntel")
            echo "intel"
            ;;
        "AuthenticAMD")
            echo "amd"
            ;;
        *)
            print_step "Could not automatically detect CPU vendor. Please specify (intel/amd):"
            read vendor
            case "${vendor:l}" in  # :l converts to lowercase
                intel|amd)
                    echo "$vendor"
                    ;;
                *)
                    echo "Invalid CPU vendor specified. Exiting."
                    exit 1
                    ;;
            esac
            ;;
    esac
}

local all_required_vars=("${COMMON_REQUIRED_VARS[@]}" "PART_ID_PATH" "EFI_DEVICE")
check_required_vars "${all_required_vars[@]}"

# CPU detection only needs to happen once
if should_skip 1; then
    CPU_VENDOR=$(cat /tmp/cpu_vendor)
else
    CPU_VENDOR=$(detect_cpu_vendor)
    echo $CPU_VENDOR > /tmp/cpu_vendor
    mark_completed 1
fi
print_step "Detected CPU vendor: $CPU_VENDOR"

# ZFS pool creation
if ! should_skip 2; then
    print_step "Creating the zpool and zfs datasets"
    
    zpool create -f -o ashift=12         \
                 -O acltype=posixacl       \
                 -O relatime=on            \
                 -O xattr=sa               \
                 -O normalization=formD    \
                 -O mountpoint=none        \
                 -O canmount=off           \
                 -O devices=off            \
                 -R /mnt                   \
                 -O compression=lz4        \
                 -O encryption=aes-256-gcm \
                 -O keyformat=passphrase   \
                 -O keylocation=prompt     \
                 zroot $PART_ID_PATH

    zfs create -o mountpoint=none zroot/data
    zfs create -o mountpoint=none zroot/ROOT
    zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/default
    zfs create -o mountpoint=/home zroot/data/home
    zfs create -o mountpoint=/root zroot/data/home/root

    zpool set cachefile=/etc/zfs/zpool.cache zroot
    zfs set org.zfsbootmenu:commandline="rw" zroot/ROOT

    zpool export zroot
    
    mark_completed 2
else
    print_step "Skipping zpool creation"
fi


print_step "Importing zpool"

zpool import -d /dev/disk/by-id -R /mnt zroot -N || true
zfs load-key zroot || true
zfs mount -a
zfs mount zroot/ROOT/default

# EFI partition setup
if ! should_skip 3; then
    print_step "Formatting the EFI partition"
    
    mkfs.fat -F32 $EFI_DEVICE
    
    mark_completed 3
else
    print_step "Skipping EFI partition formatting"
fi

print_step "Mounting the EFI partition"
mkdir -p /mnt/boot/efi
mount $EFI_DEVICE /mnt/boot/efi

# Install system packages
if ! should_skip 4; then
    print_step "Installing system packages"
    
    if [[ $CPU_VENDOR == "intel" ]]; then
        UCODE_PACKAGE=intel-ucode
    elif [[ $CPU_VENDOR == "amd" ]]; then
        UCODE_PACKAGE=amd-ucode
    fi

    pacstrap -K /mnt base base-devel linux-lts linux-firmware linux-lts-headers \
        zfs-dkms zfs-utils git neovim zsh which sudo efibootmgr openssh zellij \
        networkmanager dhcpcd wpa_supplicant iw iwd $UCODE_PACKAGE
    
    mark_completed 4
else
    print_step "Skipping system package installation"
fi

# Generate fstab
if ! should_skip 5; then
    print_step "Generating fstab"
    genfstab -U -p /mnt >> /mnt/etc/fstab
    mark_completed 5
else
    print_step "Skipping fstab generation"
fi

# Copy pacman config
if ! should_skip 6; then
    print_step "Copying pacman config"
    
    cp /etc/pacman.conf /mnt/etc/pacman.conf
    cp /etc/pacman.d/archzfs_mirrorlist /mnt/etc/pacman.d/archzfs_mirrorlist

    cp -r /usr/share/pacman/keyrings /mnt/usr/share/pacman/keyrings

    mark_completed 6
else
    print_step "Skipping pacman config copy"
fi

if ! should_skip 7; then
    print_step "Copying zpool cache"
    cp /etc/zfs/zpool.cache /mnt/etc/zfs/zpool.cache
    mark_completed 7
else
    print_step "Skipping zpool cache copy"
fi

print_step "Executing chroot commands"

# Before chroot, save important environment variables
mkdir -p /mnt/root/tmp
cat > /mnt/root/tmp/install_env.sh << EOF
export HOSTNAME="$HOSTNAME"
export USERNAME="$USERNAME"
export TIMEZONE="$TIMEZONE"
EOF

# Copy shared functions
cp "$(dirname $0)/install_shared.sh" /mnt/root/tmp

# Copy the chroot script into the chroot environment
cp "$(dirname $0)/chroot_commands.sh" /mnt/root/tmp
chmod +x /mnt/root/tmp/chroot_commands.sh

# Copy progress file
cp $PROGRESS_FILE /mnt/root/tmp

# Execute the chroot script
arch-chroot /mnt /root/tmp/chroot_commands.sh

# Cleanup
rm -rf /mnt/root/tmp

local green='\033[0;32m'
local reset='\033[0m'
echo -e "${green}"
echo "\n"
echo "************************************"
echo "*      Installation complete!      *" 
echo "************************************"
echo -e "${reset}"