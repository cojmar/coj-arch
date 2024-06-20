#!/usr/bin/env bash
#INIT 
#DEV export my_url="http://192.168.0.101:5500" && bash <(curl -L ${my_url}/install.sh)
export sep=$(echo -ne "\n===========================\n \n")
export my_pacman=(base linux linux-firmware archlinux-keyring grub efibootmgr openssh dhcpcd sudo mc htop ncdu vim networkmanager dhclient unzip neofetch)
export my_extra=""
export my_gui_autostart=n
export my_drivers=0
export my_gui=0
export my_aur=y
if [[ -z "$my_url" ]]; then export my_url="https://raw.githubusercontent.com/cojmar/coj-arch/main";fi

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
    echo $sep
    echo File system type
    echo $sep
    echo -ne "1: ext4\n2: btrfs\n"
    get_opt "File system type" "1"
    export my_file_system=$my_opt
     if [ $my_file_system = '2' ];then 
        echo btrfs 
    else 
        echo ext4
    fi

    my_def_swap_opt=n 
    TOTAL_MEM=$(cat /proc/meminfo | grep -i 'memtotal' | grep -o '[[:digit:]]*')
    if [[  $TOTAL_MEM -lt 4000000 ]]; then
        my_def_swap_opt=y 
    fi

    
}
# USER
function get_password() { # gets password to be used
    my_rand_pass=$(openssl rand -base64 12)
    get_opt "Please enter password: " $my_rand_pass
    pass1=$my_opt
    get_opt "Please re-enter password: " $my_rand_pass
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
    get_opt 'GUI (xorg xorg-xinit video drivers)' "n"
    echo $my_opt
    if [ "$my_opt" = "n" ]; then
        export my_gui=0
        get_opt 'Install video drivers and alsa-utils for alsamixer ?' "n"
        echo $my_opt
        if [ "$my_opt" = "y" ]; then
            export my_drivers=1    
        fi
    else
        export my_gui=1
        export my_drivers=1
        if [ "$my_aur" = "y" ]; then
        echo AUR detected, you can typein AUR browsers too, example: brave        
        fi
        get_opt 'Add Browser? (browser name or n for no) :' "chromium"
        if [ "$my_opt" != "n" ]; then        
        export my_extra+=" ${my_opt}"
        fi
        echo $my_opt
        echo $sep
        echo Desktop Env
        echo $sep
        echo -ne "1: none\n2: KDE plasma\n3: xfce4\n4: cinnamon\n"
        get_opt 'Desktop Env: ' "1"
  
        if [ "$my_opt" = "1" ]; then       
            get_opt 'Autostart GUI app? (app name or n for no) :' "n"  
            echo $my_opt
            if [ "$my_opt" != "n" ]; then 
                export my_gui_autostart=$my_opt
            fi
        else
            export my_gui=$my_opt
        fi        
        echo $sep        
        echo 'Gaming'
        echo $sep
        echo adds wine-staging winetricks lutris and WineDependencies described at this URL:
        echo https://github.com/lutris/docs/blob/master/WineDependencies.md
        get_opt 'Optimise for Gaming ?' "y"
        echo $my_opt
        if [ "$my_opt" = "y" ]; then
            export my_drivers=2      
        fi        
    fi
}
# detecting country and timezone
iso=$(curl -4 ifconfig.co/country-iso) && time_zone="$(curl --fail https://ipapi.co/timezone)" 
clear 
# minimal config
echo $sep && echo  Welcome to cojmar arch
set_disk
echo $sep
echo Base config
echo $sep
get_opt "Host name (computer name)" "cojarch"
my_host_name=$my_opt
echo $my_host_name
set_user    
echo $sep
echo Template
echo $sep
echo -ne "1: custom\n2: AUR server\n3: AUR desktop + brave\n"
get_opt "Template:" "1"
export my_template=$my_opt
# templates

if [ "$my_opt" = "2" ]; then
    export my_make_swap=$my_def_swap_opt
    export my_user_autologin=y    
    
    export my_extra=""
elif [ "$my_opt" = "3" ]; then
    export my_make_swap=$my_def_swap_opt
    export my_user_autologin=y
    export my_extra+=" brave"
    export my_drivers=2    

    echo $sep
    echo DESKTOP ENV
    echo $sep
    echo -ne "1: KDE plasma \n2: xfce4\n3: cinnamon\n"
    get_opt "DESKTOP ENV:" "1"
    export my_gui=$(($my_opt + 1))
    export my_use_template=$my_gui
