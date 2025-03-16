#! /bin/bash

umount /mnt/boot/efi
umount /mnt

zpool destroy -f zroot