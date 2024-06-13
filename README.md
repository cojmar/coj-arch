```

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
```
download iso (https://archlinux.org/download/)

start iso in a VM or on a real machine from a usb stick  
part your disk how u see fit  
u can use `cfdisk` example: make hdd GPT, 1 efi partition 1M, rest of hdd linux file system  
if cfdisk dosen't see your hdd use `fidisk -l` to identify your hdd name and use `cfdisk name` example: `cfdisk /dev/sda1`

run the install command
```
bash <(curl -L https://raw.githubusercontent.com/cojmar/coj-arch/main/install.sh)
```
 
