edit_mkinitcpio(){
    nano "${MOUNTPOINT}/etc/mkinitcpio.conf"
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --yesno "\n${_RunMkinit}?\n " 0 0 && { arch_chroot "mkinitcpio -P" 2>$ERR; check_for_error "run mkinitcpio" $?; }
}

edit_grub(){
    nano "${MOUNTPOINT}/etc/default/grub"
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --yesno "\n${_RunUpGrub}?\n " 0 0 && grub_mkconfig
}

edit_configs() {

    shopt -s nullglob

    local PARENT="$FUNCNAME"
    # Clear the file variables
    local options=() functions=("-") i=0 f='' choice=0 fn=''    

    for f in ${MOUNTPOINT}/home/*/.extend.xinitrc; do
        ((i++))
        options+=( $i ".extend.xinitrc ($(echo "$f"|cut -d'/' -f4 ))"  )
        functions+=( "nano ${f}" )
    done
    for f in ${MOUNTPOINT}/home/*/.xinitrc; do
        ((i++))
        options+=( $i ".xinitrc ($(echo "$f"|cut -d'/' -f4 ))"  )
        functions+=( "nano ${f}" )
    done
    for f in ${MOUNTPOINT}/home/*/.extend.Xresources; do
        ((i++))
        options+=( $i ".extend.Xresources ($(echo "$f"|cut -d'/' -f4 ))"  )
        functions+=( "nano ${f}" )
    done
    for f in ${MOUNTPOINT}/home/*/.Xresources; do
        ((i++))
        options+=( $i ".Xresources ($(echo "$f"|cut -d'/' -f4 ))"  )
        functions+=( "nano ${f}" )
    done
    if [[ -e ${MOUNTPOINT}/etc/crypttab ]]; then
        ((i++))
        options+=( $i "crypttab" )
        functions+=( "nano ${MOUNTPOINT}/etc/crypttab" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/fstab ]]; then
        ((i++))
        options+=( $i "fstab" )
        functions+=( "nano ${MOUNTPOINT}/etc/fstab" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/default/grub ]]; then
        ((i++))
        options+=( $i "grub" )
        functions+=( "edit_grub" )
    fi
    if [[ -e ${MOUNTPOINT}/boot/refind_linux.conf ]]; then
        ((i++))
        options+=( $i "refind_linux.conf" )
        functions+=( "nano ${MOUNTPOINT}/boot/refind_linux.conf" )
    fi    
    if [[ -e ${MOUNTPOINT}${UEFI_MOUNT}/efi/refind/refind_linux.conf ]]; then
        ((i++))
        options+=( $i "refind.conf" )
        functions+=( "nano ${MOUNTPOINT}${UEFI_MOUNT}/efi/refind/refind.conf" )
    fi    
    if [[ -e ${MOUNTPOINT}${UEFI_MOUNT}/loader/loader.conf ]]; then
        ((i++))
        options+=( $i "systemd-boot" )
        functions+=( "nano ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/*" )
    fi    
    if [[ -e ${MOUNTPOINT}/etc/hostname ]]; then
        ((i++))
        options+=( $i "hostname" )
        functions+=( "nano ${MOUNTPOINT}/etc/hostname" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/hosts ]]; then
        ((i++))
        options+=( $i "hosts" )
        functions+=( "nano ${MOUNTPOINT}/etc/hosts" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/systemd/journald.conf ]]; then
        ((i++))
        options+=( $i "journald" )
        functions+=( "nano ${MOUNTPOINT}/etc/systemd/journald.conf" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/conf.d/keymaps ]]; then
        ((i++))
        options+=( $i "keymaps" )
        functions+=( "nano ${MOUNTPOINT}/etc/conf.d/keymaps" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/locale.conf ]]; then
        ((i++))
        f=$(grep -o "=.*$" ${MOUNTPOINT}/etc/locale.conf -m 1)
        options+=( $i "locales (${f:1})"  )
        functions+=( "nano ${MOUNTPOINT}/etc/locale.conf" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/lightdm/lightdm.conf ]]; then
        ((i++))
        options+=( $i "lightdm" )
        functions+=( "nano ${MOUNTPOINT}/etc/lightdm/lightdm.conf" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/lxdm/lxdm.conf ]]; then
        ((i++))
        options+=( $i "lxdm" )
        functions+=( "nano ${MOUNTPOINT}/etc/lxdm/lxdm.conf" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/mkinitcpio.conf ]]; then
        ((i++))
        options+=( $i "mkinitcpio" )
        functions+=( "edit_mkinitcpio" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/rc.conf ]]; then
        ((i++))
        options+=( $i "openrc" )
        functions+=( "nano ${MOUNTPOINT}/etc/rc.conf" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/pacman.conf ]]; then
        ((i++))
        options+=( $i "pacman" )
        functions+=( "nano ${MOUNTPOINT}/etc/pacman.conf" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/sddm.conf ]]; then
        ((i++))
        options+=( $i "sddm" )
        functions+=( "nano ${MOUNTPOINT}/etc/sddm.conf" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/sudoers.conf ]]; then
        ((i++))
        options+=( $i "sudoers" )
        functions+=( "nano ${MOUNTPOINT}/etc/sudoers.conf" )
    fi
    if [[ -e ${MOUNTPOINT}/boot/syslinux/syslinux.cfg ]]; then
        ((i++))
        options+=( $i "syslinux" )
        functions+=( "nano ${MOUNTPOINT}/boot/syslinux/syslinux.cfg" )
    fi
    if [[ -e ${MOUNTPOINT}/etc/vconsole.conf ]]; then
        ((i++))
        options+=( $i "vconsole" )
        functions+=( "nano ${MOUNTPOINT}/etc/vconsole.conf" )
    fi
    ((i++))

    shopt -u nullglob
 
    while ((1)); do
        submenu 13
        DIALOG " $_SeeConfOptTitle " --default-item ${HIGHLIGHT_SUB} --menu "\n$_SeeConfOptBody\n " 0 0 $i \
            "${options[@]}" 2>${ANSWER}
        HIGHLIGHT_SUB=$(<${ANSWER})
        choice="${HIGHLIGHT_SUB:-0}"

        case "$choice" in
            0) break ;;                      # btn cancel
            *)  
                fn="${functions[$choice]}"   # find attach working function in array
                [ -n "$fn" ] && $fn
        esac        
    done
}
