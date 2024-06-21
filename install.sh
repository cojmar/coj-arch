#!/usr/bin/env bash
#INIT 
#DEV export my_url="http://192.168.0.101:5500" && bash <(curl -L ${my_url}/install.sh)
export sep=$(echo -ne "\n===========================\n \n")
export my_pacman=(base linux linux-firmware archlinux-keyring grub efibootmgr openssh dhcpcd sudo mc htop ncdu vim networkmanager dhclient unzip fastfetch)
export my_extra=""
export my_gui_autostart=n
export my_drivers=0
export my_gui=0
export my_aur=y
export my_sudo_pass=y
export my_add_vnc=n
export my_more="
echo sloboz cu ochii roz
"
export my_startx="
if [[ ! \$DISPLAY && \$XDG_VTNR -eq 1 ]]; then
    startx &>/dev/null
fi
"


if [[ -z "$my_url" ]]; then export my_url="https://raw.githubusercontent.com/cojmar/coj-arch/main";fi

get_opt() {   
    echo -ne '\n' 
    printf "%s" "$1 (default $2) : " && read my_opt && if [[ -z "$my_opt" ]]; then my_opt=$2;fi    
    # echo $my_opt
}

convertsecs() {
 ((h=${1}/3600))
 ((m=(${1}%3600)/60))
 ((s=${1}%60))
 printf "%02d:%02d:%02d\n" $h $m $s
}

