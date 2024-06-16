#!/usr/bin/env bash
#INIT
export sep=$(echo -ne "\n===========================\n \n")
export my_pacman=(base linux linux-firmware archlinux-keyring grub efibootmgr openssh dhcpcd sudo mc htop ncdu vim networkmanager dhclient)
function get_opt() {   
    echo -ne '\n' 
    printf "%s" "$1 (default $2) : " && read my_opt && if [[ -z "$my_opt" ]]; then my_opt=$2;fi    
    # echo $my_opt
}
#DISK
function get_disk() { # gets install disk
    echo $sep && echo "Available disks"
    lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}'
    get_opt "Install on disk" "1"
    
    export my_disk=$(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}' | awk 'NR=='$my_opt' {print $2}')
    echo $my_disk
}
function make_part() { # makes partitions on install disk
    # disk prep
    sgdisk -Z ${my_disk} # zap all on disk
    sgdisk -a 2048 -o ${my_disk} # new gpt disk 2048 alignment

    sgdisk -n 2::+1M --typecode=2:ef00:'EFIBOOT' ${my_disk} # partition 1 (EFI)
    sgdisk -n 3::-0 --typecode=3:8300:'ROOT' ${my_disk} # partition 2 (OS) 
    partprobe ${my_disk} 
}
function get_part_auto() { # get partitions automaticaly based on selected disk
    boot_part=$(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="part"{print "/dev/"$2" -  "$3}' | awk -v var="$my_disk" '$1 ~ var {print $0}' | awk '{print NR,$0}' | awk 'NR=='1' {print $2}')
    echo BOOT $boot_part   

    sys_part=$(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="part"{print "/dev/"$2" -  "$3}' | awk -v var="$my_disk" '$1 ~ var {print $0}' | awk '{print NR,$0}' | awk 'NR=='2' {print $2}')
    echo OS $sys_part
}
function get_part() { # manualy select partitions
    echo $sep && echo "Available partitions"
    lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="part"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}'
    
    get_opt "Boot partition EFI" "1"    
    boot_part=$(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="part"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}' | awk 'NR=='$my_opt' {print $2}')
    echo $boot_part
    
    get_opt "OS partition" "2"
    sys_part=$(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="part"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}' | awk 'NR=='$my_opt' {print $2}')
    echo $sys_part 
}
function set_disk() { # runs all disk settings
    umount -A --recursive /mnt
    echo $sep
    echo Disk Operations    
    get_disk
    get_opt "Auto partition the disk?" "y"
    my_auto_part=n
    if [ $my_opt = 'y' ];then 
        my_auto_part=y
        echo $my_auto_part
    else 
        get_part
    fi
    get_opt "File system type [1:btrfs 2:ext4]" "1"
    export my_file_system=$my_opt
     if [ $my_file_system = '1' ];then 
        echo btrfs 
    else 
        echo ext4
    fi

    my_def_swap_opt=n 
    TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
    if [[  $TOTAL_MEM -lt 4000000 ]]; then
        my_def_swap_opt=n 
    fi

    get_opt "Make Swap?" $my_def_swap_opt
    my_make_swap=$my_opt
    echo $my_make_swap
}
# USER
function get_password() { # gets password to be used
    get_opt "Please enter password: " "asd"
    pass1=$my_opt
    get_opt "Please re-enter password: " "asd"
    pass2=$my_opt   
    if [[ "$pass1" == "$pass2" ]]; then
        export my_pass=$pass1        
    else
        echo -ne "ERROR! Passwords do not match. \n"
        get_password
    fi
}
function set_user() { # runs all the user settings
    echo $sep  
    get_opt "Username" "cojmar"
    export my_user=$my_opt
    echo $my_user
    get_password
    get_opt "Autologin" "n"
    export my_user_autologin=$my_opt
    echo $my_user_autologin
}
function make_swap(){
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
}
# GUI
function set_gui(){
    export my_gui_autostart=n
    export my_drivers=0
    get_opt 'GUI (xorg xfce4 unzip graphicdrivers audiomixer)' "n"
    echo $my_opt
    if [ "$my_opt" = "n" ]; then
        export my_gui=0
        get_opt 'Install Video drivers ?' "n"
        echo $my_opt
        if [ "$my_opt" = "y" ]; then
            export my_drivers=1    
        fi
    else
        export my_gui=1
        export my_drivers=1
        get_opt 'Autostart GUI ?' "y"  
        echo $my_opt      
        export my_gui_autostart=$my_opt      
        get_opt 'Optimise for desktop experience (chromium xfce4-goodies) ?' "y"
        echo $my_opt
        if [ "$my_opt" = "y" ]; then
            export my_gui=2      
        fi
        get_opt 'Optimise for Gaming ?' "y"
        echo $my_opt
        if [ "$my_opt" = "y" ]; then
            export my_drivers=2      
        fi        
    fi
}

iso=$(curl -4 ifconfig.co/country-iso) && time_zone="$(curl --fail https://ipapi.co/timezone)" 

clear 
echo $sep && echo  Welcome to cojmar arch
set_disk

echo $sep
echo Base config
echo $sep
get_opt "Host name" "cojarch"
my_host_name=$my_opt
echo $my_host_name
set_user
echo $sep
echo Optional config
echo $sep
set_gui
echo $sep
my_def_aur_opt=n
if [ "$my_gui" != "0" ]; then
    my_def_aur_opt=y
fi
get_opt "AUR (adds yay and pacseek aur helpers)" $my_def_aur_opt
export my_aur=$my_opt
echo $my_aur
echo $sep
if [ "$my_aur" = "y" ]; then
    echo AUR detected, you can typein AUR packages too, example: brave
fi
get_opt "Extra packages" ""
export my_extra=$my_opt
echo $my_extra
echo ""
echo $sep
echo Config done!
echo $sep
get_opt "Start install?" y
if [ "$my_opt" != "y" ]; then
    exit 1
fi

if [ "$my_auto_part" = "y" ]; then
    make_part
    get_part_auto
fi

mkfs.fat $boot_part && mkfs.ext4 -F $sys_part

if [ "$my_file_system" = "1" ]; then
    mkfs.btrfs -f $sys_part
else
    mkfs.ext4 -F $sys_part
fi

if [ "$my_gui" != "0" ]; then
   my_pacman+=(xorg xfce4 xfce4-taskmanager unzip alsa-utils xfce4-pulseaudio-plugin pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-jack pulseaudio-lirc pavucontrol lib32-alsa-plugins lib32-alsa-lib lib32-libpulse)
fi

if [ "$my_gui" = "2" ]; then
   my_pacman+=(chromium xfce4-goodies)
fi

mount $sys_part /mnt && mount --mkdir $boot_part /mnt/boot/efi

timedatectl set-ntp true
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
reflector -a 48 -c $iso -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist && pacman -Sy
pacman -S --noconfirm archlinux-keyring
pacstrap -K /mnt "${my_pacman[@]}" --noconfirm --needed
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
cp /etc/pacman.conf /mnt/etc/pacman.conf
echo "keyserver hkp://keyserver.ubuntu.com" >> /mnt/etc/pacman.d/gnupg/gpg.conf
genfstab -U /mnt > /mnt/etc/fstab
ln -sf /mnt/usr/share/zoneinfo/$time_zone /mnt/etc/localtime
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
echo  en > /mnt/etc/vconsole.conf
echo $my_host_name > /mnt/etc/hostname

if [ "$my_make_swap" = "y" ]; then
    make_swap   
fi

echo ================= BASE INSTALL DONE

echo -ne '
hwclock --systohc
sed -i "s/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen
locale-gen
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
chown $my_user /root
echo AllowUsers $my_user >> /etc/ssh/sshd_config
echo "$my_user:$my_pass" | chpasswd

systemctl disable dhcpcd
systemctl stop dhcpcd
systemctl enable NetworkManager.service

TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
if [[  $TOTAL_MEM -gt 8000000 ]]; then
sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$nc\"/g" /etc/makepkg.conf
sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /etc/makepkg.conf
fi

if [ "$my_drivers" != "0" ]; then
    #VIDEO
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
        systemctl enable vmware-vmblock-fuse    
    fi

    #AUDIO
    pacman -S --noconfirm --needed alsa-utils

fi


if [ "$my_drivers" = "2" ]; then
   pacman -S --noconfirm --needed wine winetricks libva-utils lib32-mesa
fi

' > /mnt/post.sh

if [ "$my_user_autologin" = "y" ]; then
echo -ne '
mkdir -p /etc/systemd/system/getty@tty1.service.d/
echo -ne "
[Service]
ExecStart=
ExecStart=-/usr/bin/agetty -a $my_user - \$TERM
" > /etc/systemd/system/getty@tty1.service.d/override.conf
echo Autologin done
' >> /mnt/post.sh 
fi

if [ "$my_gui_autostart" = "y" ]; then
echo -ne '
echo -ne "
if [[ ! \$DISPLAY && \$XDG_VTNR -eq 1 ]]; then
    startxfce4
fi
" > /home/$my_user/.bash_profile && chown $my_user /home/$my_user/.bash_profile
' >> /mnt/post.sh
else
 echo -ne '
echo -ne "
df -h /
echo \"
                                       ▄▄▄▄▄▄   ▄▄▄▄▄▄      ▄▄    
                  ▟█▙                  █        █    █       █    
                 ▟███▙                 █▄▄▄▄▄   █▄▄▄▄█   █▄▄▄█    
                ▟█████▙                
               ▟███████▙               Default commands: mc htop ncdu vim sudo
              ▂▔▀▜██████▙            If u installed AUR: yay pacseek
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
\"
" > /home/$my_user/.bash_profile && chown $my_user /home/$my_user/.bash_profile
' >> /mnt/post.sh
fi

echo -ne "\nrm -rf post.sh" >> /mnt/post.sh && chmod +x /mnt/post.sh && arch-chroot /mnt ./post.sh

if [ "$my_aur" = "y" ]; then
# my_user=cojmar
arch-chroot -u $my_user /mnt /bin/sh -c '
cd /home/$my_user
sudo pacman -S --needed --noconfirm git base-devel && git clone https://aur.archlinux.org/yay-bin.git 
cd yay-bin && makepkg -si --noconfirm && cd .. && rm -rf yay-bin
yay
yay -Syu --noconfirm pacseek ${my_extra} && yay -Yc --noconfirm
'
else
arch-chroot /mnt /bin/sh -c '
pacman -Syu --needed --noconfirm ${my_extra}
'
fi

arch-chroot /mnt /bin/sh -c '
rm -rf /var/cache
chown -R root /root
'
sync
# clear
df -h /mnt
echo "
                                       ▄▄▄▄▄▄   ▄▄▄▄▄▄      ▄▄    
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
printf "%s" "Arch installed, reboot? (leave blank for yes) : " && read do_reb && if [[ -z "$do_reb" ]]; then reboot;fi