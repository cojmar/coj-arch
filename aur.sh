cd ~ && git clone https://aur.archlinux.org/yay-bin.git && cd yay-bin && makepkg -si --noconfirm && cd .. && rm -rf yay-bin && yay --noconfirm && yay -Syu --noconfirm pacseek && yay -Yc --noconfirm