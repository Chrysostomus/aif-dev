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

# Unmount partitions.
umount_partitions() {
    MOUNTED=""
    MOUNTED=$(mount | grep "${MOUNTPOINT}" | awk '{print $3}' | sort -r)
    swapoff -a

    for i in ${MOUNTED[@]}; do
        umount $i >/dev/null 2>$ERR
        check_for_error "unmount $i" $?
 #       local err=$(umount $i >/dev/null 2>$ERR)
 #       (( err !=0 )) && check_for_error "$FUNCNAME $i" $err
    done
}

# This function does not assume that the formatted device is the Root installation device as
# more than one device may be formatted. Root is set in the mount_partitions function.
select_device() {
    DEVICE=""
    devices_list=$(lsblk -lno NAME,SIZE,TYPE | grep 'disk' | awk '{print "/dev/" $1 " " $2}' | sort -u);

    for i in ${devices_list[@]}; do
        DEVICE="${DEVICE} ${i}"
    done

    DIALOG " $_DevSelTitle " --menu "\n$_DevSelBody\n " 0 0 4 ${DEVICE} 2>${ANSWER} || return 1
    DEVICE=$(cat ${ANSWER})
}

create_partitions() {
    # Partitioning Menu
    DIALOG " $_PrepPartDisk " --menu "\n$_PartToolBody\n " 0 0 7 \
      "$_PartOptWipe" "BIOS & UEFI" \
      "$_PartOptAuto" "BIOS & UEFI" \
      "cfdisk" "BIOS" \
      "cgdisk" "UEFI" \
      "fdisk"  "BIOS & UEFI" \
      "gdisk"  "UEFI" \
      "parted" "BIOS & UEFI" 2>${ANSWER} || return 0

    clear
    # If something selected
    if [[ $(cat ${ANSWER}) != "" ]]; then
        if ([[ $(cat ${ANSWER}) != "$_PartOptWipe" ]] && [[ $(cat ${ANSWER}) != "$_PartOptAuto" ]]); then
            $(cat ${ANSWER}) ${DEVICE}
        else
            [[ $(cat ${ANSWER}) == "$_PartOptWipe" ]] && secure_wipe && create_partitions
            [[ $(cat ${ANSWER}) == "$_PartOptAuto" ]] && auto_partition
        fi
    fi
}

# Securely destroy all data on a given device.
secure_wipe() {
    # Warn the user. If they proceed, wipe the selected device.
    DIALOG " $_PartOptWipe " --yesno "\n$_AutoPartWipeBody1 ${DEVICE} $_AutoPartWipeBody2\n " 0 0
    if [[ $? -eq 0 ]]; then
        # Install wipe where not already installed. Much faster than dd
        inst_needed wipe

        wipe -Ifre ${DEVICE} 2>$ERR
        check_for_error "wipe ${DEVICE}" $?

        # Alternate dd command - requires pv to be installed
        #dd if=/dev/zero | pv | dd of=${DEVICE} iflag=nocache oflag=direct bs=4096 2>$ERR
    fi
}

# BIOS and UEFI
auto_partition() {
    # Provide warning to user
    DIALOG " $_PrepPartDisk " --yesno "\n$_AutoPartBody1 $DEVICE $_AutoPartBody2 $_AutoPartBody3\n " 0 0

    if [[ $? -eq 0 ]]; then
        # Find existing partitions (if any) to remove
        parted -s ${DEVICE} print | awk '/^ / {print $1}' > /tmp/.del_parts

        for del_part in $(tac /tmp/.del_parts); do
            parted -s ${DEVICE} rm ${del_part} 2>$ERR
            check_for_error "rm ${del_part} on ${DEVICE}" $?
        done

        # Identify the partition table
        part_table=$(parted -s ${DEVICE} print | grep -i 'partition table' | awk '{print $3}' >/dev/null 2>&1)
        check_for_error "${DEVICE} is $part_table"

        # Create partition table if one does not already exist
        if [[ $SYSTEM == "BIOS" ]] && [[ $part_table != "msdos" ]] ; then 
            parted -s ${DEVICE} mklabel msdos 2>$ERR
            check_for_error "${DEVICE} mklabel msdos" $?
        fi
        if [[ $SYSTEM == "UEFI" ]] && [[ $part_table != "gpt" ]] ; then 
            parted -s ${DEVICE} mklabel gpt 2>$ERR
            check_for_error "${DEVICE} mklabel gpt" $?
        fi

        # Create partitions (same basic partitioning scheme for BIOS and UEFI)
        if [[ $SYSTEM == "BIOS" ]]; then
            parted -s ${DEVICE} mkpart primary ext3 1MiB 513MiB 2>$ERR
            check_for_error "create ext3 513MiB on ${DEVICE}" $?
        else
            parted -s ${DEVICE} mkpart ESP fat32 1MiB 513MiB 2>$ERR
            check_for_error "create ESP on ${DEVICE}" $?
        fi

        parted -s ${DEVICE} set 1 boot on 2>$ERR
        check_for_error "set boot flag for ${DEVICE}" $?
        parted -s ${DEVICE} mkpart primary ext3 513MiB 100% 2>$ERR
        check_for_error "create ext3 100% on ${DEVICE}" $?

        # Show created partitions
        lsblk ${DEVICE} -o NAME,TYPE,FSTYPE,SIZE > /tmp/.devlist
        DIALOG "" --textbox /tmp/.devlist 0 0
    fi
}
    
