# !/bin/bash
#
# Architect Installation Framework (2016-2017)
#
# Written by Carl Duff and @mandog for Archlinux
# Heavily modified and re-written by @Chrysostomus to install Manjaro instead
# Contributors: @papajoker, @oberon and the Manjaro-Community.
#
# This program is free software, provided under the GNU General Public License
# as published by the Free Software Foundation. So feel free to copy, distribute,
# or modify it as you wish.

setup_profiles() {
    # setup profiles with either git or package 
    if [[ -e /tmp/.git_profiles ]]; then 
        PROFILES="$DATADIR/profiles"
        clear
        # install git if not already installed
        inst_needed git
        # download manjaro-tools.-isoprofiles git repo
        if [[ -e $PROFILES ]]; then
            git -C $PROFILES pull 2>$ERR
            check_for_error "pull profiles repo" $?
        else
            git clone -b manjaro-architect --depth 1 https://gitlab.manjaro.org/profiles-and-settings/iso-profiles.git $PROFILES 2>$ERR
            check_for_error "clone profiles repo" $?
        fi
    else
        PROFILES="/usr/share/manjaro-tools/iso-profiles"
        # Only show this information box once
        clear
        pacman -Sy --noconfirm $p manjaro-iso-profiles-{base,official,community} 2>$ERR
        check_for_error "update profiles pkgs" $?
    fi
}

