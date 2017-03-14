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

# Header
VERSION="Manjaro Architect Installer v$version"

# Host system information
ARCHI=$(uname -m) # Display whether 32 or 64 bit system
SYSTEM="Unknown"   # Display whether system is BIOS or UEFI. Default is "unknown"
H_INIT=""          # Host init-sys
NW_CMD=""          # command to launch the available network client

# Locale and Language
LANGSEL="/tmp/.language"
KEYSEL="/tmp/.keymap"
CURR_LOCALE="en_US.UTF-8"   # Default Locale
FONT=""                     # Set new font if necessary
KEYMAP="us"                 # Virtual console keymap. Default is "us"
XKBMAP="us"                 # X11 keyboard layout. Default is "us"
ZONE=""                     # For time
SUBZONE=""                  # For time
LOCALE="en_US.UTF-8"        # System locale. Default is "en_US.UTF-8"
PROFILES=""                 # iso-profiles path

# Menu highlighting (automated step progression)
HIGHLIGHT=0                 # Highlight items for Main Menu
HIGHLIGHT_SUB=0             # Highlight items for submenus
SUB_MENU=""                 # Submenu to be highlighted
PARENT=""                   # the parent menu

# Temporary files to store menu selections and errors
ANSWER="/tmp/.answer"          # Basic menu selections
PACKAGES="/tmp/.pkgs"       # Packages to install
MOUNT_OPTS="/tmp/.mnt_opts" # Filesystem Mount options
INIT="/tmp/.init"           # init systemd|openrc
ERR="/tmp/.errlog"
BRANCH="/tmp/.branch"

# Installer-Log
LOGFILE="/var/log/m-a.log"  # path for the installer log in the live environment
[[ ! -e $LOGFILE ]] && touch $LOGFILE
TARGLOG="/mnt/.m-a.log"     # path to copy the installer log to target install
INIFILE="/tmp/manjaro-architect.ini"

# file systems
BTRFS=0
LUKS=0
LUKS_DEV=""
LUKS_NAME=""
LUKS_OPT=""         # Default or user-defined?
LUKS_UUID=""
LVM=0
LVM_LV_NAME=""      # Name of LV to create or use
LVM_VG=""
LVM_VG_MB=0
VG_PARTS=""
LVM_SEP_BOOT=0      # 1 = Seperate /boot, 2 = seperate /boot & LVM
LV_SIZE_INVALID=0   # Is LVM LV size entered valid?
VG_SIZE_TYPE=""     # Is VG in Gigabytes or Megabytes?

# Mounting
MOUNT=""                # Installation: All other mounts branching
MOUNTPOINT="/mnt"               # Installation: Root mount from Root
FS_OPTS=""                      # File system special mount options available
CHK_NUM=16                      # Used for FS mount options checklist length
INCLUDE_PART='part\|lvm\|crypt' # Partition types to include for display and selection.
ROOT_PART=""                    # ROOT partition
UEFI_PART=""                    # UEFI partition
UEFI_MOUNT=""                   # UEFI mountpoint (/boot or /boot/efi)

# Edit Files
FILE=""          # File(s) to be reviewed

#input infos
declare -A ARGS=()


# Installation
DM_INST=""       # Which DMs have been installed?
DM_ENABLED=0     # Has a display manager been enabled?
NM_INST=""       # Which NMs have been installed?
NM_ENABLED=0     # Has a network connection manager been enabled?
GRAPHIC_CARD=""  # graphics card
INTEGRATED_GC="" # Integrated graphics card for NVIDIA
NVIDIA_INST=0    # Indicates if NVIDIA proprietary driver has been installed
NVIDIA=""        # NVIDIA driver(s) to install depending on kernel(s)
VB_MOD=""        # headers packages to install depending on kernel(s)
SHOW_ONCE=0      # Show de_wm information only once
COPY_PACCONF=0   # Copy over installer /etc/pacman.conf to installed system?