# Finds all available partitions according to type(s) specified and generates a list
# of them. This also includes partitions on different devices.
find_partitions() {
    PARTITIONS=""
    NUMBER_PARTITIONS=0
    partition_list=$(lsblk -lno NAME,SIZE,TYPE | grep $INCLUDE_PART | sed 's/part$/\/dev\//g' | sed 's/lvm$\|crypt$/\/dev\/mapper\//g' | \
    awk '{print $3$1 " " $2}' | awk '!/mapper/{a[++i]=$0;next}1;END{while(x<length(a))print a[++x]}')

    for i in ${partition_list}; do
        PARTITIONS="${PARTITIONS} ${i}"
        NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS + 1 ))
    done

    # Double-partitions will be counted due to counting sizes, so fix
    NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS / 2 ))

    check_for_error "--------- [lsblk] ------------"
    local parts=($PARTITIONS)
    for i in ${!parts[@]}; do
        (( $i % 2 == 0 )) || continue
        local j=$((i+1))
        check_for_error "${parts[i]} ${parts[j]}"
    done    

    #for test delete /dev:sda8
    #delete_partition_in_list "/dev/sda8"

    # Deal with partitioning schemes appropriate to mounting, lvm, and/or luks.
    case $INCLUDE_PART in
        'part\|lvm\|crypt')
            # Deal with incorrect partitioning for main mounting function
            if ([[ $SYSTEM == "UEFI" ]] && [[ $NUMBER_PARTITIONS -lt 2 ]]) || ([[ $SYSTEM == "BIOS" ]] && [[ $NUMBER_PARTITIONS -eq 0 ]]); then
                DIALOG " $_ErrTitle " --msgbox "\n$_PartErrBody\n " 0 0
                create_partitions
            fi
            ;;
        'part\|crypt')
            # Ensure there is at least one partition for LVM
            if [[ $NUMBER_PARTITIONS -eq 0 ]]; then
                DIALOG " $_ErrTitle " --msgbox "\n$_LvmPartErrBody\n " 0 0
                create_partitions
            fi
            ;;
        'part\|lvm') # Ensure there are at least two partitions for LUKS
            if [[ $NUMBER_PARTITIONS -lt 2 ]]; then
                DIALOG " $_ErrTitle " --msgbox "\n$_LuksPartErrBody\n " 0 0
                create_partitions
            fi
            ;;
    esac    
}

## List partitions to be hidden from the mounting menu
list_mounted() {
    lsblk -l | awk '$7 ~ /mnt/ {print $1}' > /tmp/.mounted
    check_for_error "already mounted: $(cat /tmp/.mounted)"
    echo /dev/* /dev/mapper/* | xargs -n1 2>/dev/null | grep -f /tmp/.mounted
}

list_containing_crypt() {
    blkid | awk '/TYPE="crypto_LUKS"/{print $1}' | sed 's/.$//'
}

list_non_crypt() {
    blkid | awk '!/TYPE="crypto_LUKS"/{print $1}' | sed 's/.$//'
}

# delete partition in list $PARTITIONS
# param: partition to delete
delete_partition_in_list() {
    [ -z "$1" ] && return 127
    local parts=($PARTITIONS)
    for i in ${!parts[@]}; do
        (( $i % 2 == 0 )) || continue
        if [[ "${parts[i]}" = "$1" ]]; then
            local j=$((i+1))
            unset parts[$j]
            unset parts[$i]
            check_for_error "in partitions delete item $1 no: $i / $j"
            PARTITIONS="${parts[*]}"
            check_for_error "partitions: $PARTITIONS"
            NUMBER_PARTITIONS=$(( "${#parts[*]}" / 2 ))
            return 0
        fi
    done
    return 0
}

# Revised to deal with partion sizes now being displayed to the user
confirm_mount() {
    if [[ $(mount | grep $1) ]]; then
        DIALOG " $_MntStatusTitle " --infobox "\n$_MntStatusSucc\n " 0 0
        sleep 2
        PARTITIONS=$(echo $PARTITIONS | sed "s~${PARTITION} [0-9]*[G-M]~~" | sed "s~${PARTITION} [0-9]*\.[0-9]*[G-M]~~" | sed s~${PARTITION}$' -'~~)
        NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS - 1 ))
    else
        DIALOG " $_MntStatusTitle " --infobox "\n$_MntStatusFail\n " 0 0
        sleep 2
        return 1
    fi
}

# Set static list of filesystems rather than on-the-fly. Partially as most require additional flags, and
# partially because some don't seem to be viable.
# Set static list of filesystems rather than on-the-fly.
select_filesystem() {
    # prep variables
    fs_opts=""
    CHK_NUM=0

    local option="${ARGS[mount.${PARTITION}]}"
    [[ -z "$option" ]] && option=$(inifile "mount.${PARTITION}")
    if [[ -z "$option" ]]; then
        DIALOG " $_FSTitle " --menu "\n${PARTITION}\n$_FSBody\n " 0 0 12 \
        "$_FSSkip" "-" \
            "btrfs" "mkfs.btrfs -f" \
            "ext3" "mkfs.ext3 -q" \
            "ext4" "mkfs.ext4 -q" \
            "jfs" "mkfs.jfs -q" \
            "nilfs2" "mkfs.nilfs2 -fq" \
            "ntfs" "mkfs.ntfs -q" \
            "reiserfs" "mkfs.reiserfs -q" \
            "vfat" "mkfs.vfat -F32" \
            "xfs" "mkfs.xfs -f" 2>${ANSWER} || return 1
    else
        echo "$option">${ANSWER}
    fi
        
    case $(cat ${ANSWER}) in
        "$_FSSkip") FILESYSTEM="$_FSSkip"
            ;;
        "btrfs") FILESYSTEM="mkfs.btrfs -f"
            CHK_NUM=16
            fs_opts="autodefrag compress=zlib compress=lzo compress=no compress-force=zlib compress-force=lzo discard \
            noacl noatime nodatasum nospace_cache recovery skip_balance space_cache ssd ssd_spread"
            modprobe btrfs
            ;;
        "ext2") FILESYSTEM="mkfs.ext2 -q"
            ;;
        "ext3") FILESYSTEM="mkfs.ext3 -q"
            ;;
        "ext4") FILESYSTEM="mkfs.ext4 -q"
            CHK_NUM=8
            fs_opts="data=journal data=writeback dealloc discard noacl noatime nobarrier nodelalloc"
            ;;
        "f2fs") FILESYSTEM="mkfs.f2fs -q"
            fs_opts="data_flush disable_roll_forward disable_ext_identify discard fastboot flush_merge \
            inline_xattr inline_data inline_dentry no_heap noacl nobarrier noextent_cache noinline_data norecovery"
            CHK_NUM=16
            modprobe f2fs
            ;;
        "jfs") FILESYSTEM="mkfs.jfs -q"
            CHK_NUM=4
            fs_opts="discard errors=continue errors=panic nointegrity"
            ;;
        "nilfs2") FILESYSTEM="mkfs.nilfs2 -fq"
            CHK_NUM=7
            fs_opts="discard nobarrier errors=continue errors=panic order=relaxed order=strict norecovery"
            ;;
        "ntfs") FILESYSTEM="mkfs.ntfs -q"
            ;;
        "reiserfs") FILESYSTEM="mkfs.reiserfs -q"
            CHK_NUM=5
            fs_opts="acl nolog notail replayonly user_xattr"
            ;;
        "vfat") FILESYSTEM="mkfs.vfat -F32"
            ;;
        "xfs") FILESYSTEM="mkfs.xfs -f"
            CHK_NUM=9
            fs_opts="discard filestreams ikeep largeio noalign nobarrier norecovery noquota wsync"
            ;;
        *)  return 1
            ;;
    esac

    # Warn about formatting!
    if [[ $FILESYSTEM != $_FSSkip ]]; then
        DIALOG " $_FSTitle " --yesno "\n$_FSMount $FILESYSTEM\n\n! $_FSWarn1 $PARTITION $_FSWarn2 !\n " 0 0
        if (( $? != 1 )); then
            ${FILESYSTEM} ${PARTITION} >/dev/null 2>$ERR
            check_for_error "mount ${PARTITION} as ${FILESYSTEM}." $? || return 1
            ini "mount.${PARTITION}" $(echo "${FILESYSTEM:5}|cut -d' ' -f1")
        fi
    fi
}

# This subfunction allows for special mounting options to be applied for relevant fs's.
# Seperate subfunction for neatness.
mount_opts() {
    FS_OPTS=""

    for i in ${fs_opts}; do
        FS_OPTS="${FS_OPTS} ${i} - off"
    done

    DIALOG " $(echo $FILESYSTEM | sed "s/.*\.//g;s/-.*//g") " --checklist "\n$_btrfsMntBody\n " 0 0 \
      $CHK_NUM $FS_OPTS 2>${MOUNT_OPTS}

    # Now clean up the file
    sed -i 's/ /,/g' ${MOUNT_OPTS}
    sed -i '$s/,$//' ${MOUNT_OPTS}

    # If mount options selected, confirm choice
    if [[ $(cat ${MOUNT_OPTS}) != "" ]]; then
        DIALOG " $_MntStatusTitle " --yesno "\n${_btrfsMntConfBody}$(cat ${MOUNT_OPTS})\n " 10 75
        [[ $? -eq 1 ]] && echo "" > ${MOUNT_OPTS}
    fi
}