enable_services() {
        # Enable services in the chosen profile
        echo "Enabling services"
            eval $(grep -e "enable_systemd=" $profile | sed 's/# //g')
            echo "${enable_systemd[@]}" | xargs -n1 > /tmp/.services
            echo /mnt/usr/lib/systemd/system/* | xargs -n1 | cut -d/ -f7 | sed 's/.service//g' > /tmp/.available_services
            grep -f /tmp/.available_services /tmp/.services > /tmp/.fix && mv /tmp/.fix /tmp/.services
            arch_chroot "systemctl enable $(cat /tmp/.services)" 2>$ERR
            check_for_error "enable $(cat /tmp/.services | tr '\n' ' ')" $?
            arch_chroot "systemctl disable pacman-init" 2>$ERR
            check_for_error "disable pacman-init" $?

            # enable display manager for systemd
            if [[ "$(cat /tmp/.display-manager)" == lightdm ]]; then
                set_lightdm_greeter
                arch_chroot "systemctl enable lightdm" 2>$ERR
                check_for_error "enable lightdm" "$?"
            elif [[ "$(cat /tmp/.display-manager)" == sddm ]]; then
                arch_chroot "systemctl enable sddm" 2>$ERR
                check_for_error "enable sddm" "$?"
            elif [[ "$(cat /tmp/.display-manager)" == gdm ]]; then
                arch_chroot "systemctl enable gdm" 2>$ERR
                check_for_error "enable gdm" "$?"
            else
                check_for_error "no DM installed."
                echo "no display manager was installed"
                sleep 2
            fi
}

install_extra() {
    # Offer to install various "common" packages.
    local options=() nb=0
    cpkgs="manjaro-settings-manager pamac octopi pacli pacui fish fisherman zsh zsh-completions \
      manjaro-zsh-config mhwd-chroot bmenu clonezilla snapper snap-pac manjaro-tools-iso manjaro-tools-base manjaro-tools-pkg"
    for p in ${cpkgs}; do
        ! grep "$p" /mnt/.desktop && options+=("$p" "" off)
    done
    nb="$((${#options[@]}/3))"; (( nb>20 )) && nb=20 # if list too long limit
    DIALOG " $_InstComTitle " --checklist "\n$_InstComBody\n\n$_UseSpaceBar\n  " 0 50 $nb "${options[@]}" 2>${PACKAGES}

    # If at least one package, install.
    if [[ $(cat ${PACKAGES}) != "" ]]; then
        clear
        basestrap -i ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
        check_for_error "basestrap -i ${MOUNTPOINT} $(cat ${PACKAGES})" "$?"
    fi
}

filter_packages() {
        DIALOG " $_PkgList " --infobox "\n$_PlsWaitBody\n " 0 0
        # Parse package list based on user input and remove parts that don't belong to pacman
        # If desktop is selected, add those packages to packages to be installed.
        if [[ -e /mnt/.desktop ]]; then
            cat "$pkgs_src" /mnt/.desktop >> $pkgs_target 2>$ERR
            check_for_error "$FUNCNAME" $?
        else 
            cat "$pkgs_src" >> $pkgs_target 2>$ERR
            check_for_error "$FUNCNAME" $?  
        fi
        
        # Remove any packages tagged with >openrc and remove >systemd tags
        sed -i '/>openrc/d' $pkgs_target
        sed -i 's/>systemd //g' $pkgs_target

        if [[ "$(uname -m)" == "x86_64" ]]; then
            # Remove any packages tagged with >i686 and remove >x86_64 tags
            sed -i '/>i686/d' $pkgs_target
            sed -i '/>nonfree_i686/d' $pkgs_target
            sed -i 's/>x86_64 //g' $pkgs_target
        else
            # Remove any packages tagged with >x86_64 and remove >i686 tags
            sed -i '/>x86_64/d' $pkgs_target
            sed -i '/>nonfree_x86_64/d' $pkgs_target
            sed -i 's/>i686 //g' $pkgs_target
        fi

        # If multilib repo is enabled, install multilib packages
        if grep -q "^[multilib]" /etc/pacman.conf; then
            # Remove >multilib tags
            sed -i 's/>multilib //g' $pkgs_target
            sed -i 's/>nonfree_multilib //g' $pkgs_target
        else
            # Remove lines with >multilib tag
            sed -i '/>multilib/d' $pkgs_target
            sed -i '/>nonfree_multilib/d' $pkgs_target
        fi

        if grep -q ">extra" $pkgs_target; then
            # User to select base|extra profile
            DIALOG " $_ExtraTitle " --no-cancel --menu "\n$_ExtraBody\n " 0 0 2 \
              "1" "full" \
              "2" "minimal" 2>/tmp/.version

            if [[ $(cat /tmp/.version) -eq 2 ]]; then
                check_for_error "selected 'minimal' profile"
                touch /tmp/.minimal
            else
                check_for_error "selected 'full' profile"
                [[ -e /tmp/.minimal ]] && rm /tmp/.minimal
            fi
        fi

        if [[ -e /tmp/.minimal ]]; then
            # Remove >extra tags
            sed -i 's/>basic //g' $pkgs_target
            sed -i '/>extra/d' $pkgs_target
        else
            # Remove >basic tags
            sed -i 's/>extra //g' $pkgs_target
            sed -i '/>basic/d' $pkgs_target
        fi
        # remove >manjaro flags and >sonar flags+pkgs until we support it properly
        sed -i '/>sonar/d' $pkgs_target
        sed -i 's/>manjaro //g' $pkgs_target

        # Does the system have a battery?
        if [[ -z "$(echo /sys/class/power_supply/BAT*)" ]]; then 
          # No battery was detected. Remove TLP
          sed -i '/tlp/d' $pkgs_target
        fi  
        # Remove commented lines
        # remove everything except the first word of every lines
        sed -i 's/\s.*$//' $pkgs_target
        # Remove lines with #
        sed -i '/#/d' $pkgs_target
        # remove KERNEL variable
        sed -i '/KERNEL/d' $pkgs_target
        # Remove empty lines
        sed -i '/^\s*$/d' $pkgs_target

        # Remove packages that have been dropped from repos
        pacman -Ssq > /tmp/.available_packages
        pacman -Sgq >> /tmp/.available_packages
        grep -f /tmp/.available_packages $pkgs_target > /tmp/.tmp
        mv /tmp/.tmp $pkgs_target
}

install_base() {
    if [[ -e /mnt/.base_installed ]]; then
        DIALOG " $_InstBseTitle " --yesno "\n$_WarnInstBase\n " 0 0 && rm /mnt/.base_installed || return 0
    fi
    # Prep variables
    setup_profiles
    pkgs_src=$PROFILES/shared/Packages-Root
    pkgs_target=/mnt/.base
    BTRF_CHECK=$(echo "btrfs-progs" "" off)
    F2FS_CHECK=$(echo "f2fs-tools" "" off)
    mhwd-kernel -l | awk '/linux/ {print $2}' > /tmp/.available_kernels
    kernels=$(cat /tmp/.available_kernels)

    # Create the base list of packages
    echo "" > /mnt/.base

    declare -i loopmenu=1
    while ((loopmenu)); do
        # Choose kernel and possibly base-devel
        DIALOG " $_InstBseTitle " --checklist "\n$_InstStandBseBody$_UseSpaceBar\n " 0 0 13 \
          "yaourt + base-devel" "-" off \
          $(cat /tmp/.available_kernels | awk '$0=$0" - off"') 2>${PACKAGES} || { loopmenu=0; return 0; }
        if [[ ! $(grep "linux" ${PACKAGES}) ]]; then
            # Check if a kernel is already installed
            ls ${MOUNTPOINT}/boot/*.img >/dev/null 2>&1
            if [[ $? == 0 ]]; then
                DIALOG " Check Kernel " --msgbox "\nlinux-$(ls ${MOUNTPOINT}/boot/*.img | cut -d'-' -f2 | grep -v ucode.img | sort -u) detected \n " 0 0
                check_for_error "linux-$(ls ${MOUNTPOINT}/boot/*.img | cut -d'-' -f2) already installed"
                loopmenu=0
            else
                DIALOG " $_ErrTitle " --msgbox "\n$_ErrNoKernel\n " 0 0
            fi
        else
            cat ${PACKAGES} | sed 's/+ \|\"//g' | tr ' ' '\n' | tr '+' '\n' >> /mnt/.base
            echo " " >> /mnt/.base
            grep -f /tmp/.available_kernels /mnt/.base > /tmp/.chosen_kernels
            check_for_error "selected: $(cat ${PACKAGES})"
            loopmenu=0
        fi
    done

    # Choose wanted kernel modules
    DIALOG " $_ChsAddPkgs " --checklist "\n$_UseSpaceBar\n " 0 0 12 \
      "KERNEL-headers" "-" off \
      "KERNEL-acpi_call" "-" off \
      "KERNEL-ndiswrapper" "-" off \
      "KERNEL-broadcom-wl" "-" off \
      "KERNEL-r8168" "-" off \
      "KERNEL-rt3562sta" "-" off \
      "KERNEL-tp_smapi" "-" off \
      "KERNEL-vhba-module" "-" off \
      "KERNEL-virtualbox-guest-modules" "-" off \
      "KERNEL-virtualbox-host-modules" "-" off \
      "KERNEL-spl" "-" off \
      "KERNEL-zfs" "-" off 2>/tmp/.modules || return 0

    if [[ $(cat /tmp/.modules) != "" ]]; then
        check_for_error "modules: $(cat /tmp/.modules)"
        for kernel in $(cat ${PACKAGES} | grep -vE '(yaourt|base-devel)'); do
            cat /tmp/.modules | sed "s/KERNEL/\n$kernel/g" >> /mnt/.base
        done
        echo " " >> /mnt/.base
    fi
    filter_packages
    # remove grub
    sed -i '/grub/d' /mnt/.base
    echo "nilfs-utils" >> /mnt/.base
    check_for_error "packages to install: $(cat /mnt/.base | sort | tr '\n' ' ')"
    clear
    set -o pipefail
    basestrap ${MOUNTPOINT} $(cat /mnt/.base) 2>$ERR |& tee /tmp/basestrap.log
    local err=$?
    set +o pipefail
    check_for_error "install basepkgs" $err || {
        DIALOG " $_InstBseTitle " --msgbox "\n$_InstFail\n " 0 0; HIGHLIGHT_SUB=2;
        if [[ $err == 255 ]]; then
            cat /tmp/basestrap.log
            read -n1 -s # or ? exit $err
        fi
        return 1;
    }

    # copy keymap and consolefont settings to target
    echo -e "KEYMAP=$(ini linux.keymap)\nFONT=$(ini linux.font)" > ${MOUNTPOINT}/etc/vconsole.conf
    check_for_error "configure vconsole"
    
    # If root is on btrfs volume, amend mkinitcpio.conf
    if [[ -e /tmp/.btrfsroot ]]; then
        BTRFS_ROOT=1
        sed -e '/^HOOKS=/s/\ fsck//g' -e '/^MODULES=/s/"$/ btrfs"/g' -i ${MOUNTPOINT}/etc/mkinitcpio.conf
        check_for_error "root on btrfs volume. Amend mkinitcpio."
    fi

    # If root is on nilfs2 volume, amend mkinitcpio.conf
    [[ $(lsblk -lno FSTYPE,MOUNTPOINT | awk '/ \/mnt$/ {print $1}') == nilfs2 ]] && sed -e '/^HOOKS=/s/\ fsck//g' -i ${MOUNTPOINT}/etc/mkinitcpio.conf && \
      check_for_error "root on nilfs2 volume. Amend mkinitcpio."
    
    recheck_luks

    # add luks and lvm hooks as needed
    ([[ $LVM -eq 1 ]] && [[ $LUKS -eq 0 ]]) && { sed -i 's/block filesystems/block lvm2 filesystems/g' ${MOUNTPOINT}/etc/mkinitcpio.conf 2>$ERR; check_for_error "add lvm2 hook" $?; }
    ([[ $LVM -eq 0 ]] && [[ $LUKS -eq 1 ]]) && { sed -i 's/block filesystems keyboard/block consolefont keymap keyboard encrypt filesystems/g' ${MOUNTPOINT}/etc/mkinitcpio.conf 2>$ERR; check_for_error "add luks hook" $?; }
    [[ $((LVM + LUKS)) -eq 2 ]] && { sed -i 's/block filesystems keyboard/block consolefont keymap keyboard encrypt lvm2 filesystems/g' ${MOUNTPOINT}/etc/mkinitcpio.conf 2>$ERR; check_for_error "add lvm/luks hooks" $?; }

    [[ $((LVM + LUKS + BTRFS_ROOT)) -gt 0 ]] && { arch_chroot "mkinitcpio -P" 2>$ERR; check_for_error "re-run mkinitcpio" $?; }

    # If specified, copy over the pacman.conf file to the installation
    if [[ $COPY_PACCONF -eq 1 ]]; then
        cp -f /etc/pacman.conf ${MOUNTPOINT}/etc/pacman.conf
        check_for_error "copy pacman.conf"
    fi

    # if branch was chosen, use that also in installed system. If not, use the system setting
    [[ -z $(ini branch) ]] && ini branch $(ini system.branch)
    sed -i "s/Branch =.*/Branch = $(ini branch)/;s/# //" ${MOUNTPOINT}/etc/pacman-mirrors.conf

    touch /mnt/.base_installed
    check_for_error "base installed succesfully."
    install_network_drivers
}