import(){
    if [[ -r $1 ]];then
        source $1
    else
        echo "Could not import $1"
    fi
}

DIALOG() {
    dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --column-separator "|" --exit-label "$_Back" --title "$@"
}

# store datas in ini file
#  read: value=$(ini system.init)
#  set:  ini system.init "openrc"
ini() {
    local section="$1" value="$2"
    [[ ! -f "$INIFILE" ]] && echo "">"$INIFILE"
    if [[ ! "$section" =~ \. ]]; then
        section="manjaro-architect.${section}"
    fi
    ini_val "$INIFILE" "$section" "$value" 2>/dev/null
}

function finishini {
    [[ -f "$INIFILE" ]] && mv "$INIFILE" "/var/log/m-a.ini" &>/dev/null
    ((debug)) && cat "/var/log/m-a.ini"
}
trap finishini EXIT

# read datas from ini file
# read: value=$(ini system.init)
inifile() {
    [[ -r "${ARGS[ini]}" ]] || return 1
    local section="$1"
    [[ "$section" =~ \. ]] || section="manjaro-architect.${section}"
    ini_val "${ARGS[ini]}" "$section" 2>/dev/null
}

# read console args , set in array ARGS global var
get_ARGS() {
    declare key param
    getvalue(){
        local value="${param##--${key}=}"
        [[ "${value:0:1}" == '"' ]] && value="${value/\"/}" # remove quotes
        echo "${value}"
    }
    while [ -n "$1" ]; do
        param="$1"
        case "${param}" in
            --debug|-d)
                ARGS[debug]=1
                ;; 
            --init=*)
                key="init"
                ARGS[$key]=$(getvalue)
                ;;
            --ini=*)
                key="ini"
                ARGS[$key]=$(getvalue)
                ;;
            --mount.root=*)
                key="mount.root"
                ARGS[$key]=$(getvalue)
                ;;
            --help|-h)
                echo -e "usage [-d|--debug] [--ini=\"file.ini\"] [ --init=openrc ]  "
                exit 0
                ;;
            -*)
                echo "${param}: not used";
                ;;
        esac
        shift
    done
    #declare -g -r ARGS
}
get_ARGS "$@"

# progress through menu entries until number $1 is reached
submenu() {
    if [[ $SUB_MENU != "$PARENT" ]]; then
        SUB_MENU="$PARENT"
        HIGHLIGHT_SUB=1
    elif [[ $HIGHLIGHT_SUB != "$1" ]]; then
        HIGHLIGHT_SUB=$(( HIGHLIGHT_SUB + 1 ))
    fi
}

# Adapted from AIS. Checks if system is made by Apple, whether the system is BIOS or UEFI,
# and for LVM and/or LUKS.
id_system() {
    printf "\n    :: $(pacman -Q manjaro-architect) ::\n\n" >> ${LOGFILE}

    echo "">"$INIFILE"
    ini version "$version"
    ini date "$(date +%D\ %T)"

    # Apple System Detection
    if [[ "$(cat /sys/class/dmi/id/sys_vendor)" == 'Apple Inc.' ]] || [[ "$(cat /sys/class/dmi/id/sys_vendor)" == 'Apple Computer, Inc.' ]]; then
        modprobe -r -q efivars || true  # if MAC
    else
        modprobe -q efivarfs             # all others
    fi

    # BIOS or UEFI Detection
    if [[ -d "/sys/firmware/efi/" ]]; then
        # Mount efivarfs if it is not already mounted
        if [[ -z $(mount | grep /sys/firmware/efi/efivars) ]]; then
            mount -t efivarfs efivarfs /sys/firmware/efi/efivars
        fi
        SYSTEM="UEFI"
    else
        SYSTEM="BIOS"
    fi
    ini system.bios "$SYSTEM"

    # init system
    if [ $(cat /proc/1/comm) == "systemd" ]; then
        H_INIT="systemd"
    else
        H_INIT="openrc"
    fi
    ini system.init "$H_INIT"

    ## TODO: Test which nw-client is available, including if the service according to $H_INIT is running
    [[ $H_INIT == "systemd" ]] && [[ $(systemctl is-active NetworkManager) == "active" ]] && NW_CMD=nmtui 2>$ERR

    check_for_error "system: $SYSTEM, init: $H_INIT nw-client: $NW_CMD"

    # evaluate host branch
    ini system.branch "$(grep -oE -m 1 "unstable|stable|testing" /etc/pacman.d/mirrorlist)"
}

