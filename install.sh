#!/usr/bin/env bash
umount -A --recursive /mnt
export sep=$(echo -e "\n===========================\n \n")
iso=$(curl -4 ifconfig.co/country-iso) && time_zone="$(curl --fail https://ipapi.co/timezone)" && clear
echo $sep && echo  Welcome to cojmar arch, please note this script is on progress and atm requires u to make partitions in advance && echo ''
echo U can use cfdisk to make hdd GPT add 1 efi partition 1M and another linux system rest of the disk hf
echo $sep && echo "Available disks"
lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}'
echo '' && printf "%s" "OS disk (default 1) : " && read my_disk && if [[ -z "$my_disk" ]]; then my_disk=1;fi
my_disk=$(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}'| awk 'NR=='$my_disk' {print $2}')
echo $my_disk
echo $sep && echo "Available partitions"
lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="part"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}'
echo '' && printf "%s" "Boot partition EFI (default 1) : " && read boot_part && if [[ -z "$boot_part" ]]; then boot_part=1;fi
boot_part=$(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="part"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}' | awk 'NR=='$boot_part' {print $2}')
echo $boot_part
echo '' && printf "%s" "OS partition (default 2) : " && read sys_part && if [[ -z "$sys_part" ]]; then sys_part=2;fi
sys_part=$(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="part"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}' | awk 'NR=='$sys_part' {print $2}')
echo $sys_part
echo $sep && printf "%s" "Username (default cojmar) : " && read my_user && if [[ -z "$my_user" ]]; then my_user=cojmar;fi
echo $my_user
echo $sep && printf "%s" "Mirors (default $iso) : " && read my_iso && if [[ -z "$my_iso" ]]; then my_iso=$iso;fi
echo $my_iso
echo $sep && printf "%s" "TimeZone (default $time_zone) : " && read my_time_zone && if [[ -z "$my_time_zone" ]]; then my_time_zone=$time_zone;fi &&echo $my_time_zone
echo $sep && printf "%s" "Host name (default cojarch) : " && read my_host_name && if [[ -z "$my_host_name" ]]; then my_host_name=cojarch;fi
echo $my_host_name && echo ''
mkfs.fat $boot_part && mkfs.ext4 -F $sys_part && sync
mount $sys_part /mnt && mount --mkdir $boot_part /mnt/boot/efi
timedatectl set-ntp true
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
reflector -a 48 -c $iso -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist && pacman -Sy
pacman -S --noconfirm archlinux-keyring
pacstrap -K /mnt base linux linux-firmware archlinux-keyring grub efibootmgr openssh dhcpcd sudo mc htop ncdu --noconfirm --needed
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
cp /etc/pacman.conf /mnt/etc/pacman.conf
echo "keyserver hkp://keyserver.ubuntu.com" >> /mnt/etc/pacman.d/gnupg/gpg.conf
genfstab -U /mnt > /mnt/etc/fstab
ln -sf /mnt/usr/share/zoneinfo/$my_time_zone /mnt/etc/localtime
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
echo $my_host_name > /mnt/etc/hostname
echo $sep && printf "Make swap? (leave blank for yes) :" && read do_this && if [[ -z "$do_this" ]]; then 
    # Put swap into the actual system, not into RAM disk, otherwise there is no point in it, itll cache RAM into RAM. So, /mnt/ everything.
    mkdir -p /mnt/opt/swap # make a dir that we can apply NOCOW to to make it btrfs-friendly.
    chattr +C /mnt/opt/swap # apply NOCOW, btrfs needs that.
    dd if=/dev/zero of=/mnt/opt/swap/swapfile bs=1M count=2048 status=progress
    chmod 600 /mnt/opt/swap/swapfile # set permissions.
    chown root /mnt/opt/swap/swapfile
    mkswap /mnt/opt/swap/swapfile
    swapon /mnt/opt/swap/swapfile
    # The line below is written to /mnt/ but doesnt contain /mnt/, since it s just / for the system itself.
    echo "/opt/swap/swapfile    none    swap    sw    0    0" >> /mnt/etc/fstab # Add swap to fstab, so it KEEPS working after installation.
fi
echo -ne '
pacman -Syy
grub-install --recheck ${my_disk} && grub-mkconfig -o /boot/grub/grub.cfg
systemctl enable sshd && systemctl enable dhcpcd

# determine processor type and install microcode
proc_type=$(lscpu)
if grep -E "GenuineIntel" <<< ${proc_type}; then
    echo "Installing Intel microcode"
    pacman -S --noconfirm --needed intel-ucode
    proc_ucode=intel-ucode.img
elif grep -E "AuthenticAMD" <<< ${proc_type}; then
    echo "Installing AMD microcode"
    pacman -S --noconfirm --needed amd-ucode
    proc_ucode=amd-ucode.img
