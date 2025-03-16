#!/bin/bash

# Exit if not root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

# Check for required packages
if ! pacman -Q xorriso &>/dev/null; then
    echo "Error: xorriso package is required"
    echo "Please install it with: pacman -S xorriso"
    exit 1
fi

if ! pacman -Q squashfs-tools &>/dev/null; then
    echo "Error: squashfs-tools package is required"
    echo "Please install it with: pacman -S squashfs-tools"
    exit 1
fi

# Exit on any error
set -e

# Default values
ISO_PATH="archlinux.iso"
MOUNT_POINT="/mnt/archiso-update-scripts-iso-mount-point"
WORK_DIR="/tmp/archiso-update-scripts-work-dir"

# Cleanup function
cleanup() {
    local exit_code=$?
    echo "Cleaning up..."
    # Only try to unmount if mount point exists and is mounted
    if [[ -d "$MOUNT_POINT" ]] && mountpoint -q "$MOUNT_POINT"; then
        sudo umount "$MOUNT_POINT"
    fi
    if [[ -d "$MOUNT_POINT" ]]; then
        sudo rm -rf "$MOUNT_POINT"
    fi
    # Only try to remove work dir if it exists
    if [[ -d "$WORK_DIR" ]]; then
        sudo rm -rf "$WORK_DIR"
    fi
    exit $exit_code
}

# Set up cleanup trap
trap cleanup EXIT

# disables
exit 0

# Parse command line options
while getopts "i:m:w:" opt; do
    case $opt in
        i) ISO_PATH="$OPTARG" ;;
        m) MOUNT_POINT="$OPTARG" ;;
        w) WORK_DIR="$OPTARG" ;;
        \?)
            echo "Usage: $0 [-i ISO_PATH] [-m MOUNT_POINT] [-w WORK_DIR]"
            echo "  -i: Path to ISO file (default: archlinux.iso)"
            echo "  -m: Mount point (default: /mnt/archiso-update-scripts-iso-mount-point)"
            echo "  -w: Working directory (default: /tmp/archiso-update-scripts-work-dir)"
            exit 1
            ;;
    esac
done

# Check if ISO exists
if [[ ! -f "$ISO_PATH" ]]; then
    echo "Error: ISO file not found at $ISO_PATH"
    exit 1
fi

# Create mount point if it doesn't exist
mkdir -p "$MOUNT_POINT"

# Mount ISO
if ! mount -o loop "$ISO_PATH" "$MOUNT_POINT"; then
    echo "Error: Failed to mount ISO"
    exit 1
fi

# Check if work directory exists and ask to reuse
if [[ -d "$WORK_DIR" ]]; then
    read -p "Work directory exists. Reuse it? [y/N] " reuse
    if [[ "${reuse,,}" == "y" ]]; then
        echo "Reusing existing work directory..."
    else
        echo "Removing old work directory..."
        rm -rf "$WORK_DIR"
        mkdir -p "$WORK_DIR"
        # Copy ISO contents only if we're not reusing
        cp -a "$MOUNT_POINT/"* "$WORK_DIR/"
    fi
else
    mkdir -p "$WORK_DIR"
    cp -a "$MOUNT_POINT/"* "$WORK_DIR/"
fi

# Always update squashfs regardless of reuse choice
unsquashfs -d "$WORK_DIR/squashfs-root" "$MOUNT_POINT/arch/x86_64/airootfs.sfs"
cp airootfs/root/{install.sh,install_shared.sh,chroot_commands.sh} "$WORK_DIR/squashfs-root/root/"
mksquashfs "$WORK_DIR/squashfs-root" "$WORK_DIR/arch/x86_64/airootfs.sfs" -noappend
rm -rf "$WORK_DIR/squashfs-root"

# Create new ISO
xorriso -as mkisofs \
    -iso-level 3 \
    -full-iso9660-filenames \
    -volid "ARCH_$(date +%Y%m)" \
    -eltorito-boot boot/syslinux/isolinux.bin \
    -eltorito-catalog boot/syslinux/boot.cat \
    -no-emul-boot -boot-load-size 4 -boot-info-table \
    -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
    -eltorito-alt-boot \
    -e EFI/archiso/efiboot.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -output arch_new.iso \
    $WORK_DIR