else #default 1
    get_opt "Autologin" "n"
    export my_user_autologin=$my_opt
    echo $my_user_autologin
    echo $sep
    get_opt "Make Swap?" $my_def_swap_opt
    my_make_swap=$my_opt
    echo $my_make_swap
    echo $sep
    echo Optional config    
    echo $sep  
    get_opt "AUR (adds git, yay and pacseek aur helpers)" "n"
    export my_aur=$my_opt
    echo $my_aur 
    set_gui    
    echo $sep
        if [ "$my_aur" = "y" ]; then
        echo AUR detected, you can typein AUR packages too        
    fi
    get_opt "Extra packages" ""
    export my_extra+=" ${my_opt}"
    echo $my_opt
    echo ""
    echo $sep
    echo Config done!
    echo $sep

    get_opt "Start install?" y
    if [ "$my_opt" != "y" ]; then
        exit 1
    fi
fi
# start the install

IFS=' ' read -r my_extra <<< $my_extra
if [ "$my_aur" != "y" ]; then
my_pacman+=($my_extra)
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
    my_pacman+=(xorg xorg-xinit)
fi

if [ "$my_gui" = "2" ]; then
    export my_gui_autostart="startplasma-x11"
    my_pacman+=(plasma-meta konsole dolphin)    
fi

if [ "$my_gui" = "3" ]; then
    export my_gui_autostart="startxfce4"
    my_pacman+=(xfce4 xfce4-taskmanager alsa-utils xfce4-pulseaudio-plugin pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-jack pulseaudio-lirc pavucontrol lib32-alsa-plugins lib32-alsa-lib lib32-libpulse)
fi

if [ "$my_gui" = "4" ]; then
    export my_gui_autostart="cinnamon-session"
    my_pacman+=(cinnamon konsole)
fi
# drivers

if [ "$my_drivers" != "0" ]; then
    #VIDEO
    if grep -E "NVIDIA|GeForce" <<< ${gpu_type}; then
        my_pacman+=(nvidia)
   
    elif lspci | grep 'VGA' | grep -E "Radeon|AMD"; then
        my_pacman+=(xf86-video-amdgpu)
    elif grep -E "Integrated Graphics Controller" <<< ${gpu_type}; then
        my_pacman+=(libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa)
    elif grep -E "Intel Corporation UHD" <<< ${gpu_type}; then
        my_pacman+=(libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa)
    else
        my_pacman+=(gtkmm open-vm-tools xf86-video-vmware xf86-input-vmmouse libva-utils lib32-mesa)        
    fi
    #AUDIO
    my_pacman+=(alsa-utils)
fi

if [ "$my_drivers" = "2" ]; then
   my_pacman+=(winetricks zenity lutris gamemode vulkan-tools)
   #WineDependencies 
   my_pacman+=(wine-staging giflib lib32-giflib libpng lib32-libpng libldap lib32-libldap gnutls lib32-gnutls mpg123 lib32-mpg123 openal lib32-openal v4l-utils lib32-v4l-utils libpulse lib32-libpulse libgpg-error lib32-libgpg-error alsa-plugins lib32-alsa-plugins alsa-lib lib32-alsa-lib libjpeg-turbo lib32-libjpeg-turbo sqlite lib32-sqlite libxcomposite lib32-libxcomposite libxinerama lib32-libgcrypt libgcrypt lib32-libxinerama ncurses lib32-ncurses ocl-icd lib32-ocl-icd libxslt lib32-libxslt libva lib32-libva gtk3 lib32-gtk3 gst-plugins-base-libs lib32-gst-plugins-base-libs vulkan-icd-loader lib32-vulkan-icd-loader)
fi

# determine processor type and install microcode
proc_type=$(lscpu)
if grep -E "GenuineIntel" <<< ${proc_type}; then
    my_pacman+=(intel-ucode)
elif grep -E "AuthenticAMD" <<< ${proc_type}; then 
    my_pacman+=(amd-ucode)
fi

if [ "$my_aur" = "y" ]; then
    my_pacman+=(git base-devel)
fi

mount $sys_part /mnt && mount --mkdir $boot_part /mnt/boot/efi

# set trheds to makepkg.conf
nc=$(($(grep -c ^processor /proc/cpuinfo) * 2))
sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$nc\"/g" /etc/makepkg.conf
sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /etc/makepkg.conf

timedatectl set-ntp true
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
var1="ParallelDownloads = 5" && var2="ParallelDownloads = 10" && sed -i -e "s/$var1/$var2/g" /etc/pacman.conf
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
reflector -a 48 -c $iso -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist && pacman -Sy
pacman -S --noconfirm archlinux-keyring neofetch unzip
pacstrap -K /mnt "${my_pacman[@]}" --noconfirm --needed
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
cp /etc/pacman.conf /mnt/etc/pacman.conf
cp /etc/makepkg.conf /mnt/etc/makepkg.conf
echo "keyserver hkp://keyserver.ubuntu.com" >> /mnt/etc/pacman.d/gnupg/gpg.conf
genfstab -U /mnt > /mnt/etc/fstab
ln -sf /mnt/usr/share/zoneinfo/$time_zone /mnt/etc/localtime
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
echo  en > /mnt/etc/vconsole.conf
echo $my_host_name > /mnt/etc/hostname