#DISK
get_disk() { # gets install disk
    echo $sep
    echo "Available disks"
    lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}'
    get_opt "Install on disk" "1"
    
    export my_disk=$(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="disk"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}' | awk 'NR=='$my_opt' {print $2}')
    echo $my_disk
}
make_part() { # makes partitions on install disk
    # disk prep
    sgdisk -Z ${my_disk} # zap all on disk
    sgdisk -a 2048 -o ${my_disk} # new gpt disk 2048 alignment

    sgdisk -n 2::+1M --typecode=2:ef00:'EFIBOOT' ${my_disk} # partition 1 (EFI)
    sgdisk -n 3::-0 --typecode=3:8300:'ROOT' ${my_disk} # partition 2 (OS) 
    partprobe ${my_disk} 
}
get_part_auto() { # get partitions automaticaly based on selected disk
    boot_part=$(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="part"{print "/dev/"$2" -  "$3}' | awk -v var="$my_disk" '$1 ~ var {print $0}' | awk '{print NR,$0}' | awk 'NR=='1' {print $2}')
    echo BOOT $boot_part   

    sys_part=$(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="part"{print "/dev/"$2" -  "$3}' | awk -v var="$my_disk" '$1 ~ var {print $0}' | awk '{print NR,$0}' | awk 'NR=='2' {print $2}')
    echo OS $sys_part
}
get_part() { # manualy select partitions
    echo $sep && echo "Available partitions"
    lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="part"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}'
    
    get_opt "Boot partition EFI" "1"    
    boot_part=$(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="part"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}' | awk 'NR=='$my_opt' {print $2}')
    echo $boot_part
    
    get_opt "OS partition" "2"
    sys_part=$(lsblk -n --output TYPE,KNAME,SIZE | awk '$1=="part"{print "/dev/"$2" -  "$3}' | awk '{print NR,$0}' | awk 'NR=='$my_opt' {print $2}')
    echo $sys_part 
}
set_disk() { # runs all disk settings
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
get_password() { # gets password to be used
    my_rand_pass=$(openssl rand -base64 32)
    get_opt "Please enter password: " $my_rand_pass
    pass1=$my_opt
    get_opt "Please re-enter password: " $my_rand_pass
    pass2=$my_opt   
    if [[ "$pass1" == "$pass2" ]]; then
        export my_pass=$pass1
        get_opt "Require password for sudo?" "y"
        export my_sudo_pass=$my_opt

    else
        echo -ne "ERROR! Passwords do not match. \n"
        get_password
    fi
}
set_user() { # runs all the user settings
    echo $sep  
    get_opt "Username" "cojmar"
    export my_user=$my_opt
    echo $my_user
    get_password    
}
make_swap(){
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
set_gui(){
    export my_gui_autostart=n
    export my_drivers=0
    get_opt 'GUI (xorg xorg-xinit video drivers)' "n"
    echo $my_opt
    if [ "$my_opt" = "n" ]; then
        export my_gui=0
        get_opt 'Install video drivers and alsa-utils for alsamixer ?' "n"
        echo $my_opt
        if [ "$my_opt" = "y" ]; then
            export my_drivers=3
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
echo $sep && echo  "Welcome to cojmar arch
AUR stands for \"Arch User Repository\" and adds access to latest bleeding edge stuf
"
echo $sep
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
echo -ne "1: custom\n2: Server de AUR\n3: Desktop de AUR\n4: Web App in chromium -kiosk\n5: xtem GUI de AUR (DEV)"
get_opt "Template:" "1"
echo $my_opt
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
elif [ "$my_opt" = "4" ]; then
    echo $sep
    echo Web App URL
     echo $sep
    get_opt "URL" "https://youtube.com"
    echo $my_opt
    export my_gui_autostart="
    while :
        do
            chromium --force-dark-mode --enable-features=WebUIDarkMode --start-maximized --start-fullscreen --kiosk ${my_opt}
        done
    "
    export my_startx="
    if [[ ! \$DISPLAY && \$XDG_VTNR -eq 1 ]]; then        
            startx &>/dev/null         
    fi
    "
    export my_make_swap=n
    export my_user_autologin=y
    export my_gui=1
    export my_extra+=" chromium"
    export my_drivers=3
    export my_aur=n
elif [ "$my_opt" = "5" ]; then
    export my_make_swap=$my_def_swap_opt
    export my_user_autologin=y
    export my_gui=1
    export my_pacman+=(xterm x11vnc)
    export my_drivers=3        
    export my_gui_autostart="xterm -fa 'Monospace' -fs 14 -maximized -bg black -fg white"
    export my_add_vnc=y
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
echo $sep
echo ================= START INSTALL
echo $sep
export my_timestamp1=$(date +%s)
IFS=' ' read -r my_extra <<< $my_extra
if [ "$my_aur" != "y" ]; then
my_pacman+=($my_extra)
fi

if [ "$my_auto_part" = "y" ]; then
    make_part
    get_part_auto
fi

mkfs.fat $boot_part && mkfs.ext4 -F $sys_part

if [ "$my_file_system" = "2" ]; then
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
    my_pacman+=(xfce4 xfce4-taskmanager alsa-utils xfce4-pulseaudio-plugin pulseaudio pulseaudio-alsa pulseaudio-bluetooth pulseaudio-jack pulseaudio-lirc pavucontrol lib32-alsa-plugins lib32-alsa-lib lib32-libpulse dolphin)
fi

if [ "$my_gui" = "4" ]; then
    export my_gui_autostart="cinnamon-session"
    my_pacman+=(cinnamon konsole dolphin)
fi
# drivers
if [ "$my_drivers" = "3" ]; then
    if grep -E "NVIDIA|GeForce" <<< ${gpu_type}; then
        my_pacman+=(xf86-video-nouveau)
    elif lspci | grep 'VGA' | grep -E "Radeon|AMD"; then
        my_pacman+=(xf86-video-amdgpu)
    elif grep -E "Integrated Graphics Controller" <<< ${gpu_type}; then
        my_pacman+=(xf86-video-intel)
    elif grep -E "Intel Corporation UHD" <<< ${gpu_type}; then
        my_pacman+=(xf86-video-intel)
    else
        my_pacman+=(gtkmm open-vm-tools xf86-video-vmware xf86-input-vmmouse libva-utils lib32-mesa)        
    fi
    my_pacman+=(alsa-utils)
else
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
    my_pacman+=(winetricks zenity lutris vulkan-tools)
    #WineDependencies 
    my_pacman+=(wine-staging giflib lib32-giflib libpng lib32-libpng libldap lib32-libldap gnutls lib32-gnutls mpg123 lib32-mpg123 openal lib32-openal v4l-utils lib32-v4l-utils libpulse lib32-libpulse libgpg-error lib32-libgpg-error alsa-plugins lib32-alsa-plugins alsa-lib lib32-alsa-lib libjpeg-turbo lib32-libjpeg-turbo sqlite lib32-sqlite libxcomposite lib32-libxcomposite libxinerama lib32-libgcrypt libgcrypt lib32-libxinerama ncurses lib32-ncurses ocl-icd lib32-ocl-icd libxslt lib32-libxslt libva lib32-libva gtk3 lib32-gtk3 gst-plugins-base-libs lib32-gst-plugins-base-libs vulkan-icd-loader lib32-vulkan-icd-loader)
    fi
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

if [ "$my_add_vnc" = "y" ]; then
my_pacman+=(nodejs npm git)
export my_gui_autostart=$(echo -ne "nohup x11vnc -xkb -noxrecord -noxfixes -noxdamage -display :0 -loop -shared -forever -bg > /dev/null 2>&1 &\ncd noVNC\nnohup npm start > /dev/null 2>&1\n${my_gui_autostart}")
export my_more="
cd /home/${my_user}
git clone https://github.com/cojmar/noVNC.git
cd noVNC
npm i
echo ok
"
fi

mount $sys_part /mnt && mount --mkdir $boot_part /mnt/boot/efi

# set trheds to makepkg.conf
nc=$(($(grep -c ^processor /proc/cpuinfo) * 2))
sed -i "s/#MAKEFLAGS=\"-j2\"/MAKEFLAGS=\"-j$nc\"/g" /etc/makepkg.conf
sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /etc/makepkg.conf

timedatectl set-ntp true
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
var1="ParallelDownloads = 5" && var2="ParallelDownloads = 10" && sed -i -e "s/$var1/$var2\nILoveCandy/g" /etc/pacman.conf
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
reflector -a 48 -c $iso -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist && pacman -Sy
pacman -S --noconfirm archlinux-keyring fastfetch unzip
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
echo $sep
echo ================= MAIN INSTALL DONE
echo $sep

if [ "$my_sudo_pass" = "y" ]; then
    export my_sudo_pass=""
else
    export my_sudo_pass="NOPASSWD:"
fi

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
echo -ne "AllowUsers $my_user\nAllowTcpForwarding yes\nPermitTunnel yes\n" >> /etc/ssh/sshd_config
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
${my_startx}
" > /home/$my_user/.bash_profile

echo -ne "
${my_gui_autostart}
" > /home/$my_user/.xinitrc

' >> /mnt/post.sh
fi

if [ "$my_aur" = "y" ]; then
export my_commands="echo '
    Default commands: mc htop ncdu vim sudo unzip git
AUR package managers: yay (command line) pacseek (command line with GUI)      
'"
else
export my_commands="echo '
Default commands: mc htop ncdu vim sudo unzip      
'"
fi

echo -ne '
echo -ne "
fastfetch
${my_commands}
if [ -f /etc/systemd/system/getty@tty1.service.d/override.conf ]; then
echo \"to remove autologin run this command: sudo rm -rf /etc/systemd/system/getty@tty1.service.d/override.conf
\"
fi

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

echo -ne "\n${my_more}\nchown -R ${my_user} /root\nrm -rf post.sh" >> /mnt/post.sh && chmod +x /mnt/post.sh && arch-chroot /mnt ./post.sh

# adding AUR if case and EXTRA with aur

if [ "$my_aur" = "y" ]; then
echo $sep
echo ================= INSTALLING AUR
echo $sep

arch-chroot -u $my_user /mnt /bin/sh -c '
cd ~
git clone https://aur.archlinux.org/yay-bin.git 
cd yay-bin && makepkg -si --noconfirm && cd .. && rm -rf yay-bin
yay --noconfirm 
yay -Syu --noconfirm pacseek "${my_extra[@]}" && yay -Yc --noconfirm
'
fi


if [[ -z "$my_use_template" ]]; then 
echo ""
else
echo $sep
echo ================= ADDING HOME TEMPLATE
echo $sep
echo $my_use_template
curl -L ${my_url}/home_templates/${my_use_template}.zip > home.zip
cp home.zip /mnt/home/$my_user/home.zip
cd /mnt/home/${my_user}
unzip -o home.zip
rm -rf home.zip
fi 

# making bootloader and cleaning
arch-chroot /mnt /bin/sh -c '
    chown -R root /root 
    chown -R $my_user /home/$my_user/
    echo "$my_user ALL=(ALL) ${my_sudo_pass} ALL" > /etc/sudoers.d/$my_user
    grub-install --recheck ${my_disk} && grub-mkconfig -o /boot/grub/grub.cfg
    var1="timeout=5" && var2="timeout=1" && sed -i -e "s/$var1/$var2/g" /boot/grub/grub.cfg
    pacman -R grub efibootmgr dhcpcd --noconfirm
    rm -rf /var/cache
    rm -rf /var/log
    mkdir /var/log
    rm -rf /root/.cache
'

sync
fastfetch
export my_timestamp2=$(date +%s)

export duration=$(( $my_timestamp2 - $my_timestamp1 ))
echo install duration: $(convertsecs $duration)

if [ "$my_template" = "1" ]; then
get_opt "Arch installed, reboot?" "y"
if [ "$my_opt" = "y" ]; then
reboot
fi
else
echo rebooting in 5
sleep 5
reboot
fi