mount_current_partition() {
    # Make the mount directory
    mkdir -p ${MOUNTPOINT}${MOUNT} 2>$ERR
    check_for_error "create mountpoint ${MOUNTPOINT}${MOUNT}" "$?"

    echo "" > ${MOUNT_OPTS}
    # Get mounting options for appropriate filesystems
    [[ $fs_opts != "" ]] && mount_opts

    # Use special mounting options if selected, else standard mount
    if [[ $(cat ${MOUNT_OPTS}) != "" ]]; then
        check_for_error "mount ${PARTITION} $(cat ${MOUNT_OPTS})"
        mount -o $(cat ${MOUNT_OPTS}) ${PARTITION} ${MOUNTPOINT}${MOUNT} 2>>$LOGFILE
    else
        check_for_error "mount ${PARTITION}"
        mount ${PARTITION} ${MOUNTPOINT}${MOUNT} 2>>$LOGFILE
    fi
    confirm_mount ${MOUNTPOINT}${MOUNT}

    # Identify if mounted partition is type "crypt" (LUKS on LVM, or LUKS alone)
    if [[ $(lsblk -lno TYPE ${PARTITION} | grep "crypt") != "" ]]; then
        # cryptname for bootloader configuration either way
        LUKS=1
        LUKS_NAME=$(echo ${PARTITION} | sed "s~^/dev/mapper/~~g")

        # Check if LUKS on LVM (parent = lvm /dev/mapper/...)
        cryptparts=$(lsblk -lno NAME,FSTYPE,TYPE | grep "lvm" | grep -i "crypto_luks" | uniq | awk '{print "/dev/mapper/"$1}')
        for i in ${cryptparts}; do
            if [[ $(lsblk -lno NAME ${i} | grep $LUKS_NAME) != "" ]]; then
                LUKS_DEV="$LUKS_DEV cryptdevice=${i}:$LUKS_NAME"
                LVM=1
                return 0;
            fi
        done

        # Check if LUKS alone (parent = part /dev/...)
        cryptparts=$(lsblk -lno NAME,FSTYPE,TYPE | grep "part" | grep -i "crypto_luks" | uniq | awk '{print "/dev/"$1}')
        for i in ${cryptparts}; do
            if [[ $(lsblk -lno NAME ${i} | grep $LUKS_NAME) != "" ]]; then
                LUKS_UUID=$(lsblk -lno UUID,TYPE,FSTYPE ${i} | grep "part" | grep -i "crypto_luks" | awk '{print $1}')
                LUKS_DEV="$LUKS_DEV cryptdevice=UUID=$LUKS_UUID:$LUKS_NAME"
                return 0;
            fi
        done

        # If LVM logical volume....
    elif [[ $(lsblk -lno TYPE ${PARTITION} | grep "lvm") != "" ]]; then
        LVM=1

        # First get crypt name (code above would get lv name)
        cryptparts=$(lsblk -lno NAME,TYPE,FSTYPE | grep "crypt" | grep -i "lvm2_member" | uniq | awk '{print "/dev/mapper/"$1}')
        for i in ${cryptparts}; do
            if [[ $(lsblk -lno NAME ${i} | grep $(echo $PARTITION | sed "s~^/dev/mapper/~~g")) != "" ]]; then
                LUKS_NAME=$(echo ${i} | sed s~/dev/mapper/~~g)
                return 0;
            fi
        done

        # Now get the device (/dev/...) for the crypt name
        cryptparts=$(lsblk -lno NAME,FSTYPE,TYPE | grep "part" | grep -i "crypto_luks" | uniq | awk '{print "/dev/"$1}')
        for i in ${cryptparts}; do
            if [[ $(lsblk -lno NAME ${i} | grep $LUKS_NAME) != "" ]]; then
                # Create UUID for comparison
                LUKS_UUID=$(lsblk -lno UUID,TYPE,FSTYPE ${i} | grep "part" | grep -i "crypto_luks" | awk '{print $1}')

                # Check if not already added as a LUKS DEVICE (i.e. multiple LVs on one crypt). If not, add.
                if [[ $(echo $LUKS_DEV | grep $LUKS_UUID) == "" ]]; then
                    LUKS_DEV="$LUKS_DEV cryptdevice=UUID=$LUKS_UUID:$LUKS_NAME"
                    LUKS=1
                fi

                return 0;
            fi
        done
    fi
}

