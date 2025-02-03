#!/usr/bin/env bash
#INIT 
#DEV export my_url="http://192.168.0.101:5500" && bash <(curl -L ${my_url}/termux.sh)
export sep=$(echo -ne "\n===========================\n \n")
export my_pacman=(base-devel sudo mc htop ncdu unzip fastfetch wget git)
export my_sudo_pass=y
export my_outside=n

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


# USER
get_password() { # gets password to be used
    my_rand_pass=$(openssl rand -base64 32)
    if [[ -z "$my_rand_pass" ]]; then my_rand_pass=123456;my_outside=y;fi
    get_opt "Please enter password: " $my_rand_pass
    pass1=$my_opt
    get_opt "Please re-enter password: " $my_rand_pass
    pass2=$my_opt   
    if [[ "$pass1" == "$pass2" ]]; then
        export my_pass=$pass1
        get_opt "Require password for sudo?" "n"
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

# minimal config
echo $sep && echo  "Welcome to cojmar arch for termux"


echo Base config
set_user    
echo $sep

get_opt "Add GUI (i3 window manager both native and in arch)" "y"
export my_gui=$my_opt
if [ "$my_gui" = "y" ];then
    my_pacman+=(i3-wm dmenu i3status xfce4-terminal polybar)
fi

if [ "$my_outside" = "y" ];then
get_opt "Clean install?:" "y"
export my_clean_install=$my_opt
fi

if [ "$my_sudo_pass" = "y" ]; then
    export my_sudo_pass=""
else
    export my_sudo_pass="NOPASSWD:"
fi
# POST ROOT
post=$(echo -ne "
awk '{if (\$0 ~ /^#ParallelDownloads = 5/) {print \"ParallelDownloads = 15\"; print \"ILoveCandy\";} else print \$0}' /etc/pacman.conf > /etc/pacman.conf.tmp && mv /etc/pacman.conf.tmp /etc/pacman.conf
&&
awk '{if (\$0 ~ /^#MAKEFLAGS=/) print \"MAKEFLAGS=\\\"j2\\\"\"; else print \$0}' /etc/makepkg.conf > /etc/makepkg.conf.tmp && mv /etc/makepkg.conf.tmp /etc/makepkg.conf
&&
pacman -Sy --noconfirm
&&
pacman -Syu --noconfirm
&&
pacman -S ${my_pacman[@]} --noconfirm
&&
echo \"${my_user} ALL=(ALL) ${my_sudo_pass} ALL\" > /etc/sudoers.d/${my_user}   
&&
chmod 0440 /etc/sudoers.d/${my_user}
&&
useradd -m -G wheel ${my_user}
&&
echo \"${my_user}:${my_pass}\" | chpasswd
&&
cd /home/${my_user}
&&
curl -L ${my_url}/home_templates/termux.zip > home.zip
&&
unzip -o home.zip
&&
rm -rf home.zip
")

# POST USER
post_user=$(echo -ne "
cd ~
&&
git clone https://aur.archlinux.org/yay-bin.git 
&&
cd yay-bin && makepkg -si --noconfirm && cd .. && rm -rf yay-bin
&&
yay --noconfirm 
&&
yay -Syu --noconfirm pacseek && yay -Yc --noconfirm
")


mkdir -p ~/shared_folder
echo $post > ~/shared_folder/post.sh
echo $post_user > ~/shared_folder/post_user.sh

# start the install
echo $sep
echo ================= START INSTALL
echo $sep
export my_timestamp1=$(date +%s)
if [ "$my_outside" = "y" ];then
if [ "$my_clean_install" = "y" ];then
pkg update -y
pkg upgrade -y
pkg install -y x11-repo
pkg install -y tur-repo
pkg install -y termux-x11-nightly
pkg install -y pulseaudio
pkg install -y proot-distro
pkg install -y mc
pkg install -y htop

if [ "$my_gui" = "y" ];then
    pkg install -y i3
    pkg install -y code-oss
fi

proot-distro install archlinux
proot-distro reset archlinux
fi
proot-distro login archlinux --bind ~/shared_folder:/root/shared_folder -- /bin/bash -c 'source /root/shared_folder/post.sh'

proot-distro login archlinux --bind ~/shared_folder:/root/shared_folder -- /bin/bash -c "su - ${my_user} -c 'source /root/shared_folder/post_user.sh'"

rm -rf ~/shared_folder
echo echo -ne "
#!/data/data/com.termux/files/usr/bin/bash

# Kill open X11 processes
kill -9 \$(pgrep -f "termux.x11") 2>/dev/null

# Enable PulseAudio over Network
pulseaudio --start --load=\"module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1\" --exit-idle-time=-1

# Prepare termux-x11 session
export XDG_RUNTIME_DIR=\${TMPDIR}
termux-x11 :0 >/dev/null &

# Wait a bit until termux-x11 gets started.
sleep 3

# Launch Termux X11 main activity
am start --user 0 -n com.termux.x11/com.termux.x11.MainActivity > /dev/null 2>&1
sleep 1

# Argument -- acts as terminator of proot-distro login options processing.
# All arguments behind it would not be treated as options of PRoot Distro.
proot-distro login archlinux --shared-tmp -- /bin/bash -c  'export PULSE_SERVER=127.0.0.1 && export XDG_RUNTIME_DIR=\${TMPDIR} && su - ${my_user} -c \"env DISPLAY=:0 i3\"'

exit 0
" > arch.sh
chmod +x arch.sh
echo $sep
echo "Use ./arch.sh to start arch"
echo $sep
export my_timestamp2=$(date +%s)
export duration=$(( $my_timestamp2 - $my_timestamp1 ))
echo install duration: $(convertsecs $duration)
echo $sep
get_opt "Start Arch now?" "y"

if [ "$my_opt" = "y" ];then
./arch.sh
fi

fi
