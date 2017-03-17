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

setup_graphics_card() {
    DIALOG " $_GCDetBody " --radiolist "\n$_UseSpaceBar\n " 0 0 12 \
      $(mhwd -l | awk '/video-/{print $1}' |awk '$0=$0" - off"')  2> /tmp/.driver || return 0

    if [[ $(cat /tmp/.driver) != "" ]]; then
        clear
        arch_chroot "mhwd -f -i pci $(cat /tmp/.driver)" 2>$ERR
        check_for_error "install $(cat /tmp/.driver)" $?
        touch /mnt/.video_installed

        GRAPHIC_CARD=$(lspci | grep -i "vga" | sed 's/.*://' | sed 's/(.*//' | sed 's/^[ \t]*//')

        # All non-NVIDIA cards / virtualisation
        if [[ $(echo $GRAPHIC_CARD | grep -i 'intel\|lenovo') != "" ]]; then
            install_intel
        elif [[ $(echo $GRAPHIC_CARD | grep -i 'ati') != "" ]]; then
            install_ati
        elif [[ $(cat /tmp/.driver) == "video-nouveau" ]]; then
            sed -i 's/MODULES=""/MODULES="nouveau"/' ${MOUNTPOINT}/etc/mkinitcpio.conf
        fi
    else
        DIALOG " $_ErrTitle " --msgbox "\n$_WarnInstGr\n " 0 0
        check_for_error "No video-driver selected."
    fi
}

setup_network_drivers() {
    DIALOG " $_InstGrMenuDD " --menu "\n " 0 0 3 \
          "1" "$_InstFree" \
          "2" "$_InstProp" \
          "3" "$_InstNWDrv" 2>${ANSWER} || return 0

    case $(cat ${ANSWER}) in
        "1") clear
            arch_chroot "mhwd -a pci free 0200" 2>$ERR
            check_for_error "$FUNCNAME free" $?
            ;;
        "2") clear
            arch_chroot "mhwd -a pci nonfree 0200" 2>$ERR
            check_for_error "$FUNCNAME nonfree" $?
            ;;
        "3") if [[ $(mhwd -l | awk '/network-/' | wc -l) -eq 0 ]]; then 
                DIALOG " $_InstNWDrv " --msgbox "\n$_InfoNWKernel\n " 0 0
            else
                DIALOG " $_InstGrDrv " --checklist "\n$_UseSpaceBar\n " 0 0 12 \
                  $(mhwd -l | awk '/network-/{print $1}' |awk '$0=$0" - off"')  2> /tmp/.network_driver || return 0

                if [[ $(cat /tmp/.driver) != "" ]]; then
                    clear
                    arch_chroot "mhwd -f -i pci $(cat /tmp/.network_driver)" 2>$ERR
                    check_for_error "install $(cat /tmp/.network_driver)" $? || return 1
                else
                    DIALOG " $_ErrTitle " --msgbox "\nNo network driver selected\n " 0 0
                    check_for_error "No network-driver selected."
                fi
            fi
            ;;
    esac
}

install_network_drivers() {
    if [[ $(mhwd -l | awk '/network-/' | wc -l) -gt 0 ]]; then 
        for driver in $(mhwd -l | awk '/network-/{print $1}'); do
            arch_chroot "mhwd -f -i pci ${driver}" 2>$ERR
            check_for_error "install ${driver}" $?
        done
    else
        echo "No special network drivers installed because no need detected."
    fi
}