install_bootloader() {
    check_base
    if [[ $? -eq 0 ]]; then
        if [[ $SYSTEM == "BIOS" ]]; then
            bios_bootloader
        else
            uefi_bootloader
        fi
    else
        HIGHLIGHT_SUB=2
    fi
}

uefi_bootloader() {
    #Ensure again that efivarfs is mounted
    [[ -z $(mount | grep /sys/firmware/efi/efivars) ]] && mount -t efivarfs efivarfs /sys/firmware/efi/efivars

    DIALOG " $_InstUefiBtTitle " --menu "\n$_bootloaderInfo\n " 0 0 3 \
      "1" "grub" \
      "2" "refind" \
      "3" "systemd-boot" 2>/tmp/.bootloader
 
        case $(cat /tmp/.bootloader) in
        "1") install_grub_uefi
            ;;
        "2") install_refind
            ;;
        "3") install_systemd_boot
            ;;
        esac
}

install_grub_uefi() {

    DIALOG " $_InstUefiBtTitle " --yesno "\n$_InstUefiBtBody\n " 0 0 || return 0
    if $(efibootmgr | cut -d\  -f2 | grep -q -o manjaro); then
        DIALOG " Bootloader id " --inputbox "\nInput the name identify your grub installation. Choosing an existing name overwrites it." 0 0 "manjaro" 2>/tmp/.bootid || return 0
        bootid=$(cat /tmp/.bootid)
    else
        bootid="manjaro"
    fi
    
    clear
    if $(mount | awk '$3 == "/mnt" {print $0}' | grep btrfs | grep -qv subvolid=5) ; then 
        basestrap ${MOUNTPOINT} grub-btrfs efibootmgr dosfstools 2>$ERR
        check_for_error "$FUNCNAME grub" $? || return 1
    else
        basestrap ${MOUNTPOINT} grub efibootmgr dosfstools 2>$ERR
        check_for_error "$FUNCNAME grub" $? || return 1
    fi

    #DIALOG " $_InstGrub " --infobox "\n$_PlsWaitBody\n " 0 0
    
    # if root is encrypted, amend /etc/default/grub
    root_name=$(mount | awk '/\/mnt / {print $1}' | sed s~/dev/mapper/~~g | sed s~/dev/~~g)
    root_device=$(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/$root_name/,/disk/p" | awk '/disk/ {print $1}')
    root_part=$(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/$root_name/,/part/p" | awk '/part/ {print $1}' | tr -cd '[:alnum:]')
    boot_encrypted_setting
    # If encryption used amend grub
    [[ $(cat /tmp/.luks_dev) != "" ]] && sed -i "s~GRUB_CMDLINE_LINUX=.*~GRUB_CMDLINE_LINUX=\"$(cat /tmp/.luks_dev)\"~g" ${MOUNTPOINT}/etc/default/grub
    #install grub
    if [[ "$(cat /sys/block/${root_device}/removable)" == 1 ]]; then
        arch_chroot "grub-install --target=x86_64-efi --efi-directory=${UEFI_MOUNT} --bootloader-id=${bootid} --recheck --removable" 2>$ERR
        check_for_error "grub-install --target=x86_64-efi" $?
    else
        arch_chroot "grub-install --target=x86_64-efi --efi-directory=${UEFI_MOUNT} --bootloader-id=${bootid} --recheck" 2>$ERR
        check_for_error "grub-install --target=x86_64-efi" $?
    fi

    # If root is on btrfs volume, amend grub
    [[ -e /tmp/.btrfsroot ]] && \
      sed -e '/GRUB_SAVEDEFAULT/ s/^#*/#/' -i ${MOUNTPOINT}/etc/default/grub
    # Enble manjaro grub theme
    basestrap ${MOUNTPOINT} grub-theme-manjaro 2>$ERR
    check_for_error "$FUNCNAME grub" $?
    
    # grub_mkconfig

    # Ask if user wishes to set Grub as the default bootloader and act accordingly
    DIALOG " $_InstUefiBtTitle " --yesno "\n$_SetBootDefBody ${UEFI_MOUNT}/EFI/boot $_SetBootDefBody2\n " 0 0
    if [[ $? -eq 0 ]]; then
        arch_chroot "mkdir ${UEFI_MOUNT}/EFI/boot" 2>$ERR
        arch_chroot "cp -r ${UEFI_MOUNT}/EFI/manjaro/grubx64.efi ${UEFI_MOUNT}/EFI/boot/bootx64.efi" 2>$ERR
        check_for_error "Install GRUB" $?
        DIALOG " $_InstUefiBtTitle " --infobox "\nGrub $_SetDefDoneBody\n " 0 0
        sleep 2
    fi

}
install_refind()

{
    DIALOG " $_InstUefiBtTitle " --yesno "\n$_InstRefindBody\n " 0 0 || return 0
    clear
    inst_needed refind-efi
    inst_needed refind-drivers
    # Check if the volume is removable. If so, install all drivers
    root_name=$(mount | awk '/\/mnt / {print $1}' | sed s~/dev/mapper/~~g | sed s~/dev/~~g)
    root_device=$(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/$root_name/,/disk/p" | awk '/disk/ {print $1}')   
    ## install refind 
    if [[ "$(cat /sys/block/${root_device}/removable)" == 1 ]]; then
        refind-install --root /mnt --alldrivers --yes 2>$ERR
        check_for_error "refind-install --root /mnt --alldrivers --yes" $?
        # Remove autodetect hook
        sed -i -e '/^HOOKS=/s/\ autodetect//g' /mnt/etc/mkinitcpio.conf 
    elif [[ $LUKS == 1 ]]; then
        refind-install --root /mnt --alldrivers --yes 2>$ERR
        check_for_error "refind-install --root /mnt --alldrivers --yes" $?
    else 
        refind-install --root /mnt 2>$ERR
        check_for_error "refind-install --root /mnt" $?
    fi

    # If root is on exotic filesystem, add drivers
    rootfs=$(mount | awk '/\/mnt / {print $5}')
    case $rootfs in
        nilfs2|xfs|jfs) cp /usr/share/refind/drivers_x64/"$rootfs"_x64.fi ${MOUNTPOINT}${UEFI_MOUNT}/EFI/refind/drivers_x64/
            ;;
    esac
    # Mount as rw
    sed -i 's/ro\ /rw\ \ /g' /mnt/boot/refind_linux.conf

    # Configure for intel microcode
    #if [[ -e /boot/intel-ucode.img ]]; then 
    #    sed -i "s|\"$|\ initrd=/boot/intel-ucode.img\"|g" /mnt/boot/refind_linux.conf
    #fi
    # Boot in graphics mode 
    sed -i -e '/use_graphics_for/ s/^#*//' ${MOUNTPOINT}${UEFI_MOUNT}/EFI/refind/refind.conf
    # Set appropriate rootflags if installed on btrs subvolume
    if $(mount | awk '$3 == "/mnt" {print $0}' | grep btrfs | grep -qv subvolid=5) ; then 
        rootflag="rootflags=$(mount | awk '$3 == "/mnt" {print $6}' | sed 's/^.*subvol=/subvol=/' | sed -e 's/,.*$/,/p' | sed 's/)//g')"
        sed -i "s|\"$|\ $rootflag\"|g" /mnt/boot/refind_linux.conf
    fi

    # LUKS
    if [[ $LUKS == 1 ]]; then
        mapper_name="$(mount | awk '/\/mnt / {print $1}')"
        ROOTY_PARTY="/dev/$(lsblk -i | sed -r 's/^[^[:alnum:]]+//' | grep -B1 "$root_name" | awk '/part/ {print $1}' | cut -c 3-)"
        bl_root="PARTUUID=$(blkid -s PARTUUID ${ROOTY_PARTY} | sed 's/.*=//g' | sed 's/"//g')"
        sed -i "s|root=.* |cryptdevice=$bl_root:$root_name root=$mapper_name |g" /mnt/boot/refind_linux.conf
        sed -i '/Boot with minimal options/d' /mnt/boot/refind_linux.conf
    fi
        
    # Set the root parameter if encrypted or on LVM
    #ROOTY_PARTY="/dev/$(lsblk -lno NAME,MOUNTPOINT | grep "/mnt$" | awk '{print $1}')"
    #if [[ $(echo $ROOTY_PARTY | grep "/dev/mapper/") != "" ]]; then
    #    bl_root="PARTUUID=$(blkid -s PARTUUID ${ROOTY_PARTY} | sed 's/.*=//g' | sed 's/"//g')"
    #    sed -i "s/root=.* /root=$bl_root /g" /mnt/boot/refind_linux.conf
    #    sed -i '/Boot with minimal options/d' /mnt/boot/refind_linux.conf
    #fi
    basestrap ${MOUNTPOINT} refind-theme-maia 
    DIALOG " $_InstUefiBtTitle " --infobox "\n$_RefindReady\n " 0 0
    sleep 2
}

install_systemd_boot() {
    DIALOG " $_InstUefiBtTitle " --yesno "\n$_InstSystdBBody\n " 0 0 || return 0
    clear

    # Check if already installed. If so, just add entries
    if $(arch_chroot "bootctl status" 2>&1 >/dev/null | grep -q "systemd-boot not installed"); then
        arch_chroot "bootctl --path=${UEFI_MOUNT} install" 2>$ERR
        check_for_error "systemd-boot" $?
        [[ $? -eq 0 ]] && touch /tmp/.newsystemdboot
    fi
    # Deal with LVM Root

    if [[ $(echo $ROOT_PART | grep "/dev/mapper/") != "" ]]; then
        bl_root=$ROOT_PART
    else
        bl_root="PARTUUID=$(blkid -s PARTUUID ${ROOT_PART} | sed 's/.*=//g' | sed 's/\"//g')"
    fi

    # Create default config files. First the loader
    #echo /mnt/boot/initramfs-* | sed 's/\/mnt\/boot\/initramfs-//g' | sed 's/\.img//g' | xargs -n1 | grep -v "fallback" > /tmp/.kernels
    arch_chroot "pacman -Ql $(cat /tmp/.chosen_kernels)" | awk '/vmlinuz/ {print $2}' | sed 's~/boot/vmlinuz-~~g' > /tmp/.kernels

    echo -e "default  manjaro-$(cat /tmp/.kernels | sort | tail -n1)\ntimeout  10" > ${MOUNTPOINT}${UEFI_MOUNT}/loader/loader.conf 2>$ERR
    # Second, the kernel conf files
    for kernel in $(cat /tmp/.kernels); do
        if [[ -e /mnt/boot/intel-ucode.img ]]; then 
            echo -e "title\tManjaro Linux $kernel\nlinux\t/vmlinuz-$kernel\ninitrd\t/intel-ucode.img\ninitrd\t/initramfs-$kernel.img\noptions\troot=${bl_root} rw" > "${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/manjaro-$kernel.conf" && echo "${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/manjaro-$kernel.conf" >> /tmp/.sysdconfd
            echo -e "title\tManjaro Linux $kernel\nlinux\t/vmlinuz-$kernel\ninitrd\t/intel-ucode.img\ninitrd\t/initramfs-$kernel-fallback.img\noptions\troot=${bl_root} rw" > "${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/manjaro-$kernel-fallback.conf" && echo "${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/manjaro-$kernel-fallback.conf" >> /tmp/.sysdconfd
        else
            echo -e "title\tManjaro Linux $kernel\nlinux\t/vmlinuz-$kernel\ninitrd\t/initramfs-$kernel.img\noptions\troot=${bl_root} rw" > "${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/manjaro-$kernel.conf" && echo "${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/manjaro-$kernel.conf" >> /tmp/.sysdconfd
            echo -e "title\tManjaro Linux $kernel\nlinux\t/vmlinuz-$kernel\ninitrd\t/initramfs-$kernel-fallback.img\noptions\troot=${bl_root} rw" > "${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/manjaro-$kernel-fallback.conf" && echo "${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/manjaro-$kernel-fallback.conf" >> /tmp/.sysdconfd
        fi
    done

    # Finally, amend kernel conf files for LUKS and BTRFS
    sysdconf=$(cat /tmp/.sysdconfd)
    for i in ${sysdconf}; do
        [[ $LUKS_DEV != "" ]] && sed -i "s~rw~$LUKS_DEV rw~g" ${i}
        # Deal with btrfs subvolumes
        if $(mount | awk '$3 == "/mnt" {print $0}' | grep btrfs | grep -qv subvolid=5) ; then 
            rootflag="rootflags=$(mount | awk '$3 == "/mnt" {print $6}' | sed 's/^.*subvol=/subvol=/' | sed -e 's/,.*$/,/p' | sed 's/)//g')"
            sed -i "s|rw|rw $rootflag|g" ${i}
        fi
    done

    # Check if the volume is removable. If so, dont use autodetect
    root_name=$(mount | awk '/\/mnt / {print $1}' | sed s~/dev/mapper/~~g | sed s~/dev/~~g)
    root_device=$(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/$root_name/,/disk/p" | awk '/disk/ {print $1}')
    if [[ "$(cat /sys/block/${root_device}/removable)" == 1 ]]; then
        # Remove autodetect hook
        sed -i -e '/^HOOKS=/s/\ autodetect//g' /mnt/etc/mkinitcpio.conf
    fi
    DIALOG " $_InstUefiBtTitle " --infobox "\n$_SystdBReady\n " 0 0
    sleep 2
}


# Grub auto-detects installed kernels, etc. Syslinux does not, hence the extra code for it.
bios_bootloader() {
    DIALOG " $_InstBiosBtTitle " --menu "\n$_InstGrubBody\n " 0 0 2 \
      "grub" "" \
      "grub + os-prober" "" 2>${PACKAGES} || return 0
    clear

    # If something has been selected, act
    if [[ $(cat ${PACKAGES}) != "" ]]; then
        sed -i 's/+ \|\"//g' ${PACKAGES}
        basestrap ${MOUNTPOINT} $(cat ${PACKAGES}) 2>$ERR
        check_for_error "$FUNCNAME" $? || return 1

        # If Grub, select device
        if [[ $(cat ${PACKAGES} | grep "grub") != "" ]]; then
            select_device
            # if root is encrypted, amend /etc/default/grub
            boot_encrypted_setting
            # If a device has been selected, configure
            if [[ $DEVICE != "" ]]; then
                # if /boot is LVM (whether using a seperate /boot mount or not), amend grub
                if ( [[ $LVM -eq 1 ]] && [[ $LVM_SEP_BOOT -eq 0 ]] ) || [[ $LVM_SEP_BOOT -eq 2 ]]; then
                    sed -i "s/GRUB_PRELOAD_MODULES=\"/GRUB_PRELOAD_MODULES=\"lvm /g" ${MOUNTPOINT}/etc/default/grub
                    sed -e '/GRUB_SAVEDEFAULT/ s/^#*/#/' -i ${MOUNTPOINT}/etc/default/grub
                fi

                # If encryption used amend grub
                [[ $(cat /tmp/.luks_dev) != "" ]] && sed -i "s~GRUB_CMDLINE_LINUX=.*~GRUB_CMDLINE_LINUX=\"$(cat /tmp/.luks_dev)\"~g" ${MOUNTPOINT}/etc/default/grub

                # If root is on btrfs volume, amend grub
                [[ $(lsblk -lno FSTYPE,MOUNTPOINT | awk '/ \/mnt$/ {print $1}') == btrfs ]] && \
                  sed -e '/GRUB_SAVEDEFAULT/ s/^#*/#/' -i ${MOUNTPOINT}/etc/default/grub
                
                DIALOG " $_InstGrub " --infobox "\n$_PlsWaitBody\n " 0 0
                dd if=/dev/zero of=$DEVICE seek=1 count=2047
                arch_chroot "grub-install --target=i386-pc --recheck $DEVICE" 2>$ERR
                check_for_error "grub-install --target=i386-pc" $?

                #grub_mkconfig
                basestrap ${MOUNTPOINT} grub-theme-manjaro 2>$ERR
                check_for_error "$FUNCNAME grub" $?
            fi
        else
            # Syslinux
            DIALOG " $_InstSysTitle " --menu "\n$_InstSysBody\n " 0 0 2 \
              "syslinux-install_update -iam" "[MBR]" "syslinux-install_update -i" "[/]" 2>${PACKAGES}

            # If an installation method has been chosen, run it
            if [[ $(cat ${PACKAGES}) != "" ]]; then
                arch_chroot "$(cat ${PACKAGES})" 2>$ERR
                check_for_error "syslinux-install" $?

                # Amend configuration file. First remove all existing entries, then input new ones.
                sed -i '/^LABEL.*$/,$d' ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                #echo -e "\n" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg

                # First the "main" entries
                [[ -e ${MOUNTPOINT}/boot/initramfs-linux.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux\n\tLINUX \
                  ../vmlinuz-linux\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                [[ -e ${MOUNTPOINT}/boot/initramfs-linux-lts.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux realtime LTS\n\tLINUX \
                  ../vmlinuz-linux-lts\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-lts.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                [[ -e ${MOUNTPOINT}/boot/initramfs-linux-grsec.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux realtime\n\tLINUX \
                  ../vmlinuz-linux-grsec\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-grsec.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                [[ -e ${MOUNTPOINT}/boot/initramfs-linux-zen.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux release candidate\n\tLINUX \
                  ../vmlinuz-linux-zen\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-zen.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg

                # Second the "fallback" entries
                [[ -e ${MOUNTPOINT}/boot/initramfs-linux.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux Fallback\n\tLINUX \
                  ../vmlinuz-linux\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-fallback.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                [[ -e ${MOUNTPOINT}/boot/initramfs-linux-lts.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux Fallback realtime LTS\n\tLINUX \
                  ../vmlinuz-linux-lts\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-lts-fallback.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                [[ -e ${MOUNTPOINT}/boot/initramfs-linux-grsec.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux Fallback realtime\n\tLINUX \
                  ../vmlinuz-linux-grsec\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-grsec-fallback.img" \
                  >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                [[ -e ${MOUNTPOINT}/boot/initramfs-linux-zen.img ]] && echo -e "\n\nLABEL arch\n\tMENU LABEL Manjaro Linux Fallbacl Zen\n\tLINUX \
                  ../vmlinuz-linux-zen\n\tAPPEND root=${ROOT_PART} rw\n\tINITRD ../initramfs-linux-zen-fallback.img" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg

                # Third, amend for LUKS
                [[ $LUKS_DEV != "" ]] && sed -i "s~rw~$LUKS_DEV rw~g" ${MOUNTPOINT}/boot/syslinux/syslinux.cfg

                # Finally, re-add the "default" entries
                echo -e "\n\nLABEL hdt\n\tMENU LABEL HDT (Hardware Detection Tool)\n\tCOM32 hdt.c32" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                echo -e "\n\nLABEL reboot\n\tMENU LABEL Reboot\n\tCOM32 reboot.c32" >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                echo -e "\n\n#LABEL windows\n\t#MENU LABEL Windows\n\t#COM32 chain.c32\n\t#APPEND root=/dev/sda2 rw" \
                  >> ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
                echo -e "\n\nLABEL poweroff\n\tMENU LABEL Poweroff\n\tCOM32 poweroff.c32" ${MOUNTPOINT}/boot/syslinux/syslinux.cfg
            fi
        fi
    fi
}

setup_luks_keyfile() {
    # Create a keyfile
    [[ -e /mnt/crypto_keyfile.bin ]] || dd bs=512 count=4 if=/dev/urandom of=/mnt/crypto_keyfile.bin && echo "Generating a keyfile"
    chmod 000 /mnt/crypto_keyfile.bin
    # Add keyfile to luks
    echo "Adding the keyfile to the LUKS configuration"
    root_name=$(mount | awk '/\/mnt / {print $1}' | sed s~/dev/mapper/~~g | sed s~/dev/~~g)
    root_part=$(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/$root_name/,/part/p" | awk '/part/ {print $1}' | tr -cd '[:alnum:]')
    cryptsetup luksAddKey /dev/"$root_part" /mnt/crypto_keyfile.bin || echo "Something vent wrong with adding the LUKS key. Is /dev/$root_part the right partition?"
    # Add keyfile to initcpio
    grep -q '/crypto_keyfile.bin' /mnt/etc/mkinitcpio.conf || sed -i '/FILES/ s~)~/crypto_keyfile.bin)~' /mnt/etc/mkinitcpio.conf && echo "Adding keyfile to the initcpio"
    arch_chroot "mkinitcpio -P"    
}

boot_encrypted_setting() {
    # Check if there is separate /boot partition 
    if [[ $(lsblk | grep "/mnt/boot$") == "" ]]; then
        #There is no separate /boot parition
        root_name=$(mount | awk '/\/mnt / {print $1}' | sed s~/dev/mapper/~~g | sed s~/dev/~~g)
        # Check if root is encrypted
        if  [[ "$LUKS" == 1 ]]; then
            grep -q "GRUB_ENABLE_CRYPTODISK=y" /mnt/etc/default/grub || echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub
            setup_luks_keyfile
        elif $(lsblk "/dev/mapper/$root_name" | grep -q 'crypt' ); then
            grep -q "GRUB_ENABLE_CRYPTODISK=y" /mnt/etc/default/grub || echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub
            setup_luks_keyfile
        elif $(lsblk | grep "/mnt$" | grep -q 'crypt' ); then
            grep -q "GRUB_ENABLE_CRYPTODISK=y" /mnt/etc/default/grub || echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub
            setup_luks_keyfile
        # Check if root is on encrypted lvm volume
        elif $(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/$root_name/,/disk/p" | awk '{print $6}' | grep -q crypt); then
            grep -q "GRUB_ENABLE_CRYPTODISK=y" /mnt/etc/default/grub || echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub
            setup_luks_keyfile
        fi
    else
        # There is a separate /boot. Check if it is encrypted
        boot_name=$(mount | awk '/\/mnt\/boot / {print $1}' | sed s~/dev/mapper/~~g | sed s~/dev/~~g)
        if $(lsblk | grep '/mnt/boot' | grep -q 'crypt' ); then
            grep -q "GRUB_ENABLE_CRYPTODISK=y" /mnt/etc/default/grub || echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub
            setup_luks_keyfile
        # Check if the /boot is inside encrypted lvm volume
        elif $(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/$boot_name/,/disk/p" | awk '{print $6}' | grep -q crypt); then
            grep -q "GRUB_ENABLE_CRYPTODISK=y" /mnt/etc/default/grub || echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub
            setup_luks_keyfile
        elif $(lsblk "/dev/mapper/$boot_name" | grep -q 'crypt' ); then
            grep -q "GRUB_ENABLE_CRYPTODISK=y" /mnt/etc/default/grub || echo "GRUB_ENABLE_CRYPTODISK=y" >> /mnt/etc/default/grub
            setup_luks_keyfile
        fi
    fi

}

recheck_luks() {
    # Check if there is separate encrypted /boot partition 
    if $(lsblk | grep '/mnt/boot' | grep -q 'crypt' ); then
        LUKS=1
    # Check if root is encrypted and there is no separate /boot
    elif $(lsblk | grep "/mnt$" | grep -q 'crypt' ) && [[ $(lsblk | grep "/mnt/boot$") == "" ]]; then
        LUKS=1
    # Check if root is on encrypted lvm volume
    elif $(lsblk -i | tac | sed -r 's/^[^[:alnum:]]+//' | sed -n -e "/$root_name/,/disk/p" | awk '{print $6}' | grep -q crypt); then
        LUKS=1
    else
        true
    fi
}

# Function will not allow incorrect UUID type for installed system.
generate_fstab() {
    DIALOG " $_ConfBseFstab " --menu "\n$_FstabBody\n " 0 0 4 \
      "fstabgen -p" "$_FstabDevName" \
      "fstabgen -L -p" "$_FstabDevLabel" \
      "fstabgen -U -p" "$_FstabDevUUID" \
      "fstabgen -t PARTUUID -p" "$_FstabDevPtUUID" 2>${ANSWER}

    if [[ $(cat ${ANSWER}) != "" ]]; then
        if [[ $SYSTEM == "BIOS" ]] && [[ $(cat ${ANSWER}) == "fstabgen -t PARTUUID -p" ]]; then
            DIALOG " $_ErrTitle " --msgbox "\n$_FstabErr\n " 0 0
        else
            $(cat ${ANSWER}) ${MOUNTPOINT} > ${MOUNTPOINT}/etc/fstab 2>$ERR
            check_for_error "$FUNCNAME" $?
            [[ -f ${MOUNTPOINT}/swapfile ]] && sed -i "s/\\${MOUNTPOINT}//" ${MOUNTPOINT}/etc/fstab
        fi
    fi
    # Edit fstab in case of btrfs subvolumes
    sed -i "s/subvolid=.*,subvol=\/.*,//g" /mnt/etc/fstab
}

# locale array generation code adapted from the Manjaro 0.8 installer
set_locale() {
    LOCALES=""
    for i in $(cat /etc/locale.gen | grep -v "#  " | sed 's/#//g' | awk '/UTF-8/ {print $1}'); do
        LOCALES="${LOCALES} ${i} -"
    done

    DIALOG " $_ConfBseSysLoc " --menu "\n$_localeBody\n " 0 0 12 ${LOCALES} 2>${ANSWER} || return 0

    LOCALE=$(cat ${ANSWER})

    echo "LANG=\"${LOCALE}\"" > ${MOUNTPOINT}/etc/locale.conf
    sed -i "s/#${LOCALE}/${LOCALE}/" ${MOUNTPOINT}/etc/locale.gen 2>$ERR
    arch_chroot "locale-gen" >/dev/null 2>$ERR
    check_for_error "$FUNCNAME" "$?"
    ini linux.locale "$LOCALE"

}

# Set Zone and Sub-Zone
set_timezone() {
    ZONE=""
    for i in $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "/" | sed "s/\/.*//g" | sort -ud); do
        ZONE="$ZONE ${i} -"
    done

    DIALOG " $_ConfBseTimeHC " --menu "\n$_TimeZBody\n " 0 0 10 ${ZONE} 2>${ANSWER} || return 1
    ZONE=$(cat ${ANSWER})

    SUBZONE=""
    for i in $(cat /usr/share/zoneinfo/zone.tab | awk '{print $3}' | grep "${ZONE}/" | sed "s/${ZONE}\///g" | sort -ud); do
        SUBZONE="$SUBZONE ${i} -"
    done

    DIALOG " $_ConfBseTimeHC " --menu "\n$_TimeSubZBody\n " 0 0 11 ${SUBZONE} 2>${ANSWER} || return 1
    SUBZONE=$(cat ${ANSWER})

    DIALOG " $_ConfBseTimeHC " --yesno "\n$_TimeZQ ${ZONE}/${SUBZONE}?\n " 0 0
    if (( $? == 0 )); then
        arch_chroot "ln -sf /usr/share/zoneinfo/${ZONE}/${SUBZONE} /etc/localtime" 2>$ERR
        check_for_error "$FUNCNAME ${ZONE}/${SUBZONE}" $?
        ini linux.zone "${ZONE}/${SUBZONE}"
    else
        return 1
    fi
}

set_hw_clock() {
    DIALOG " $_ConfBseTimeHC " --menu "\n$_HwCBody\n " 0 0 2 \
    "utc" "-" \
    "localtime" "-" 2>${ANSWER}

    if [[ $(cat ${ANSWER}) != "" ]]; then
        arch_chroot "hwclock --systohc --$(cat ${ANSWER})"  2>$ERR
        check_for_error "$FUNCNAME" "$?"
        ini linux.time "$ANSWER"
    fi
}

set_hostname() {
    DIALOG " $_ConfBseHost " --inputbox "\n$_HostNameBody\n " 0 0 "manjaro" 2>${ANSWER} || return 0

    echo "$(cat ${ANSWER})" > ${MOUNTPOINT}/etc/hostname 2>$ERR
    echo -e "#<ip-address>\t<hostname.domain.org>\t<hostname>\n127.0.0.1\tlocalhost.localdomain\tlocalhost\t$(cat \
      ${ANSWER})\n::1\tlocalhost.localdomain\tlocalhost\t$(cat ${ANSWER})" > ${MOUNTPOINT}/etc/hosts 2>$ERR
    check_for_error "$FUNCNAME"
    ini linux.hostname "$ANSWER"
}

# Adapted and simplified from the Manjaro 0.8 and Antergos 2.0 installers
set_root_password() {
    DIALOG " $_ConfUsrRoot " --clear --insecure --passwordbox "\n$_PassRtBody\n " 0 0 \
      2> ${ANSWER} || return 0
    PASSWD=$(cat ${ANSWER})

    DIALOG " $_ConfUsrRoot " --clear --insecure --passwordbox "\n$_PassReEntBody\n " 0 0 \
      2> ${ANSWER} || return 0
    PASSWD2=$(cat ${ANSWER})

    if [[ $PASSWD == $PASSWD2 ]]; then
        echo -e "${PASSWD}\n${PASSWD}" > /tmp/.passwd
        arch_chroot "passwd root" < /tmp/.passwd >/dev/null 2>$ERR
        check_for_error "$FUNCNAME" $?
        rm /tmp/.passwd
    else
        DIALOG " $_ErrTitle " --msgbox "\n$_PassErrBody\n " 0 0
        set_root_password
    fi
}

# Originally adapted from the Antergos 2.0 installer
create_new_user() {
    DIALOG " $_NUsrTitle " --inputbox "\n$_NUsrBody\n " 0 0 "" 2>${ANSWER} || return 0
    USER=$(cat ${ANSWER})

    # Loop while user name is blank, has spaces, or has capital letters in it.
    while [[ ${#USER} -eq 0 ]] || [[ $USER =~ \ |\' ]] || [[ $USER =~ [^a-z0-9\ ] ]]; do
        DIALOG " $_NUsrTitle " --inputbox "$_NUsrErrBody" 0 0 "" 2>${ANSWER} || return 0
        USER=$(cat ${ANSWER})
    done

    shell=""
    DIALOG " $_NUsrTitle " --radiolist "\n$_DefShell\n$_UseSpaceBar\n " 0 0 3 \
      "zsh" "-" on \
      "bash" "-" off \
      "fish" "-" off 2>/tmp/.shell
    shell_choice=$(cat /tmp/.shell)

    case ${shell_choice} in
        "zsh") [[ ! -e /mnt/etc/skel/.zshrc ]] && basestrap ${MOUNTPOINT} manjaro-zsh-config
            shell=/usr/bin/zsh
            ;;
        "fish") [[ ! -e /mnt/usr/bin/fish ]] && basestrap ${MOUNTPOINT} fish
            shell=/usr/bin/fish
            ;;
        "bash") shell=/bin/bash
            ;;
    esac
    check_for_error "default shell: [${shell}]"

    # Enter password. This step will only be reached where the loop has been skipped or broken.
    DIALOG " $_ConfUsrNew " --clear --insecure --passwordbox "\n$_PassNUsrBody $USER\n " 0 0 \
      2> ${ANSWER} || return 0
    PASSWD=$(cat ${ANSWER})

    DIALOG " $_ConfUsrNew " --clear --insecure --passwordbox "\n$_PassReEntBody\n " 0 0 \
      2> ${ANSWER} || return 0
    PASSWD2=$(cat ${ANSWER})

    # loop while passwords entered do not match.
    while [[ $PASSWD != $PASSWD2 ]]; do
        DIALOG " $_ErrTitle " --msgbox "\n$_PassErrBody\n " 0 0

        DIALOG " $_ConfUsrNew " --clear --insecure --passwordbox "\n$_PassNUsrBody $USER\n " 0 0 \
          2> ${ANSWER} || return 0
        PASSWD=$(cat ${ANSWER})

        DIALOG " $_ConfUsrNew " --clear --insecure --passwordbox "\n_PassReEntBody\n " 0 0 \
          2> ${ANSWER} || return 0
        PASSWD2=$(cat ${ANSWER})
    done

    # create new user. This step will only be reached where the password loop has been skipped or broken.
    DIALOG " $_ConfUsrNew " --infobox "\n$_NUsrSetBody\n " 0 0
    sleep 2

    local list=$(ini linux.users)
    [[ -n "$list" ]] && list="${list};"
    ini linux.users "${list}${USER}"
    list=$(ini linux.shells)
    [[ -n "$list" ]] && list="${list};"
    ini linux.shells "${list}${shell}"

    # Create the user, set password, then remove temporary password file
    arch_chroot "groupadd ${USER}"
    arch_chroot "useradd ${USER} -m -g ${USER} -G wheel,storage,power,network,video,audio,lp -s $shell" 2>$ERR
    check_for_error "add user to groups" $?
    echo -e "${PASSWD}\n${PASSWD}" > /tmp/.passwd
    arch_chroot "passwd ${USER}" < /tmp/.passwd >/dev/null 2>$ERR
    check_for_error "create user pwd" $?
    rm /tmp/.passwd

    # Set up basic configuration files and permissions for user
    #arch_chroot "cp /etc/skel/.bashrc /home/${USER}"
    arch_chroot "chown -R ${USER}:${USER} /home/${USER}"
    [[ -e ${MOUNTPOINT}/etc/sudoers ]] && sed -i '/%wheel ALL=(ALL) ALL/s/^#//' ${MOUNTPOINT}/etc/sudoers
}
