ISO must have a kernel version supported by ZFS.
Recommended: https://github.com/stevleibelt/arch-linux-live-cd-iso-with-zfs
## Booting from USB on GRUB
```bash
ls # find your usb disk
ls (hd0,msdos1) # confirm
set root=(hd0,msdos1)
chainloader /efi/boot/BOOTx64.EFI
boot
```

## Connecting to Wifi
https://wiki.archlinux.org/title/Iwd

## Install Root System

https://wiki.archlinux.org/title/Install_Arch_Linux_on_ZFS

```zsh
# Install zfs (this is required even if you use the zfs arch iso (?))
curl -s https://raw.githubusercontent.com/eoli3n/archiso-zfs/master/init | bash

# Edit system partitions (keep EFI part., create one large part for zpool)
cfdisk /dev/sdX


ls -l /dev/disk/by-id # show links to normal block device name
PART_PATH=/dev/disk/by-id/<uuid>
zpool create -f -o ashift=12         \
             -O acltype=posixacl       \
             -O relatime=on            \
             -O xattr=sa               \
             -O normalization=formD    \ # consider using formC instead for syncthing; it won't be compatible with MacOS, but that's okay for me
             -O mountpoint=none        \
             -O canmount=off           \
             -O devices=off            \
             -R /mnt                   \
             -O compression=lz4        \
             -O encryption=aes-256-gcm \
             -O keyformat=passphrase   \
             -O keylocation=prompt     \
             zroot $PART_PATH

zfs create -o mountpoint=none zroot/data
zfs create -o mountpoint=none zroot/ROOT
zfs create -o mountpoint=/ -o canmount=noauto zroot/ROOT/default
zfs create -o mountpoint=/home zroot/data/home
zfs create -o mountpoint=/root zroot/data/home/root

zpool export zroot
zpool import -d /dev/disk/by-id -R /mnt zroot -N
zfs load-key zroot
zfs mount -a
zfs mount zroot/ROOT/default
zfs get mounted # check to make sure everything is mounted

mkfs.fat -F32 /dev/<efi part>
mkdir -p /mnt/boot/efi
mount /dev/<efi part> /mnt/boot/efi

pacstrap -K /mnt base base-devel linux-lts linux-firmware linux-lts-headers git neovim zsh which sudo efibootmgr openssh tmux # also include amd-ucode or intel-ucode
genfstab -U -p /mnt >> /mnt/etc/fstab
vim /mnt/etc/fstab # remove zfs options, since zfs handles that separately
arch-chroot /mnt

mount -a # mounts EFI part


# Install zfs
curl -s https://raw.githubusercontent.com/eoli3n/archiso-zfs/master/init | bash
# or

# --------
# may need to update the /etc/pacman.d/mirrorlist
nvim /etc/pacman.d/mirrorlist # add Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch (may not be necessary)



pacman -Sy zfs-dkms # build for the latest patch of the lts kernel
# ---------

nvim /etc/mkinitcpio.conf # add zfs module and hook (right before filesystems hook)

# automatically mount zfs pools on boot
zpool set cachefile=/etc/zfs/zpool.cache zroot
systemctl enable zfs.target zfs-import-cache.service zfs-mount.service zfs-import.target

zgenhostid $(hostid)

mkinitcpio -P

zfs mount -a

# Set hostname so that other services can find this machine; this also relies on avahi-daemon running (I think)
hostnamectl set-hostname <host-name>
# If you already started NetworkManager, restart it for the hostname to be updated on the router

# Install network manager in new system
# pacman -S networkmanager dhcpcd bind iproute2 wpa_supplicant iw
pacman -S networkmanager dhcpcd wpa_supplicant iw
systemctl enable NetworkManager dhcpcd
# maybe edit /dev/resolv.conf

timedatectl set-timezone America/New_York

# Provision sudo user (required for AUR install)
useradd -m -G wheel -s $(which zsh) jsimonrichard
ln -s /usr/bin/nvim /usr/bin/vim
visudo # uncomment wheel line ("%wheel ALL=(ALL:ALL) ALL")
passwd jsimonrichard
su - jsimonrichard
# optionally complete zsh rc

# install yay
mkdir aur
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si
yay -Y --gendb # generates the yay db for AUR packages previously installed using git 

# install zfsbootmenu
yay -S zfsbootmenu

sudo nvim /etc/zfsbootmenu/config.yaml
# inside Global:, set ManageImages: true, set InitCPIO: true
# inside Components: set Enabled to false
# inside EFI set Enabled to true
sudo generate-zbm

sudo zfs set org.zfsbootmenu:commandline="rw" zroot/ROOT

# EFI entry
sudo efibootmgr --create --disk _your_esp_disk_block_device --part _your_esp_partition_number_ --label "ZFSBootMenu" --loader '\EFI\zbm\vmlinuz-linux-lts.EFI' --unicode


# With grub
yay -S grub

sudo blkid /dev/<efi part> -o export > /tmp/blkid-env
source /tmn/blkid-env
sudo sh -c "echo $UUID >> /etc/grub.d/40_custom"
cd /etc/grub.d
sudo mv 10_linux ../grub.10_linux.disabled # These grub menu options won't work
sudo cp 40_custom 10_zfsbootmenu
sudo nvim 10_zfsbootmenu # see file below

sudo grub-mkconfig -o /boot/efi/EFI/grub/grub.cfg

sudo grub-install --target=x86_64-efi --efi-directory=<esp> --bootloader-id=grub --boot-directory=<eps>/EFI # --debug

sudo nvim /etc/hostname # add hostname

exit && exit
reboot
```