fi



useradd -U $my_user
echo "$my_user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$my_user
chmod 0440 /etc/sudoers.d/$my_user
mkdir /home/$my_user && chown $my_user /home/$my_user 
echo AllowUsers $my_user >> /etc/ssh/sshd_config && echo '' && echo $sep Seting Passward for $my_user && passwd $my_user

echo $sep && printf "%s" "Autologin ? (leave blank for NO) : " && read do_reb && if [[ -z "$do_reb" ]]; then
echo secure
else
mkdir -p /etc/systemd/system/getty@tty1.service.d/
echo -ne "
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty -a $my_user - \$TERM
" > /etc/systemd/system/getty@tty1.service.d/override.conf
echo Autologin done
fi

echo $sep && printf "%s" "Network manager (replaces dhcpcd) ? (leave blank for NO) : " && read do_reb && if [[ -z "$do_reb" ]]; then
echo skiped
else
pacman -S --needed --noconfirm networkmanager dhclient
systemctl disable dhcpcd
systemctl stop dhcpcd
systemctl enable NetworkManager.service
fi

echo $sep && printf "%s" "GUI (xorg xfce4 graphicdrivers) ? (leave blank for NO) : " && read do_reb && if [[ -z "$do_reb" ]]; then
echo console only
else
pacman -S --needed --noconfirm xorg xfce4

# Graphics Drivers find and install
gpu_type=$(lspci)
if grep -E "NVIDIA|GeForce" <<< ${gpu_type}; then
    pacman -S --noconfirm --needed nvidia
    nvidia-xconfig
elif lspci | grep 'VGA' | grep -E "Radeon|AMD"; then
    pacman -S --noconfirm --needed xf86-video-amdgpu
elif grep -E "Integrated Graphics Controller" <<< ${gpu_type}; then
    pacman -S --noconfirm --needed libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa
elif grep -E "Intel Corporation UHD" <<< ${gpu_type}; then
    pacman -S --needed --noconfirm libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa
else
    pacman -S --needed --noconfirm gtkmm open-vm-tools xf86-video-vmware xf86-input-vmmouse
    systemctl enable vmtoolsd
fi
if [[ ! $DISPLAY && $XDG_VTNR -eq 1 ]]; then
    Xorg :0 -configure
    cp /root/xorg.conf.new /etc/X11/xorg.conf
fi

echo $sep && printf "%s" "Autostart Xfce4 ? (leave blank for yes) : " && read do_reb && if [[ -z "$do_reb" ]]; then
echo -ne "
if [[ ! \$DISPLAY && \$XDG_VTNR -eq 1 ]]; then
    startxfce4
fi
" > /home/$my_user/.bash_profile && chown $my_user /home/$my_user/.bash_profile
echo AutostartX done
fi

echo $sep && printf "%s" "Optimise for desktop experience (chromium xfce4-goodies code) ? (leave blank for yes) : " && read do_reb && if [[ -z "$do_reb" ]]; then
pacman -S --needed --noconfirm chromium xfce4-goodies code
fi

echo $sep && printf "%s" "Gaming (adds wine winetricks) ? (leave blank for yes) : " && read do_reb && if [[ -z "$do_reb" ]]; then
pacman -S --needed --noconfirm wine winetricks
fi

fi



echo $sep && printf "%s" "Extra packages :" && read do_reb && if [[ -z "$do_reb" ]]; then
echo skiped
else
pacman -S --needed --noconfirm $do_reb
fi

rm -rf continue.sh
' > /mnt/continue.sh
chmod +x /mnt/continue.sh
export my_user = $my_user
export my_disk = $my_disk
arch-chroot /mnt ./continue.sh
clear
echo "


                                         ▄▆▅▄   ▆▅▄        █     
                  ▟█▙                  █        █    █       █    
                 ▟███▙                 █▄▄▄▄▄   █▄▄▄▄█   █▄▄▄█    
                ▟█████▙                
               ▟███████▙
              ▂▔▀▜██████▙
             ▟██▅▂▝▜█████▙
            ▟█████████████▙
           ▟███████████████▙
          ▟█████████████████▙
         ▟███████████████████▙
        ▟█████████▛▀▀▜████████▙
       ▟████████▛      ▜███████▙
      ▟█████████        ████████▙
     ▟██████████        █████▆▅▄▃▂
    ▟██████████▛        ▜█████████▙
   ▟██████▀▀▀              ▀▀██████▙
  ▟███▀▘                       ▝▀███▙
 ▟▛▀                               ▀▜▙
"
printf "%s" "Arch installed, reboot? (default y) : " && read do_reb && if [[ -z "$do_reb" ]]; then reboot;fi