if [ "$my_make_swap" = "y" ]; then
    make_swap   
fi

echo ================= MAIN INSTALL DONE

echo -ne '
hwclock --systohc
sed -i "s/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/" /etc/locale.gen
locale-gen
pacman -Syy
systemctl enable sshd 

if [ "$my_drivers" != "0" ]; then
    #VIDEO
    if grep -E "NVIDIA|GeForce" <<< ${gpu_type}; then        
        nvidia-xconfig
    elif lspci | grep 'VGA' | grep -E "Radeon|AMD"; then
        echo ""
    elif grep -E "Integrated Graphics Controller" <<< ${gpu_type}; then
        echo ""
    elif grep -E "Intel Corporation UHD" <<< ${gpu_type}; then
        echo ""
    else        
        systemctl enable vmtoolsd
        systemctl enable vmware-vmblock-fuse    
    fi
fi

useradd -U $my_user
echo "$my_user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$my_user
chmod 0440 /etc/sudoers.d/$my_user
mkdir /home/$my_user && chown $my_user /home/$my_user 
echo AllowUsers $my_user >> /etc/ssh/sshd_config
echo "$my_user:$my_pass" | chpasswd

systemctl disable dhcpcd
systemctl stop dhcpcd
systemctl enable NetworkManager.service

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

if [ "$my_gui_autostart" != "n" ]; then
echo -ne '
echo -ne "
if [[ ! \$DISPLAY && \$XDG_VTNR -eq 1 ]]; then
    startx &>/dev/null    
fi
" > /home/$my_user/.bash_profile

echo -ne "
${my_gui_autostart}
" > /home/$my_user/.xinitrc

' >> /mnt/post.sh
fi

echo -ne '
echo -ne "
neofetch
df -h / 
echo \"
  Default commands: mc htop ncdu vim sudo unzip
If u installed AUR: git yay pacseek
\"
" >> /home/$my_user/.bash_profile
' >> /mnt/post.sh


#init xorg if display 

if [ "$my_gui" != "0" ]; then
if [[ ! \$DISPLAY && \$XDG_VTNR -eq 1 ]]; then
echo -ne '
X -configure
cp /root/xorg.conf.new /etc/X11/xorg.conf
' >> /mnt/post.sh
fi
fi

echo -ne "\nchown -R ${my_user} /root\nrm -rf post.sh" >> /mnt/post.sh && chmod +x /mnt/post.sh && arch-chroot /mnt ./post.sh

# adding AUR if case and EXTRA with aur

if [ "$my_aur" = "y" ]; then
echo ================= INSTALLING AUR
# my_user=cojmar
arch-chroot -u $my_user /mnt /bin/sh -c '
cd ~
git clone https://aur.archlinux.org/yay-bin.git 
cd yay-bin && makepkg -si --noconfirm && cd .. && rm -rf yay-bin
yay --noconfirm 
yay -Syu --noconfirm pacseek "${my_extra[@]}" && yay -Yc --noconfirm
'
fi


if [[ -z "$my_use_template" ]]; then 
echo no custom templates
else
echo $my_use_template
curl -L ${my_url}/gui_templates/${my_use_template}.zip > home.zip
cp home.zip /mnt/home/$my_user/home.zip
cd /mnt/home/${my_user}
unzip -o home.zip
rm -rf home.zip
fi 

# making bootloader and cleaning
arch-chroot /mnt /bin/sh -c '
    chown -R root /root 
    chown -R $my_user /home/$my_user/
    grub-install --recheck ${my_disk} && grub-mkconfig -o /boot/grub/grub.cfg
    var1="timeout=5" && var2="timeout=1" && sed -i -e "s/$var1/$var2/g" /boot/grub/grub.cfg
    pacman -R grub efibootmgr dhcpcd --noconfirm
    rm -rf /var/cache
    rm -rf /var/log
    mkdir /var/log
    rm -rf /root/.cache
'

sync
if [ "$my_template" = "1" ]; then
neofetch
df -h /mnt
echo "
  Default commands: mc htop ncdu vim sudo unzip
If u installed AUR: git yay pacseek
"
get_opt "Arch installed, reboot?" "y"
if [ "$my_opt" = "y" ]; then
reboot
fi
else
reboot
fi