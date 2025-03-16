#! /bin/bash

set -e

# Copy and source the shared functions
export PROGRESS_FILE="$HOME/tmp/install_progress"
source $HOME/tmp/install_shared.sh

# Access environment variables passed from the host
source $HOME/tmp/install_env.sh  # We'll create this

check_required_vars "${COMMON_REQUIRED_VARS[@]}"

if ! should_skip 15; then
    # Install yay
    mkdir aur && cd aur
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    yay -Y --gendb
else
    print_step "Skipping yay installation"
fi

if ! should_skip 16; then
    # Install zfsbootmenu
    yay -S zfsbootmenu-efi-bin --noconfirm
else
    print_step "Skipping zfsbootmenu installation"
fi

# # Configure ZFSBootMenu
# cat > /etc/zfsbootmenu/config.yaml << 'EOF'
# Global:
#   ManageImages: true
#   BootMountPoint: /boot/efi
#   DracutConfDir: /etc/zfsbootmenu/dracut.conf.d
#   PreHooksDir: /etc/zfsbootmenu/generate-zbm.pre.d
#   PostHooksDir: /etc/zfsbootmenu/generate-zbm.post.d
#   InitCPIO: true
#   InitCPIOConfig: /etc/zfsbootmenu/mkinitcpio.conf
# Components:
#   ImageDir: /boot/efi/EFI/zbm
#   Versions: 3
#   Enabled: false
# EFI:
#   ImageDir: /boot/efi/EFI/zbm
#   Versions: false
#   Enabled: true
# Kernel:
#   CommandLine: ro quiet loglevel=0
# EOF

if ! should_skip 17; then
    print_step "Creating ZFSBootMenu EFI entry"
    sudo efibootmgr --create --disk $EFI_DISK --part $EFI_PART \
        --label "ZFS Boot Menu" --loader '\EFI\zbm\zfsbootmenu-release-vmlinuz-x86_64.EFI' --unicode
else
    print_step "Skipping EFI entry creation for ZFSBootMenu"
fi

if ! should_skip 18; then
    print_step "Installing KDE Plasma and other applications"

    yay -S --noconfirm plasma kitty konsole packagekit packagekit-qt5
    sudo systemctl enable sddm

    yay -S --noconfirm ttf-meslo-nerd-font-powerlevel10k zsh-theme-powerlevel10k-git \
        zen-browser-bin visual-studio-code-bin cursor-bin python python-pip ipython sagemath syncthing \
        dolphin 1password ark bluez bluez-utils zotero duplicati-beta-bin cups cups-pdf \
        cups-filters nss-mdns spotify
    echo 'source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme' >> ~/.zshrc
    echo 'alias sshi="kitty +kitten ssh"' >> ~/.zshrc

    # Add mdns_minimal after mymachines in hosts line
    sudo sed -i '/^hosts:/ s/mymachines/mymachines mdns_minimal [NOTFOUND=return]/' /etc/nsswitch.conf

    sudo systemctl enable bluetooth cups avahi-daemon

else
    print_step "Skipping KDE Plasma installation"
fi

