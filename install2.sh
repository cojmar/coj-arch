#!/usr/bin/env bash
#INIT
export sep=$(echo -ne "\n===========================\n \n")
export my_pacman=(base linux linux-firmware archlinux-keyring grub efibootmgr openssh dhcpcd sudo mc htop ncdu vim)
get_opt() {   
    echo -ne '\n' 
    printf "%s" "$1 (default $2) : " && read my_opt && if [[ -z "$my_opt" ]]; then my_opt=$2;fi    
    echo $my_opt
}
get_opt_sep() {
    echo $sep
    get_opt $1 $2
}
#DISK
get_disk() { # gets install disk
    echo $sep && echo "Available disks"
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
    echo $sep
    echo Disk Operations    
    get_disk
    get_opt "Auto partition the disk?" "y"
    if [ $my_opt = 'y' ];then 
        make_part
        get_part_auto
    else 
        get_part
    fi
    #get_opt "File system type [1:btrfs 2:ext4]" "1"
    #export my_file_system=$my_opt
    get_opt "Make Swap?" "n"
    my_make_swap=$my_opt
}
# USER
get_password() { # gets password to be used
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
set_user() { # runs all the user settings
    echo $sep
    echo User
    get_opt "Username" "cojmar"
    export my_user=$my_opt
    echo $my_user
    get_password
    get_opt "Autologin" "n"
    export my_user_autologin=$my_opt
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


iso=$(curl -4 ifconfig.co/country-iso) && time_zone="$(curl --fail https://ipapi.co/timezone)" 
umount -A --recursive /mnt
clear 
echo $sep && echo  Welcome to cojmar arch
set_disk
set_user
echo $sep
echo Base config
# HOST
get_opt_sep "Host name" "cojarch"
my_host_name=$my_opt
echo $my_host_name

mkfs.fat $boot_part && mkfs.ext4 -F $sys_part
sync
mount $sys_part /mnt && mount --mkdir $boot_part /mnt/boot/efi

timedatectl set-ntp true
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
reflector -a 48 -c $iso -f 5 -l 20 --sort rate --save /etc/pacman.d/mirrorlist && pacman -Sy
pacman -S --noconfirm archlinux-keyring
pacstrap -K /mnt ${my_pacman} --noconfirm --needed
cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d/mirrorlist
cp /etc/pacman.conf /mnt/etc/pacman.conf
echo "keyserver hkp://keyserver.ubuntu.com" >> /mnt/etc/pacman.d/gnupg/gpg.conf
genfstab -U /mnt > /mnt/etc/fstab
ln -sf /mnt/usr/share/zoneinfo/$time_zone /mnt/etc/localtime
echo LANG=en_US.UTF-8 > /mnt/etc/locale.conf
echo  en > /mnt/etc/vconsole.conf
echo $my_host_name > /mnt/etc/hostname
echo $my_make_swap
if [ "$my_make_swap" = "n" ]; then
    echo no swap
else
    make_swap
fi