make_swap() {
    # Ask user to select partition or create swapfile
    DIALOG " $_PrepMntPart " --menu "\n$_SelSwpBody\n " 0 0 12 "$_SelSwpNone" $"-" "$_SelSwpFile" $"-" ${PARTITIONS} 2>${ANSWER} || return 0

    if [[ $(cat ${ANSWER}) != "$_SelSwpNone" ]]; then
        PARTITION=$(cat ${ANSWER})

        if [[ $PARTITION == "$_SelSwpFile" ]]; then
            total_memory=$(grep MemTotal /proc/meminfo | awk '{print $2/1024}' | sed 's/\..*//')
            DIALOG " $_SelSwpFile " --inputbox "\nM = MB, G = GB\n " 9 30 "${total_memory}M" 2>${ANSWER} || return 0
            m_or_g=$(cat ${ANSWER})

            while [[ $(echo ${m_or_g: -1} | grep "M\|G") == "" ]]; do
                DIALOG " $_SelSwpFile " --msgbox "\n$_SelSwpFile $_ErrTitle: M = MB, G = GB\n " 0 0
                DIALOG " $_SelSwpFile " --inputbox "\nM = MB, G = GB\n " 9 30 "${total_memory}M" 2>${ANSWER} || return 0
                m_or_g=$(cat ${ANSWER})
            done

            fallocate -l ${m_or_g} ${MOUNTPOINT}/swapfile 2>$ERR
            check_for_error "Swapfile fallocate" "$?"
            chmod 600 ${MOUNTPOINT}/swapfile 2>$ERR
            check_for_error "Swapfile chmod" "$?"
            mkswap ${MOUNTPOINT}/swapfile 2>$ERR
            check_for_error "Swapfile mkswap" "$?"
            swapon ${MOUNTPOINT}/swapfile 2>$ERR
            check_for_error "Swapfile swapon" "$?"

        else # Swap Partition
            # Warn user if creating a new swap
            if [[ $(lsblk -o FSTYPE  ${PARTITION} | grep -i "swap") != "swap" ]]; then
                DIALOG " $_PrepMntPart " --yesno "\nmkswap ${PARTITION}\n " 0 0
                if [[ $? -eq 0 ]]; then
                    mkswap ${PARTITION} >/dev/null 2>$ERR
                    check_for_error "Swap partition: mkswap" "$?"
                else
                    return 0
                fi
            fi
            # Whether existing to newly created, activate swap
            swapon  ${PARTITION} >/dev/null 2>$ERR
            check_for_error "Swap partition: swapon" "$?"
            # Since a partition was used, remove that partition from the list
            PARTITIONS=$(echo $PARTITIONS | sed "s~${PARTITION} [0-9]*[G-M]~~" | sed "s~${PARTITION} [0-9]*\.[0-9]*[G-M]~~" | sed s~${PARTITION}$' -'~~)
            NUMBER_PARTITIONS=$(( NUMBER_PARTITIONS - 1 ))
        fi
    fi
    ini mount.swap "${PARTITION}"
}

# Had to write it in this way due to (bash?) bug(?), as if/then statements in a single
# "create LUKS" function for default and "advanced" modes were interpreted as commands,
# not mere string statements. Not happy with it, but it works...
luks_password() {
    DIALOG " $_PrepLUKS " --clear --insecure --passwordbox "\n$_LuksPassBody\n " 0 0 2> ${ANSWER} || return 0
    PASSWD=$(cat ${ANSWER})

    DIALOG " $_PrepLUKS " --clear --insecure --passwordbox "\n$_PassReEntBody\n " 0 0 2> ${ANSWER} || return 0
    PASSWD2=$(cat ${ANSWER})

    if [[ $PASSWD != $PASSWD2 ]]; then
        DIALOG " $_ErrTitle " --msgbox "\n$_PassErrBody\n " 0 0
        luks_password
    fi
}

luks_open() {
    LUKS_ROOT_NAME=""
    INCLUDE_PART='part\|crypt\|lvm'
    umount_partitions
    find_partitions
    # Filter out partitions that don't contain crypt device
    list_non_crypt > /tmp/.ignore_part
 
    for part in $(cat /tmp/.ignore_part); do
        delete_partition_in_list $part
    done

    # Select encrypted partition to open
    DIALOG " $_LuksOpen " --menu "\n$_LuksMenuBody\n " 0 0 12 ${PARTITIONS} 2>${ANSWER} || return 1
    PARTITION=$(cat ${ANSWER})

    # Enter name of the Luks partition and get password to open it
    DIALOG " $_LuksOpen " --inputbox "\n$_LuksOpenBody\n " 10 50 "cryptroot" 2>${ANSWER} || return 1
    LUKS_ROOT_NAME=$(cat ${ANSWER})
    luks_password

    # Try to open the luks partition with the credentials given. If successful show this, otherwise
    # show the error
    DIALOG " $_LuksOpen " --infobox "\n$_PlsWaitBody\n " 0 0
    echo $PASSWD | cryptsetup open --type luks ${PARTITION} ${LUKS_ROOT_NAME} 2>$ERR
    check_for_error "luks pwd ${PARTITION} ${LUKS_ROOT_NAME}" "$?"

    lsblk -o NAME,TYPE,FSTYPE,SIZE,MOUNTPOINT ${PARTITION} | grep "crypt\|NAME\|MODEL\|TYPE\|FSTYPE\|SIZE" > /tmp/.devlist
    DIALOG " $_DevShowOpt " --textbox /tmp/.devlist 0 0
}