# If there is an error, display it and go back to main menu. In any case, write to logfile.
# param 2 : error code is optional
# param 3 : return menu function , optional, default: main_menu_online
check_for_error() {
    local _msg="$1"
    local _err="${2:-0}"
    local _function_menu="${3:-main_menu}"
    ((${_err}!=0)) && _msg="[${_msg}][${_err}]"
    [[ -f "${ERR}" ]] && {
        _msg="${_msg} $(head -n1 ${ERR})"
        rm "${ERR}"
    }
    if ((${_err}!=0)) ; then
        # and function varsdump ? _msg="$_msg \n $(declare -p | grep -v " _")"
        local _fpath="${FUNCNAME[*]:1:2}()"
        _fpath=" --${_fpath// /()<-}"
        ! ((debug)) && _fpath=""
        echo -e "$(date +%D\ %T) ERROR ${_msg}${_fpath}" >> "${LOGFILE}"
        if [[  "${_function_menu}" != "SKIP" ]]; then
            DIALOG " $_ErrTitle " --msgbox "\n${_msg}\n" 0 0
            # return error for return to parent menu
            return $_err
        fi
    else
        # add $FUNCNAME limit to 20 max for control if recursive
        ((debug)) && _msg="${_msg} --${FUNCNAME[*]:1:20}"
        echo -e "$(date +%D\ %T) ${_msg}" >> "${LOGFILE}"
    fi
}

# Add locale on-the-fly and sets source translation file for installer
select_language() {
    fl="1" # terminus-font variation supporting most languages, to be processed in set_keymap()
    if [[ $(cat ${LANGSEL} 2>/dev/null) == "" ]]; then
        DIALOG " Select Language " --default-item '3' --menu "\n " 0 0 11 \
          "1" $"Danish|(da_DK)" \
          "2" $"Dutch|(nl_NL)" \
          "3" $"English|(en_**)" \
          "4" $"French|(fr_FR)" \
          "5" $"German|(de_DE)" \
          "6" $"Hungarian|(hu_HU)" \
          "7" $"Italian|(it_IT)" \
          "8" $"Portuguese|(pt_PT)" \
          "9" $"Portuguese [Brasil]|(pt_BR)" \
          "10" $"Russian|(ru_RU)" \
          "11" $"Spanish|(es_ES)" 2>${LANGSEL}
    fi

    case $(cat ${LANGSEL}) in
        "1") source $DATADIR/translations/danish.trans
             CURR_LOCALE="da_DK.UTF-8"
             ;;
        "2") source $DATADIR/translations/dutch.trans
             CURR_LOCALE="nl_NL.UTF-8"
             ;;
        "3") source $DATADIR/translations/english.trans
             CURR_LOCALE="en_US.UTF-8"
             ;;
        "4") source $DATADIR/translations/french.trans
             CURR_LOCALE="fr_FR.UTF-8"
             ;;
        "5") source $DATADIR/translations/german.trans
             CURR_LOCALE="de_DE.UTF-8"
             ;;
        "6") source $DATADIR/translations/hungarian.trans
             CURR_LOCALE="hu_HU.UTF-8"
             fl="2"
             ;;
        "7") source $DATADIR/translations/italian.trans
             CURR_LOCALE="it_IT.UTF-8"
             ;;
        "8") source $DATADIR/translations/portuguese.trans
             CURR_LOCALE="pt_PT.UTF-8"
             ;;
        "9") source $DATADIR/translations/portuguese_brasil.trans
             CURR_LOCALE="pt_BR.UTF-8"
             ;;
        "10") source $DATADIR/translations/russian.trans
             CURR_LOCALE="ru_RU.UTF-8"
             fl="u"
             ;;
        "11") source $DATADIR/translations/spanish.trans
             CURR_LOCALE="es_ES.UTF-8"
             ;;
        *) clear && exit 0
             ;;
    esac

    if [[ $(cat ${KEYSEL} 2>/dev/null) == "" ]]; then
        set_keymap
    fi

    # Generate the chosen locale and set the language
    DIALOG " $_Config " --infobox "\n$_ApplySet\n " 0 0
    sed -i "s/#${CURR_LOCALE}/${CURR_LOCALE}/" /etc/locale.gen
    locale-gen >/dev/null 2>$ERR
    export LANG=${CURR_LOCALE}

    check_for_error "set LANG=${CURR_LOCALE}" $?
    ini system.lang "$CURR_LOCALE"
}