10_zfsbootmenu
```
sudmenuentry "ZFS Boot Menu" {
	insmod part_gpt
	insmod fat
	insmod chain
	search --no-floppy --fs-uuid --set=root YOUR_ESP_UUID
	chainloader /EFI/zbm/vmlinuz-linux-lts.EFI
}
```

On the new system:
```bash
sudo pacman -S plasma kitty konsole packagekit packagekit-qt5
sudo systemctl enable --now sddm # starts plasma
yay -S ttf-meslo-nerd-font-powerlevel10k zsh-theme-powerlevel10k-git brave-bin visual-studio-code-bin python python-pip ipython sagemath syncthing dolphin 1password ark bluez bluez-utils zotero duplicati-beta-bin cups cups-pdf cups-filters nss-mdns
echo 'source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme' >>~/.zshrc
echo 'alias sshi="kitty +kitten ssh"' >>~/.zshrc

sudo nvim /etc/nsswitch.conf # add `mdns_minimal [NOTFOUND=return]` right after `hosts: mymachines `

sudo systemctl enable --now bluetooth cups avahi-daemon
```

#### Things I may need in the future
```zsh
# increase cowspace in iso
mount -o remount,size=10G /run/archiso/cowspace
```

### Other notes
```
psmouse serio1: synapticsL Unable to query device: -5
```

May need to delete `~/.cache` if KDE has config bugs