luks_setup() {
    modprobe -a dm-mod dm_crypt
    INCLUDE_PART='part\|lvm'
    umount_partitions
    find_partitions
    # Select partition to encrypt
    DIALOG " $_LuksEncrypt " --menu "\n$_LuksCreateBody\n " 0 0 12 ${PARTITIONS} 2>${ANSWER} || return 1
    PARTITION=$(cat ${ANSWER})

    # Enter name of the Luks partition and get password to create it
    DIALOG " $_LuksEncrypt " --inputbox "\n$_LuksOpenBody\n " 10 50 "cryptroot" 2>${ANSWER} || return 1
    LUKS_ROOT_NAME=$(cat ${ANSWER})
    luks_password
}

luks_default() {
    # Encrypt selected partition or LV with credentials given
    DIALOG " $_LuksEncrypt " --infobox "\n$_PlsWaitBody\n " 0 0
    sleep 2
    echo $PASSWD | cryptsetup -q luksFormat ${PARTITION} 2>$ERR
    check_for_error "luksFormat ${PARTITION}" $?

    # Now open the encrypted partition or LV
    echo $PASSWD | cryptsetup open ${PARTITION} ${LUKS_ROOT_NAME} 2>$ERR
    check_for_error "open ${PARTITION} ${LUKS_ROOT_NAME}" $?
}

luks_key_define() {
    DIALOG " $_PrepLUKS " --inputbox "\n$_LuksCipherKey\n " 0 0 "-s 512 -c aes-xts-plain64" 2>${ANSWER} || return 1

    # Encrypt selected partition or LV with credentials given
    DIALOG " $_LuksEncryptAdv " --infobox "\n$_PlsWaitBody\n " 0 0
    sleep 2

    echo $PASSWD | cryptsetup -q $(cat ${ANSWER}) luksFormat ${PARTITION} 2>$ERR
    check_for_error "encrypt ${PARTITION}" "$?"

    # Now open the encrypted partition or LV
    echo $PASSWD | cryptsetup open ${PARTITION} ${LUKS_ROOT_NAME} 2>$ERR
    check_for_error "open ${PARTITION} ${LUKS_ROOT_NAME}" "$?"
}

luks_show() {
    echo -e ${_LuksEncruptSucc} > /tmp/.devlist
    lsblk -o NAME,TYPE,FSTYPE,SIZE ${PARTITION} | grep "part\|crypt\|NAME\|TYPE\|FSTYPE\|SIZE" >> /tmp/.devlist
    DIALOG " $_LuksEncrypt " --textbox /tmp/.devlist 0 0
}

luks_menu() {
    LUKS_OPT=""

    DIALOG " $_PrepLUKS " --menu "\n$_LuksMenuBody$_LuksMenuBody2$_LuksMenuBody3\n " 0 0 4 \
      "$_LuksOpen" "cryptsetup open --type luks" \
      "$_LuksEncrypt" "cryptsetup -q luksFormat" \
      "$_LuksEncryptAdv" "cryptsetup -q -s -c luksFormat" \
      "$_Back" "-" 2>${ANSWER}

    case $(cat ${ANSWER}) in
        "$_LuksOpen") luks_open
            ;;
        "$_LuksEncrypt") luks_setup && luks_default && luks_show
            ;;
            "$_LuksEncryptAdv") luks_setup && luks_key_define && luks_show
            ;;
        *) return 0
            ;;
    esac
}

lvm_detect() {
    LVM_PV=$(pvs -o pv_name --noheading 2>/dev/null)
    LVM_VG=$(vgs -o vg_name --noheading 2>/dev/null)
    LVM_LV=$(lvs -o vg_name,lv_name --noheading --separator - 2>/dev/null)

    if [[ $LVM_LV != "" ]] && [[ $LVM_VG != "" ]] && [[ $LVM_PV != "" ]]; then
        DIALOG " $_PrepLVM " --infobox "\n$_LvmDetBody\n " 0 0
        modprobe dm-mod 2>$ERR
        check_for_error "modprobe dm-mod" "$?"
        vgscan >/dev/null 2>&1
        vgchange -ay >/dev/null 2>&1
    fi
}

lvm_show_vg() {
    VG_LIST=""
    vg_list=$(lvs --noheadings | awk '{print $2}' | uniq)

    for i in ${vg_list}; do
        VG_LIST="${VG_LIST} ${i} $(vgdisplay ${i} | grep -i "vg size" | awk '{print $3$4}')"
    done
}