# virtual console keymap and font
set_keymap() {
    KEYMAPS=""
    for i in $(ls -R /usr/share/kbd/keymaps | grep "map.gz" | sed 's/\.map\.gz//g' | sort); do
        KEYMAPS="${KEYMAPS} ${i} -"
    done

    DIALOG " $_VCKeymapTitle " --menu "\n$_VCKeymapBody\n " 20 40 20 ${KEYMAPS} 2>${KEYSEL} || return 0
    KEYMAP=$(cat ${KEYSEL})

    loadkeys $KEYMAP 2>$ERR
    check_for_error "loadkeys $KEYMAP" "$?"
    ini linux.keymap "$KEYMAP"
    # set keymap for openrc too
    echo "keymap=\"$KEYMAP\"" > /tmp/keymap
    biggest_resolution=$(head -n 1 /sys/class/drm/card*/*/modes | awk -F'[^0-9]*' '{print $1}' | awk 'BEGIN{a=   0}{if ($1>a) a=$1 fi} END{print a}')
    # Choose terminus font size depending on resolution
    if [[ $biggest_resolution -gt 1920 ]]; then
        fs="24"
    elif [[ $biggest_resolution -eq 1920 ]]; then
        fs="18"
    else
        fs="16"
    fi
    FONT="ter-${fl}${fs}n"
    ini linux.font "$FONT"
    echo -e "KEYMAP=${KEYMAP}\nFONT=${FONT}" > /tmp/vconsole.conf
    echo -e "consolefont=\"${FONT}\"" > /tmp/consolefont

    setfont $FONT 2>$ERR
    check_for_error "set font $FONT" $?
    ini system.font "$FONT"
}

mk_connection() {
    if [[ ! $(ping -c 2 google.com) ]]; then
        DIALOG " $_NoCon " --yesno "\n$_EstCon\n " 0 0 && $NW_CMD && return 0 || clear && exit 0
    fi
}

# Check user is root, and that there is an active internet connection
# Seperated the checks into seperate "if" statements for readability.
check_requirements() {
    DIALOG " $_ChkTitle " --infobox "\n$_ChkBody\n " 0 0
    sleep 2

    if [[ `whoami` != "root" ]]; then
        DIALOG " $_Erritle " --infobox "\n$_RtFailBody\n " 0 0
        sleep 2
        exit 1
    fi

    if [[ ! $(ping -c 1 google.com) ]]; then
        DIALOG " $_ErrTitle " --infobox "\n$_ConFailBody\n " 0 0
        sleep 2
        exit 1
    fi

    # This will only be executed where neither of the above checks are true.
    # The error log is also cleared, just in case something is there from a previous use of the installer.
    DIALOG " $_ReqMetTitle " --infobox "\n$_ReqMetBody\n\n$_UpdDb\n " 0 0
    sleep 2
    clear
    echo "" > $ERR
    pacman -Syy 2>$ERR
    check_for_error "refresh database" $? SKIP
}

# Greet the user when first starting the installer
greeting() {
    DIALOG " $_WelTitle $VERSION " --msgbox "\n$_WelBody\n " 0 0
}

# Originally adapted from AIS. Added option to allow users to edit the mirrorlist.
configure_mirrorlist() {
    HIGHLIGHT_SUB=1
    declare -i loopmenu=1
    while ((loopmenu)); do
        DIALOG " $_MirrorlistTitle " --default-item ${HIGHLIGHT_SUB} --menu "\n$_MirrorlistBody\n " 0 0 4 \
          "1" "$_MirrorPacman" \
          "2" "$_MirrorConfig" \
          "3" "$_MirrorRankTitle" \
          "4" "$_Back" 2>${ANSWER}

        case $(cat ${ANSWER}) in
            "1") nano /etc/pacman.conf
                DIALOG " $_MirrorPacman " --yesno "\n$_MIrrorPacQ\n " 0 0 && COPY_PACCONF=1 || COPY_PACCONF=0
                check_for_error "edit pacman.conf $COPY_PACCONF"
                DIALOG "" --infobox "\n$_UpdDb\n " 0 0
                pacman -Syy
                HIGHLIGHT_SUB=2
                ;;
            "2") nano /etc/pacman-mirrors.conf
                check_for_error "edit pacman-mirrors.conf"
                HIGHLIGHT_SUB=3
                ;;
            "3") rank_mirrors
                HIGHLIGHT_SUB=4
                ;;

            *) HIGHLIGHT_SUB=1
                loopmeu=0
                return 0
                ;;
        esac
    done
}

rank_mirrors() {
    #Choose the branch for mirrorlist
    DIALOG " $_MirrorBranch " --radiolist "\n$_UseSpaceBar\n " 0 0 3 \
      "stable" "-" on \
      "testing" "-" off \
      "unstable" "-" off 2>${ANSWER}
    local branch="$(<{ANSWER})"
    clear
    if [[ ! -z ${branch} ]]; then
        pacman-mirrors -gib "${branch}"
        ini branch "${branch}"
    fi
}

# Simple code to show devices / partitions.
show_devices() {
    lsblk -o NAME,MODEL,TYPE,FSTYPE,SIZE,MOUNTPOINT | grep "disk\|part\|lvm\|crypt\|NAME\|MODEL\|TYPE\|FSTYPE\|SIZE\|MOUNTPOINT" > /tmp/.devlist
    DIALOG " $_DevShowOpt " --textbox /tmp/.devlist 0 0
}

# Adapted from AIS. An excellent bit of code!
arch_chroot() {
    manjaro-chroot $MOUNTPOINT "${1}"
}

# Ensure that a partition is mounted
check_mount() {
    if [[ $(lsblk -o MOUNTPOINT | grep ${MOUNTPOINT}) == "" ]]; then
        DIALOG " $_ErrTitle " --msgbox "\n$_ErrNoMount\n " 0 0
        ANSWER=0
        HIGHLIGHT=0
        return 1
    fi
}

# Ensure that Manjaro has been installed
check_base() {
    check_mount
    if [[ $? -eq 0 ]]; then
        if [[ ! -e /mnt/.base_installed ]]; then
            DIALOG " $_ErrTitle " --msgbox "\n$_ErrNoBase\n " 0 0
            ANSWER=1
            HIGHLIGHT=1
            HIGHLIGHT_SUB=2
            return 1
        fi
    else
        return 1
    fi
}

# install a pkg in the live session if not installed
inst_needed() {
    if [[ ! $(pacman -Q $1) ]]; then
        DIALOG " $_InstPkg " --infobox "\n$_InstPkg '${1}'\n " 0 0
        sleep 2
        clear
        pacman -Sy --noconfirm $1 2>$ERR
        check_for_error "Install needed pkg $1." $?
    fi
}

# return list of profiles not containing >openrc flag in Packages-Desktop
evaluate_profiles() {
    echo "" > /tmp/.systemd_only
    for p in $(find $PROFILES/{manjaro,community} -mindepth 1 -maxdepth 1 -type d ! -name 'netinstall' ! -name 'architect'); do
        [[ ! $(grep ">openrc" $p/Packages-Desktop) ]] && echo $p | cut -f7 -d'/' >> /tmp/.systemd_only
    done
    echo $(cat /tmp/.systemd_only)
}

# verify if profile is available for openrc
evaluate_openrc() {
    if [[ ! $(grep ">openrc" $PROFILES/*/$(cat /tmp/.desktop)/Packages-Desktop) ]]; then
        DIALOG " $_ErrInit " --menu "\n[Manjaro-$(cat /tmp/.desktop)] $_WarnInit\n " 0 0 2 \
          "1" "$_DiffPro" \
          "2" "$_InstSystd" 2>${ANSWER}
        check_for_error "selected systemd-only profile [$(cat /tmp/.desktop)] with openrc base. -> $(cat ${ANSWER})"
        case $(cat ${ANSWER}) in
            "1") install_desktop_menu
            ;;
            "2") install_base
            ;;
        esac
    fi
}  

