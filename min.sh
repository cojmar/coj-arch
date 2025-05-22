#!/usr/bin/env bash
#INIT 
#DEV export my_url="http://192.168.0.101:5500" && bash <(curl -L ${my_url}/user.sh)
export sep=$(echo -ne "\n===========================\n \n")
export my_pacman=()
export my_sudo_pass=y

get_opt() {   
    echo -ne '\n' 
    printf "%s" "$1 (default $2) : " && read my_opt && if [[ -z "$my_opt" ]]; then my_opt=$2;fi    
    # echo $my_opt
}

# USER
get_password() { # gets password to be used
    my_rand_pass=$(openssl rand -base64 32)
    if [[ -z "$my_rand_pass" ]]; then my_rand_pass=123456;fi
    get_opt "Require password for sudo?" "n"
    export my_sudo_pass=$my_opt

    if [ "$my_sudo_pass" = "y" ];then
        get_opt "Please enter password: " $my_rand_pass
        pass1=$my_opt
        get_opt "Please re-enter password: " $my_rand_pass
        pass2=$my_opt
    else
           pass1=$my_rand_pass
           pass2=$my_rand_pass
    fi
    if [[ "$pass1" == "$pass2" ]]; then
        export my_pass=$pass1    

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

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root"
  exit 1
fi

set_user
if [ "$my_sudo_pass" = "y" ]; then
    export my_sudo_pass=""
else
    export my_sudo_pass="NOPASSWD:"
fi

pacman -S --noconfirm base-devel sudo mc htop ncdu unzip fastfetch wget git

if id "$my_user" &>/dev/null; then
  echo "User $my_user already exists"
else
    useradd -m -G wheel $my_user
    echo "${my_user}:${my_pass}" | chpasswd
    echo "${my_user} ALL=(ALL) ${my_sudo_pass} ALL" > /etc/sudoers.d/${my_user}   
    chmod 0440 /etc/sudoers.d/${my_user}
fi

nc=$(($(grep -c ^processor /proc/cpuinfo) * 1))
sed -i "s/#MAKEFLAGS="-j2"/MAKEFLAGS="-j$nc"/g" /etc/makepkg.conf
sed -i "s/COMPRESSXZ=(xz -c -z -)/COMPRESSXZ=(xz -c -T $nc -z -)/g" /etc/makepkg.conf
# set pacman.conf
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf
sed -i 's/^#Color/Color/' /etc/pacman.conf
var1="ParallelDownloads = 5" && var2="ParallelDownloads = 10" && sed -i -e "s/$var1/$var2\nILoveCandy\nNoExtract = usr\/share\/locale\/\* !usr\/share\/locale\/uk\*\nNoExtract = usr\/share\/doc\/\*\n\nNoExtract = usr\/share\/man\/\*/g" /etc/pacman.conf
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf

echo Done!