# Create Volume Group and Logical Volumes
lvm_create() {
    # Find LVM appropriate partitions.
    INCLUDE_PART='part\|crypt'
    umount_partitions
    find_partitions
    # Amend partition(s) found for use in check list
    PARTITIONS=$(echo $PARTITIONS | sed 's/M\|G\|T/& off/g')

    # Name the Volume Group
    DIALOG " $_LvmCreateVG " --inputbox "\n$_LvmNameVgBody\n " 0 0 "" 2>${ANSWER} || return 0
    LVM_VG=$(cat ${ANSWER})

    # Loop while the Volume Group name starts with a "/", is blank, has spaces, or is already being used
    while [[ ${LVM_VG:0:1} == "/" ]] || [[ ${#LVM_VG} -eq 0 ]] || [[ $LVM_VG =~ \ |\' ]] || [[ $(lsblk | grep ${LVM_VG}) != "" ]]; do
        DIALOG " $_ErrTitle " --msgbox "\n$_LvmNameVgErr\n " 0 0
        DIALOG " $_LvmCreateVG " --inputbox "\n$_LvmNameVgBody\n " 0 0 "" 2>${ANSWER} || return 0
        LVM_VG=$(cat ${ANSWER})
    done

    # Select the partition(s) for the Volume Group
    DIALOG " $_LvmCreateVG " --checklist "\n$_LvmPvSelBody\n\n$_UseSpaceBar\n " 0 0 12 ${PARTITIONS} 2>${ANSWER} || return 0
    [[ $(cat ${ANSWER}) != "" ]] && VG_PARTS=$(cat ${ANSWER}) || return 0

    # Once all the partitions have been selected, show user. On confirmation, use it/them in 'vgcreate' command.
    # Also determine the size of the VG, to use for creating LVs for it.
    DIALOG " $_LvmCreateVG " --yesno "\n$_LvmPvConfBody1${LVM_VG} $_LvmPvConfBody2${VG_PARTS}\n " 0 0

    if [[ $? -eq 0 ]]; then
        DIALOG " $_LvmCreateVG " --infobox "\n$_LvmPvActBody1${LVM_VG}.$_PlsWaitBody\n " 0 0
        sleep 1
        vgcreate -f ${LVM_VG} ${VG_PARTS} >/dev/null 2>$ERR
        check_for_error "vgcreate -f ${LVM_VG} ${VG_PARTS}" "$?"

        # Once created, get size and size type for display and later number-crunching for lv creation
        VG_SIZE=$(vgdisplay $LVM_VG | grep 'VG Size' | awk '{print $3}' | sed 's/\..*//')
        VG_SIZE_TYPE=$(vgdisplay $LVM_VG | grep 'VG Size' | awk '{print $4}')

        # Convert the VG size into GB and MB. These variables are used to keep tabs on space available and remaining
        [[ ${VG_SIZE_TYPE:0:1} == "G" ]] && LVM_VG_MB=$(( VG_SIZE * 1000 )) || LVM_VG_MB=$VG_SIZE

        DIALOG " $_LvmCreateVG " --msgbox "\n$_LvmPvDoneBody1 '${LVM_VG}' $_LvmPvDoneBody2 (${VG_SIZE} ${VG_SIZE_TYPE}).\n " 0 0 || return 0
    fi

    #
    # Once VG created, create Logical Volumes
    #

    # Specify number of Logical volumes to create.
    DIALOG " $_LvmCreateVG " --radiolist "\n$_LvmLvNumBody1 ${LVM_VG}. $_LvmLvNumBody2\n " 0 0 9 \
      "1" "-" off "2" "-" off "3" "-" off "4" "-" off "5" "-" off "6" "-" off "7" "-" off "8" "-" off "9" "-" off 2>${ANSWER}

    [[ $(cat ${ANSWER}) == "" ]] && lvm_menu || NUMBER_LOGICAL_VOLUMES=$(cat ${ANSWER})

    # Loop while the number of LVs is greater than 1. This is because the size of the last LV is automatic.
    while [[ $NUMBER_LOGICAL_VOLUMES -gt 1 ]]; do
        DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "\n$_LvmLvNameBody1\n " 0 0 "lvol" 2>${ANSWER} || return 0
        LVM_LV_NAME=$(cat ${ANSWER})

        # Loop if preceeded with a "/", if nothing is entered, if there is a space, or if that name already exists.
        while [[ ${LVM_LV_NAME:0:1} == "/" ]] || [[ ${#LVM_LV_NAME} -eq 0 ]] || [[ ${LVM_LV_NAME} =~ \ |\' ]] || [[ $(lsblk | grep ${LVM_LV_NAME}) != "" ]]; do
            DIALOG " $_ErrTitle " --msgbox "\n$_LvmLvNameErrBody\n " 0 0
            DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "\n$_LvmLvNameBody1\n " 0 0 "lvol" 2>${ANSWER} || return 0
            LVM_LV_NAME=$(cat ${ANSWER})
        done

        DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "\n${LVM_VG}: ${VG_SIZE}${VG_SIZE_TYPE} (${LVM_VG_MB}MB \
          $_LvmLvSizeBody1).$_LvmLvSizeBody2\n " 0 0 "" 2>${ANSWER} || return 0
        LVM_LV_SIZE=$(cat ${ANSWER})
        check_lv_size

        # Loop while an invalid value is entered.
        while [[ $LV_SIZE_INVALID -eq 1 ]]; do
            DIALOG " $_ErrTitle " --msgbox "\n$_LvmLvSizeErrBody\n " 0 0
            DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "\n${LVM_VG}: ${VG_SIZE}${VG_SIZE_TYPE} \
              (${LVM_VG_MB}MB $_LvmLvSizeBody1).$_LvmLvSizeBody2\n " 0 0 "" 2>${ANSWER} || return 0
            LVM_LV_SIZE=$(cat ${ANSWER})
            check_lv_size
        done

        # Create the LV
        lvcreate -L ${LVM_LV_SIZE} ${LVM_VG} -n ${LVM_LV_NAME} 2>$ERR
        check_for_error "lvcreate -L ${LVM_LV_SIZE} ${LVM_VG} -n ${LVM_LV_NAME}" "$?"
        DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --msgbox "\n$_Done\n\nLV ${LVM_LV_NAME} (${LVM_LV_SIZE}) $_LvmPvDoneBody2.\n " 0 0
        NUMBER_LOGICAL_VOLUMES=$(( NUMBER_LOGICAL_VOLUMES - 1 ))
    done

    # Now the final LV. Size is automatic.
    DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "\n$_LvmLvNameBody1 $_LvmLvNameBody2 (${LVM_VG_MB}MB).\n " 0 0 "lvol" 2>${ANSWER} || return 0
    LVM_LV_NAME=$(cat ${ANSWER})
     
    # Loop if preceeded with a "/", if nothing is entered, if there is a space, or if that name already exists.
    while [[ ${LVM_LV_NAME:0:1} == "/" ]] || [[ ${#LVM_LV_NAME} -eq 0 ]] || [[ ${LVM_LV_NAME} =~ \ |\' ]] || [[ $(lsblk | grep ${LVM_LV_NAME}) != "" ]]; do
        DIALOG " $_ErrTitle " --msgbox "\n$_LvmLvNameErrBody\n " 0 0
        DIALOG " $_LvmCreateVG (LV:$NUMBER_LOGICAL_VOLUMES) " --inputbox "\n$_LvmLvNameBody1 $_LvmLvNameBody2 (${LVM_VG_MB}MB).\n " 0 0 "lvol" 2>${ANSWER} || return 0
        LVM_LV_NAME=$(cat ${ANSWER})
    done

    # Create the final LV
    lvcreate -l +100%FREE ${LVM_VG} -n ${LVM_LV_NAME} 2>$ERR
    check_for_error "lvcreate -l +100%FREE ${LVM_VG} -n ${LVM_LV_NAME}" "$?"
    NUMBER_LOGICAL_VOLUMES=$(( NUMBER_LOGICAL_VOLUMES - 1 ))
    LVM=1
    DIALOG " $_LvmCreateVG " --yesno "\n$_LvmCompBody\n " 0 0 && show_devices || return 0
}

check_lv_size() {
    LV_SIZE_INVALID=0
    chars=0

    # Check to see if anything was actually entered and if first character is '0'
    ([[ ${#LVM_LV_SIZE} -eq 0 ]] || [[ ${LVM_LV_SIZE:0:1} -eq "0" ]]) && LV_SIZE_INVALID=1

    # If not invalid so far, check for non numberic characters other than the last character
    if [[ $LV_SIZE_INVALID -eq 0 ]]; then
        while [[ $chars -lt $(( ${#LVM_LV_SIZE} - 1 )) ]]; do
            [[ ${LVM_LV_SIZE:chars:1} != [0-9] ]] && LV_SIZE_INVALID=1 && return 0;
            chars=$(( chars + 1 ))
        done
    fi

    # If not invalid so far, check that last character is a M/m or G/g
    if [[ $LV_SIZE_INVALID -eq 0 ]]; then
        LV_SIZE_TYPE=$(echo ${LVM_LV_SIZE:$(( ${#LVM_LV_SIZE} - 1 )):1})

        case $LV_SIZE_TYPE in
            "m"|"M"|"g"|"G") LV_SIZE_INVALID=0 ;;
            *) LV_SIZE_INVALID=1 ;;
        esac

    fi

    # If not invalid so far, check whether the value is greater than or equal to the LV remaining Size.
    # If not, convert into MB for VG space remaining.
    if [[ ${LV_SIZE_INVALID} -eq 0 ]]; then
        case ${LV_SIZE_TYPE} in
            "G"|"g")
                if [[ $(( $(echo ${LVM_LV_SIZE:0:$(( ${#LVM_LV_SIZE} - 1 ))}) * 1000 )) -ge ${LVM_VG_MB} ]]; then
                    LV_SIZE_INVALID=1
                else
                    LVM_VG_MB=$(( LVM_VG_MB - $(( $(echo ${LVM_LV_SIZE:0:$(( ${#LVM_LV_SIZE} - 1 ))}) * 1000 )) ))
                fi
                ;;
            "M"|"m")
                if [[ $(echo ${LVM_LV_SIZE:0:$(( ${#LVM_LV_SIZE} - 1 ))}) -ge ${LVM_VG_MB} ]]; then
                    LV_SIZE_INVALID=1
                else
                    LVM_VG_MB=$(( LVM_VG_MB - $(echo ${LVM_LV_SIZE:0:$(( ${#LVM_LV_SIZE} - 1 ))}) ))
                fi
                ;;
            *) LV_SIZE_INVALID=1
                ;;
        esac

    fi
}

lvm_del_vg() {
    # Generate list of VGs for selection
    lvm_show_vg

    # If no VGs, no point in continuing
    if [[ $VG_LIST == "" ]]; then
        DIALOG " $_ErrTitle " --msgbox "\n$_LvmVGErr\n " 0 0
        return 0
    fi

    # Select VG
    DIALOG " $_PrepLVM " --menu "\n$_LvmSelVGBody\n " 0 0 5 ${VG_LIST} 2>${ANSWER} || return 0

    # Ask for confirmation
    DIALOG " $_LvmDelVG " --yesno "\n$_LvmDelQ\n " 0 0

    # if confirmation given, delete
    if [[ $? -eq 0 ]]; then
        check_for_error "delete lvm-VG $(cat ${ANSWER})"
        vgremove -f $(cat ${ANSWER}) >/dev/null 2>&1
    fi
}

lvm_del_all() {
    LVM_PV=$(pvs -o pv_name --noheading 2>/dev/null)
    LVM_VG=$(vgs -o vg_name --noheading 2>/dev/null)
    LVM_LV=$(lvs -o vg_name,lv_name --noheading --separator - 2>/dev/null)

    # Ask for confirmation
    DIALOG " $_LvmDelLV " --yesno "\n$_LvmDelQ\n " 0 0

    # if confirmation given, delete
    if [[ $? -eq 0 ]]; then
        for i in ${LVM_LV}; do
            check_for_error "remove LV ${i}"
            lvremove -f /dev/mapper/${i} >/dev/null 2>&1
        done

        for i in ${LVM_VG}; do
            check_for_error "remove VG ${i}"
            vgremove -f ${i} >/dev/null 2>&1
        done

        for i in ${LV_PV}; do
            check_for_error "remove LV-PV ${i}"
            pvremove -f ${i} >/dev/null 2>&1
        done
    fi
}

lvm_menu() {
    DIALOG " $_PrepLVM $_PrepLVM2 " --infobox "\n$_PlsWaitBody\n " 0 0
    sleep 1
    lvm_detect

    DIALOG " $_PrepLVM $_PrepLVM2 " --menu "\n$_LvmMenu\n " 0 0 4 \
      "$_LvmCreateVG" "vgcreate -f, lvcreate -L -n" \
      "$_LvmDelVG" "vgremove -f" \
      "$_LvMDelAll" "lvrmeove, vgremove, pvremove -f" \
      "$_Back" "-" 2>${ANSWER}

    case $(cat ${ANSWER}) in
        "$_LvmCreateVG") lvm_create ;;
        "$_LvmDelVG") lvm_del_vg ;;
        "$_LvMDelAll") lvm_del_all ;;
        *) return 0 ;;
    esac
}

mount_partitions() {
    # Warn users that they CAN mount partitions without formatting them!
    DIALOG " $_PrepMntPart " --msgbox "\n$_WarnMount1 '$_FSSkip' $_WarnMount2\n " 0 0

    # LVM Detection. If detected, activate.
    lvm_detect

    # Ensure partitions are unmounted (i.e. where mounted previously), and then list available partitions
    INCLUDE_PART='part\|lvm\|crypt'
    umount_partitions
    find_partitions
    # Filter out partitions that have already been mounted and partitions that just contain crypt device
    list_mounted > /tmp/.ignore_part
    list_containing_crypt >> /tmp/.ignore_part
    check_for_error "ignore crypted: $(list_containing_crypt)"

    for part in $(cat /tmp/.ignore_part); do
        delete_partition_in_list $part
    done

    # Identify and mount root
    PARTITION="${ARGS[mount.root]}"
    if [[ -z "$PARTITION" ]]; then
        PARTITION=$(inifile "mount.root")
        if [[ -z "$PARTITION" ]]; then
            DIALOG " $_PrepMntPart " --menu "\n$_SelRootBody\n " 0 0 12 ${PARTITIONS} 2>${ANSWER} || return 0
            PARTITION=$(cat ${ANSWER})
        fi
    fi
    ROOT_PART=${PARTITION}

    # Format with FS (or skip) -> # Make the directory and mount. Also identify LUKS and/or LVM
    select_filesystem && mount_current_partition || return 0

    ini mount.root "${PARTITION}"
    delete_partition_in_list "${ROOT_PART}"

    # Identify and create swap, if applicable
    make_swap

    # Extra Step for VFAT UEFI Partition. This cannot be in an LVM container.
    if [[ $SYSTEM == "UEFI" ]]; then
        if DIALOG " $_PrepMntPart " --menu "\n$_SelUefiBody\n " 0 0 12 ${PARTITIONS} 2>${ANSWER}; then
            PARTITION=$(cat ${ANSWER})
            UEFI_PART=${PARTITION}

            # If it is already a fat/vfat partition...
            if [[ $(fsck -N $PARTITION | grep fat) ]]; then
                DIALOG " $_PrepMntPart " --yesno "\n$_FormUefiBody $PARTITION $_FormUefiBody2\n " 0 0 && {
                    mkfs.vfat -F32 ${PARTITION} >/dev/null 2>$ERR
                    check_for_error "mkfs.vfat -F32 ${PARTITION}" "$?"
                } # || return 0
            else
                mkfs.vfat -F32 ${PARTITION} >/dev/null 2>$ERR
                check_for_error "mkfs.vfat -F32 ${PARTITION}" "$?"
            fi

            DIALOG " $_PrepMntPart " --radiolist "\n$_MntUefiBody\n "  0 0 2 \
            "/boot" "" on \
            "/boot/efi" "" off 2>${ANSWER}

            if [[ $(cat ${ANSWER}) != "" ]]; then
                UEFI_MOUNT=$(cat ${ANSWER})
                mkdir -p ${MOUNTPOINT}${UEFI_MOUNT} 2>$ERR
                check_for_error "create ${MOUNTPOINT}${UEFI_MOUNT}" $?
                mount ${PARTITION} ${MOUNTPOINT}${UEFI_MOUNT} 2>$ERR
                check_for_error "mount ${PARTITION} ${MOUNTPOINT}${UEFI_MOUNT}" $?
                if confirm_mount ${MOUNTPOINT}${UEFI_MOUNT}; then
                    ini mount.efi "${UEFI_MOUNT}"
                    delete_partition_in_list "$PARTITION"
                fi
            fi
        fi
    fi

    # All other partitions
    while [[ $NUMBER_PARTITIONS > 0 ]]; do
        DIALOG " $_PrepMntPart " --menu "\n$_ExtPartBody\n " 0 0 12 "$_Done" $"-" ${PARTITIONS} 2>${ANSWER} || return 0
        PARTITION=$(cat ${ANSWER})

        if [[ $PARTITION == $_Done ]]; then
            return 0;
        else
            MOUNT=""
            select_filesystem

            # Ask user for mountpoint. Don't give /boot as an example for UEFI systems!
            [[ $SYSTEM == "UEFI" ]] && MNT_EXAMPLES="/home\n/var" || MNT_EXAMPLES="/boot\n/home\n/var"
            DIALOG " $_PrepMntPart $PARTITON " --inputbox "\n$_ExtPartBody1$MNT_EXAMPLES\n " 0 0 "/" 2>${ANSWER} || return 0
            MOUNT=$(cat ${ANSWER})

            # loop while the mountpoint specified is incorrect (is only '/', is blank, or has spaces).
            while [[ ${MOUNT:0:1} != "/" ]] || [[ ${#MOUNT} -le 1 ]] || [[ $MOUNT =~ \ |\' ]]; do
                # Warn user about naming convention
                DIALOG " $_ErrTitle " --msgbox "\n$_ExtErrBody\n " 0 0
                # Ask user for mountpoint again
                DIALOG " $_PrepMntPart $PARTITON " --inputbox "\n$_ExtPartBody1$MNT_EXAMPLES\n " 0 0 "/" 2>${ANSWER} || return 0
                MOUNT=$(cat ${ANSWER})
            done

            # Create directory and mount.
            mount_current_partition
            delete_partition_in_list "$PARTITION"

            # Determine if a seperate /boot is used. 0 = no seperate boot, 1 = seperate non-lvm boot,
            # 2 = seperate lvm boot. For Grub configuration
            if  [[ $MOUNT == "/boot" ]]; then
                [[ $(lsblk -lno TYPE ${PARTITION} | grep "lvm") != "" ]] && LVM_SEP_BOOT=2 || LVM_SEP_BOOT=1
            fi
        fi
    done
}