final_check() {
    CHECKLIST=/tmp/.final_check
    # Empty the list
    echo "" > ${CHECKLIST}

    # Check if base is installed
    if [[ ! -e /mnt/.base_installed ]]; then
        echo "- $_BaseCheck" >> ${CHECKLIST}
    else
        # Check if bootloader is installed
        if [[ $SYSTEM == "BIOS" ]]; then
            arch_chroot "pacman -Qq grub" &> /dev/null || echo "- $_BootlCheck" >> ${CHECKLIST}
        else
            [[ -e /mnt/boot/efi/EFI/manjaro_grub/grubx64.efi ]] || [[ -e /mnt/boot/EFI/manjaro_grub/grubx64.efi ]] || echo "- $_BootlCheck" >> ${CHECKLIST}
        fi

        # Check if fstab is generated
        $(grep -qv '^#' /mnt/etc/fstab 2>/dev/null) || echo "- $_FstabCheck" >> ${CHECKLIST}

        # Check if video-driver has been installed
        [[ ! -e /mnt/.video_installed ]] && echo "- $_GCCheck" >> ${CHECKLIST}

        # Check if locales have been generated
        [[ $(manjaro-chroot /mnt 'locale -a' | wc -l) -ge '3' ]] || echo "- $_LocaleCheck" >> ${CHECKLIST}

        # Check if root password has been set
        manjaro-chroot /mnt 'passwd --status root' | cut -d' ' -f2 | grep -q 'NP' && echo "- $_RootCheck" >> ${CHECKLIST}

        # check if user account has been generated
        [[ $(ls /mnt/home 2>/dev/null) == "" ]] && echo "- $_UserCheck" >> ${CHECKLIST}
    fi
}

exit_done() {
    if [[ $(lsblk -o MOUNTPOINT | grep ${MOUNTPOINT} 2>/dev/null) != "" ]]; then
        final_check
        dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --yesno "$(printf "\n$_CloseInstBody\n$(cat ${CHECKLIST})\n ")" 0 0
        if [[ $? -eq 0 ]]; then
            check_for_error "exit installer."
            dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --yesno "\n$_LogInfo ${TARGLOG}\n " 0 0
            if [[ $? -eq 0 ]]; then
                [[ -e ${TARGLOG} ]] && cat ${LOGFILE} >> ${TARGLOG} || cp ${LOGFILE} ${TARGLOG}
            fi
            umount_partitions
            clear
            exit 0
        else
            [[ menu_opt == "advanced" ]] && main_menu_full || main_menu
        fi
    else
        dialog --backtitle "$VERSION - $SYSTEM ($ARCHI)" --yesno "\n$_CloseInstBody\n " 0 0
        if [[ $? -eq 0 ]]; then
            umount_partitions
            clear
            exit 0
        else
            [[ menu_opt == "advanced" ]] && main_menu_full || main_menu
        fi
    fi
}