## Things to install
* [x] powerlevel10, meslo ttf font
* [x] code
* [x] brave
* [x] spotify
* [x] python, python-pip, sagemath
* [x] syncthing ✅ 2024-10-26
	- ~~Enable `git config --global core.precomposeUnicode true` so syncthing can handle special unicode letters in filenames~~
		- Only works on MasOS :(
* [/] duplicati + S3
* [x] vscode + extensions...
* [ ] Gwenview, okular

- [x] Fix boot over usb issue on elendil ✅ 2024-10-26
	- Installed GRUB (which can boot USBs), chainloaded ZFSBootMenu

## Setting up git
```bash
git config set --global user.name "J. Simon Richard"
git config set --global user.email "jsimonrichard@gmail.com"
```

Then setup with 1password: https://developer.1password.com/docs/ssh/git-commit-signing/

## Getting a good mirror list
* Get one from here after selecting your country: https://archlinux.org/mirrorlist/
* Uncomment all mirrors
* Run `yay -S pacman-contrib`
* Run `rankmirrors /etc/pacman.d/mirrorlist > mirrorlist2`
	* This will take a while
* Move your new mirror list (with sudo)


## Hook to take ZFS snapshot before pacman updates

In `/etc/pacman.d/hooks`, place these two files:

**10-zfs-snapshot.hook**
```toml
[Trigger]
Operation=Install
Operation=Upgrade
Operation=Remove
Type=Package
Target=*

[Action]
When=PreTransaction
Exec=/etc/pacman.d/hooks/pacman-zfs-snapshot.sh
```

**pacman-zfs-snapshot.sh**
```bash
#!/usr/bin/env bash

DATE="$(date --utc --iso-8601=seconds)"
EPOCH="$(date --utc --date "$DATE" +%s)"
SNAPSHOT_DATE="$(date --utc --date "$DATE" +%Y%m%dT%H%M%SZ)"
# datasets you'd like to take snapshots of. note '-r' is used to take snapshots recursively
DATASETS=( \
    zroot/ROOT
    zroot/data
)
# how many days you'd like to keep the snapshots
KEEP_DAYS=7
KEEP_SECONDS=$(( KEEP_DAYS * 24 * 3600 ))
# skip taking new snapshots if the last one was taken within THROTTLE_SECONDS
THROTTLE_SECONDS=900
# prefix of snapshot names, make sure it doesn't conflict with others
SNAPSHOT_PREFIX="pacman"

# input: a/b@pacman-20181212T211523Z
# output: 2018-12-12 21:15:23
function get_snapshot_date() {
    snapshot_name="$1"
    # shellcheck disable=SC2001
    snapshot_date="$(sed "s/.*$SNAPSHOT_PREFIX-\(....\)\(..\)\(..\)T\(..\)\(..\)\(..\)Z/\1-\2-\3 \4:\5:\6/" <<< "$snapshot_name")"
    printf '%s' "$snapshot_date"
}

# input: a/b@pacman-20181212T211523Z
# output: 1544609723
function get_snapshot_epoch() {
    snapshot_name="$1"
    # shellcheck disable=SC2001
    snapshot_date="$(get_snapshot_date "$snapshot_name")"
    snapshot_epoch="$(date --utc --date "$snapshot_date" +%s)"
    printf '%s' "$snapshot_epoch"
}

last_snapshot="$(zfs list -t snapshot -S creation -o name -H | rg "@$SNAPSHOT_PREFIX" | head -n 1)"
if [[ -n "$last_snapshot" ]]; then
    last_snapshot_epoch="$(get_snapshot_epoch "$last_snapshot")"
    if [[ $(( EPOCH - last_snapshot_epoch )) -lt "$THROTTLE_SECONDS" ]]; then
        printf 'Last snapshot %s was created at %s (%s), skipping creating new ones\n' "$last_snapshot" "$(get_snapshot_date "$last_snapshot")" "$last_snapshot_epoch"
        exit 0
    fi
fi

zfs list -t snapshot -S creation -o name -H | rg "@$SNAPSHOT_PREFIX" | while read -r snapshot; do
    snapshot_epoch="$(get_snapshot_epoch "$snapshot")"
    if [[ $(( EPOCH - snapshot_epoch )) -gt $KEEP_SECONDS ]]; then
        printf 'Destroying snapshot %s\n' "$snapshot"
        zfs destroy "$snapshot"
    else
        # remove this if it's too annoying
        printf 'Keeping snapshot %s created at %s (%s)\n' "$snapshot" "$(get_snapshot_date "$snapshot")" "$snapshot_epoch"
    fi
done

for dataset in "${DATASETS[@]}"; do
    snapshot="$dataset@$SNAPSHOT_PREFIX-$SNAPSHOT_DATE"
    printf 'Creating snapshot %s\n' "$snapshot"
    zfs snapshot -r "$snapshot"
done
```


## Ngrok SSH Tunnel
Only for paid ngrok accounts :(

``` bash
yay -S openssh
yay ngrok
```

Edit `/etc/ssh/sshd_config`
```
PasswordAuthentication No
PermitRootLogin no
```

``` bash
sudo systemctl enable --now sshd
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEO5wNHZQmZ4Xkz08W0COGJy2vdPhMRLlJYdEh9ks48a" >> ~/.ssh/authorized_keys
ngrok config add-authtoken <auth_token>
```

## Cloudflared SSH Tunnel
https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/use-cases/ssh/#connect-to-ssh-server-with-cloudflared-access

```bash
yay -S cloudflared
```

Add to `~/.ssh/config`:
```
Host ssh.jsimonrichard.com
        ProxyCommand /usr/bin/cloudflared access ssh --hostname %h

Host excalibur.jsimonrichard.com
        ProxyCommand /usr/bin/cloudflared access ssh --hostname %h
```

You could do a wildcard here, but you never know what other servers you'll need to add.

## Tmux config


## Restic Backups with S3 / Backblaze

```bash
yay -S restic resticprofile-bin
```

Add to `~/profiles.yaml`:
```yaml
version: "1"

default:
  repository: s3:s3.us-east-005.backblazeb2.com/jsimonrichard-<name>-backup
  password-file: '.restic-key'

  env:
    AWS_ACCESS_KEY_ID: <key-name>
    AWS_SECRET_ACCESS_KEY: <key>

  backup:
    tag:
      - "root"
    source:
      - "/"
    schedule: "daily"
    schedule-after-network-online: true
    skip-if-unchanged: true
    exclude:
      - "node_modules/"
      - "target/"
      - "__pycache__/"
      - "~/.cache"
```

Then initiate and schedule (while in `~`):
```
resticprofile generate --random-key > .restic-key
resticprofile init
sudo resticprofile schedule
```

Finally, **upload .restic-key** to 1password! Losing it means losing the backups.


## Fixing Font Issues online
After installing `ttf-ms-fonts` or something that includes "Courier New" (which looks awful), a lot of websites / Obsidian using monospace may start falling back to that awful font. To fix this, edit `.config/fontconfig/fonts.conf` to include the following:
```xml
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <alias>
    <family>Menlo</family>
    <prefer>
      <family>MesloLGS NF</family>
      <family>Menlo</family>
    </prefer>
  </alias>
  <alias>
    <family>ui-monospace</family>
    <prefer>
      <family>Noto Sans Mono</family>
      <family>MesloLGS NF</family>
    </prefer>
  </alias>
</fontconfig>
```

Then run `fc-cache` (probably required). Finally, restart affected apps.


## Zen Browser
- https://www.reddit.com/r/zen_browser/comments/1es1acr/comment/luoelb2/?utm_source=share&utm_medium=web3x&utm_name=web3xcss&utm_term=1&utm_content=share_button
- https://edb.tools/posts/1password-extension-fix/
```bash
yay -Syy zen-browser-bin
sudo mkdir /etc/1password
sudo echo "zen-bin" > /etc/1password/custom_allowed_browsers
sudo chown root:root /etc/1password/custom_allowed_browsers
sudo chmod 755 /etc/1password/custom_allowed_browsers
```

## Using TexLive Fonts
To use texlive fonts, you'll need to link tex's font directories with the default font directories.
```bash
sudo ln -s /usr/share/texmf-dist/fonts/opentype /usr/share/fonts/tex-opentype
sudo ln -s /usr/share/texmf-dist/fonts/truetype /usr/share/fonts/tex-truetype
```


## Using v4l2 loopback device to rotate Webcam feed

First, install/load the loopback kernel module
```bash
yay v4l2loopback-dkms
sudo modprobe v4l2loopback exclusive_caps=1 max_buffers=2 card_label="Virtual Camera" video_nr=2

# Remove if necessary
sudo rmmod v4l2loopback
```

To make the module load on boot, create these files:
`/etc/modprobe.d/v4l2loopback.conf`:
```
options v4l2loopback exclusive_caps=1 max_buffers=2 card_label="Virtual Camera" video_nr=2
```

`/etc/modules-load.d/v4l2.conf`:
```
v4l2loopback
```

Then create a systemd service at `.config/systemd/user/webcam-rotate.service`:
```ini
[Unit]
Description=Rotate webcam feed
After=graphical-session.target

[Service]
ExecStart=/usr/bin/ffmpeg -f v4l2 -i /dev/video0 -vf "vflip,hflip,format=yuv420p" -f v4l2 /dev/video2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=graphical-session.target
```

Then
```bash
systemctl --user enable --now webcam-rotate.service
```

## Issues with Localhost
External DNS systems may help your computer resolve `localhost`, but others may not, leading to flaky issues on different networks.

To fix, make sure that `/etc/hosts` contains the following:
```
127.0.0.1 localhost
::1 localhost
```

## Helpful tool for finding dependee packages
```
pactree -r <package-name>
```


## Add things to your path
`~/.zshrc`:
```
path+=('~/.cargo/bin')
```

Note that there must not be any spacing between `path`, `+=`, and the rest of the command.


## Using a fingerprint sensor
First, you'll need to install any required drivers (e.g. `libfprint-2-tod1-xps9300-bin`). After that, install `fprintd`.

At this point, you should be able to enroll a fingerprint through **System Settings > Users > ... > Configure Fingerprint Authenatication...**.

To enable the use of the fingerprint auth, edit `/etc/pam.d/system-auth` to look like this:

```ini
#%PAM-1.0

auth       required                    pam_faillock.so      preauth
auth       sufficient                  pam_fprintd.so
# important bit  ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
...
```