install_intel() {
    sed -i 's/MODULES=""/MODULES="i915"/' ${MOUNTPOINT}/etc/mkinitcpio.conf

    # Intel microcode (Grub, Syslinux and systemd-boot).
    # Done as seperate if statements in case of multiple bootloaders.
    if [[ -e ${MOUNTPOINT}/boot/grub/grub.cfg ]]; then
        DIALOG " grub-mkconfig " --infobox "\n$_PlsWaitBody\n " 0 0
        sleep 1
        grub_mkconfig
    fi
    # Syslinux
    [[ -e ${MOUNTPOINT}/boot/syslinux/syslinux.cfg ]] && sed -i "s/INITRD /&..\/intel-ucode.img,/g" ${MOUNTPOINT}/boot/syslinux/syslinux.cfg

    # Systemd-boot
    if [[ -e ${MOUNTPOINT}${UEFI_MOUNT}/loader/loader.conf ]]; then
        update=$(ls ${MOUNTPOINT}${UEFI_MOUNT}/loader/entries/*.conf)
        for i in ${upgate}; do
            sed -i '/linux \//a initrd \/intel-ucode.img' ${i}
        done
    fi
}

install_ati() {
    sed -i 's/MODULES=""/MODULES="radeon"/' ${MOUNTPOINT}/etc/mkinitcpio.conf
}

# Set keymap for X11
set_xkbmap() {
    XKBMAP_LIST=""
    keymaps_xkb=("af al am at az ba bd be bg br bt bw by ca cd ch cm cn cz de dk ee es et eu fi fo fr\
      gb ge gh gn gr hr hu ie il in iq ir is it jp ke kg kh kr kz la lk lt lv ma md me mk ml mm mn mt mv\
      ng nl no np pc ph pk pl pt ro rs ru se si sk sn sy tg th tj tm tr tw tz ua us uz vn za")

    for i in ${keymaps_xkb}; do
        XKBMAP_LIST="${XKBMAP_LIST} ${i} -"
    done

    DIALOG " $_PrepKBLayout " --menu "\n$_XkbmapBody\n " 0 0 16 ${XKBMAP_LIST} 2>${ANSWER} || return 0
    XKBMAP=$(cat ${ANSWER} |sed 's/_.*//')
    echo -e "Section "\"InputClass"\"\nIdentifier "\"system-keyboard"\"\nMatchIsKeyboard "\"on"\"\nOption "\"XkbLayout"\" "\"${XKBMAP}"\"\nEndSection" \
      > ${MOUNTPOINT}/etc/X11/xorg.conf.d/00-keyboard.conf 2>$ERR
    check_for_error "$FUNCNAME ${XKBMAP}" "$?"
}

install_manjaro_de_wm_pkg() {
    PROFILES="/usr/share/manjaro-tools/iso-profiles"
    # Only show this information box once
    if [[ $SHOW_ONCE -eq 0 ]]; then
        DIALOG " $_InstDETitle " --msgbox "\n$_InstPBody\n " 0 0
        SHOW_ONCE=1
    fi
    clear
    pacman -Sy --noconfirm $p manjaro-iso-profiles-{base,official,community} 2>$ERR
    check_for_error "update profiles pkgs" $?

    install_manjaro_de_wm
}

install_manjaro_de_wm() {
    # Clear packages after installing base
    echo "" > /tmp/.desktop

    # DE/WM Menu
    DIALOG " $_InstDETitle " --radiolist "\n$_InstManDEBody\n$(evaluate_profiles)\n\n$_UseSpaceBar\n " 0 0 12 \
      $(echo $PROFILES/{manjaro,community}/* | xargs -n1 | cut -f7 -d'/' | grep -vE "netinstall|architect" | awk '$0=$0" - off"')  2> /tmp/.desktop

    # If something has been selected, install
    if [[ $(cat /tmp/.desktop) != "" ]]; then
        check_for_error "selected: [Manjaro-$(cat /tmp/.desktop)]"
        clear
        # Source the iso-profile
        profile=$(echo $PROFILES/*/$(cat /tmp/.desktop)/profile.conf)
        . $profile        
        overlay=$(echo $PROFILES/*/$(cat /tmp/.desktop)/desktop-overlay/)
        echo $displaymanager > /tmp/.display-manager

        # Parse package list based on user input and remove parts that don't belong to pacman
        package_list=$(echo $PROFILES/*/$(cat /tmp/.desktop)/Packages-Desktop)
        filter_packages
        # remove already installed base pkgs and
        # basestrap the parsed package list to the new root
        check_for_error "packages to install: $(cat /mnt/.base | sort | uniq | tr '\n' ' ')"
        clear
        basestrap ${MOUNTPOINT} $(cat /mnt/.base | sort | uniq) 2>$ERR
        check_for_error "install desktop-pkgs" "$?" || return 1

        # copy the profile overlay to the new root
        echo "Copying overlay files to the new root"
        cp -r "$overlay"* ${MOUNTPOINT} 2>$ERR
        check_for_error "copy overlay" "$?"

        # Copy settings to root account
        cp -ar $MOUNTPOINT/etc/skel/. $MOUNTPOINT/root/ 2>$ERR
        check_for_error "copy root config" "$?"

        # copy settings to already created users
        if [[ -e "$(echo /mnt/home/*)" ]]; then
            for home in $(echo $MOUNTPOINT/home/*); do
                cp -ar $MOUNTPOINT/etc/skel/. $home/
                user=$(echo $home | cut -d/ -f4)
                arch_chroot "chown -R ${user}:${user} /home/${user}"
            done
        fi
        # Enable services in the chosen profile
        enable_services
        install_graphics_menu
        # Stop for a moment so user can see if there were errors
        echo ""
        echo ""
        echo ""
        echo "press Enter to continue"
        read
        # Clear the packages file for installation of "common" packages
        echo "" > ${PACKAGES}

        # Offer to install various "common" packages.
        install_extra
    fi
}

set_lightdm_greeter() {
    local greeters=$(ls /mnt/usr/share/xgreeters/*greeter.desktop) name
    for g in ${greeters[@]}; do
        name=${g##*/}
        name=${name%%.*}
        case ${name} in
            lightdm-gtk-greeter)
                break
                ;;
            lightdm-*-greeter)
                sed -i -e "s/^.*greeter-session=.*/greeter-session=${name}/" /mnt/etc/lightdm/lightdm.conf
                ;;
        esac
    done
}

set_sddm_ck() {
    local halt='/usr/bin/shutdown -h -P now' \
      reboot='/usr/bin/shutdown -r now'
    sed -e "s|^.*HaltCommand=.*|HaltCommand=${halt}|" \
      -e "s|^.*RebootCommand=.*|RebootCommand=${reboot}|" \
      -e "s|^.*MinimumVT=.*|MinimumVT=7|" \
      -i "/mnt/etc/sddm.conf"
    arch_chroot "gpasswd -a sddm video" 2>$ERR
    check_for_error "$FUNCNAME" $?
}
