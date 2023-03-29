#!/usr/bin/env bash
set -Eeuo pipefail

# ----------------------------------------------------------------------------------------------------
# ASSET BASE URL
# ----------------------------------------------------------------------------------------------------

ASSET_BASE_URL="${1:-https://raw.githubusercontent.com/murkl/arch-distro/main/assets}"

# ----------------------------------------------------------------------------------------------------
# LOGGING
# ----------------------------------------------------------------------------------------------------

LOG_FILE="/tmp/arch-install.log"

# ----------------------------------------------------------------------------------------------------
# SETUP VARIABLES
# ----------------------------------------------------------------------------------------------------

ARCH_USERNAME=""
ARCH_HOSTNAME=""
ARCH_PASSWORD=""
ARCH_DISK=""
ARCH_BOOT_PARTITION=""
ARCH_ROOT_PARTITION=""
ARCH_ENCRYPTION_ENABLED=""
ARCH_SWAP_SIZE=""
ARCH_LANGUAGE=""
ARCH_TIMEZONE=""
ARCH_LOCALE_LANG=""
ARCH_LOCALE_GEN_LIST=()
ARCH_VCONSOLE_KEYMAP=""
ARCH_VCONSOLE_FONT=""
ARCH_KEYBOARD_LAYOUT=""
ARCH_KEYBOARD_VARIANT=""
ARCH_DRIVER=""

# ----------------------------------------------------------------------------------------------------
# TUI VARIABLES
# ----------------------------------------------------------------------------------------------------

TUI_TITLE="Arch Linux Installation"
TUI_WIDTH="80"
TUI_HEIGHT="20"
TUI_POSITION=""

# ----------------------------------------------------------------------------------------------------
# WHIPTAIL VARIABLES
# ----------------------------------------------------------------------------------------------------

PROGRESS_COUNT=0
PROGRESS_TOTAL=36

# ----------------------------------------------------------------------------------------------------
# PRINT FUNCTIONS
# ----------------------------------------------------------------------------------------------------

print_menu_entry() {
    local key="$1"
    local val="$2" && val=$(echo "$val" | xargs) # Trim spaces
    local spaces=""
    for ((i = ${#key}; i < 12; i++)); do spaces="${spaces} "; done
    [ -z "$val" ] && val='?' # Set default value
    echo "${key} ${spaces} ->  $val"
}

print_whiptail_info() {

    local info="$1"

    # Print title for logging (only stderr will be logged)
    echo "#########################################################" >&2
    echo ">>> ${info}" >&2
    echo "#########################################################" >&2

    # Print percent & info for whiptail (uses descriptor 3 as stdin)
    ((PROGRESS_COUNT += 1)) && echo -e "XXX\n$((PROGRESS_COUNT * 100 / PROGRESS_TOTAL))\n${info}...\nXXX" >&3
}

# ----------------------------------------------------------------------------------------------------
# CHECK CONFIG
# ----------------------------------------------------------------------------------------------------

check_config() {
    [ -z "${ARCH_LANGUAGE}" ] && TUI_POSITION="language" && return 1
    [ -z "${ARCH_TIMEZONE}" ] && TUI_POSITION="language" && return 1
    [ -z "${ARCH_LOCALE_LANG}" ] && TUI_POSITION="language" && return 1
    [ -z "${ARCH_LOCALE_GEN_LIST[*]}" ] && TUI_POSITION="language" && return 1
    [ -z "${ARCH_VCONSOLE_KEYMAP}" ] && TUI_POSITION="language" && return 1
    [ -z "${ARCH_VCONSOLE_FONT}" ] && TUI_POSITION="language" && return 1
    [ -z "${ARCH_KEYBOARD_LAYOUT}" ] && TUI_POSITION="language" && return 1
    [ -z "${ARCH_KEYBOARD_VARIANT}" ] && TUI_POSITION="language" && return 1
    [ -z "${ARCH_HOSTNAME}" ] && TUI_POSITION="hostname" && return 1
    [ -z "${ARCH_USERNAME}" ] && TUI_POSITION="user" && return 1
    [ -z "${ARCH_PASSWORD}" ] && TUI_POSITION="password" && return 1
    [ -z "${ARCH_DISK}" ] && TUI_POSITION="disk" && return 1
    [ -z "${ARCH_BOOT_PARTITION}" ] && TUI_POSITION="disk" && return 1
    [ -z "${ARCH_ROOT_PARTITION}" ] && TUI_POSITION="disk" && return 1
    [ -z "${ARCH_ENCRYPTION_ENABLED}" ] && TUI_POSITION="encrypt" && return 1
    [ -z "${ARCH_SWAP_SIZE}" ] && TUI_POSITION="swap" && return 1
    [ -z "${ARCH_DRIVER}" ] && TUI_POSITION="driver" && return 1
    TUI_POSITION="install"
}

# ----------------------------------------------------------------------------------------------------
# SOURCE CONFIG
# ----------------------------------------------------------------------------------------------------

# shellcheck disable=SC1091
[ -f ./installer.conf ] && source ./installer.conf

# ----------------------------------------------------------------------------------------------------
# SHOW MENU
# ----------------------------------------------------------------------------------------------------

while (true); do

    # Create TUI menu entries
    menu_entry_array=()
    menu_entry_array+=("language") && menu_entry_array+=("$(print_menu_entry "Language" "${ARCH_LANGUAGE}")")
    menu_entry_array+=("hostname") && menu_entry_array+=("$(print_menu_entry "Hostname" "${ARCH_HOSTNAME}")")
    menu_entry_array+=("user") && menu_entry_array+=("$(print_menu_entry "User" "${ARCH_USERNAME}")")
    menu_entry_array+=("password") && menu_entry_array+=("$(print_menu_entry "Password" "$([ -n "$ARCH_PASSWORD" ] && echo "******")")")
    menu_entry_array+=("disk") && menu_entry_array+=("$(print_menu_entry "Disk" "${ARCH_DISK}")")
    menu_entry_array+=("encrypt") && menu_entry_array+=("$(print_menu_entry "Encryption" "${ARCH_ENCRYPTION_ENABLED}")")
    menu_entry_array+=("swap") && menu_entry_array+=("$(print_menu_entry "Swap" "$([ -n "$ARCH_SWAP_SIZE" ] && { [ "$ARCH_SWAP_SIZE" != "0" ] && echo "${ARCH_SWAP_SIZE} GB" || echo "disabled"; })")")
    menu_entry_array+=("driver") && menu_entry_array+=("$(print_menu_entry "Driver" "${ARCH_DRIVER}")")
    menu_entry_array+=("") && menu_entry_array+=("") # Empty entry
    menu_entry_array+=("install") && menu_entry_array+=("> Start Installation")

    # Set menu position
    check_config || true

    # Open TUI menu
    menu_selection=$(whiptail --title "$TUI_TITLE" --menu "\n" --ok-button "Ok" --cancel-button "Exit" --notags --default-item "$TUI_POSITION" "$TUI_HEIGHT" "$TUI_WIDTH" "$(((${#menu_entry_array[@]} / 2) + (${#menu_entry_array[@]} % 2)))" "${menu_entry_array[@]}" 3>&1 1>&2 2>&3) || exit

    case "${menu_selection}" in

    "language")
        ARCH_LANGUAGE=$(whiptail --title "$TUI_TITLE" --menu "\nChoose Setup Language" --nocancel --notags "$TUI_HEIGHT" "$TUI_WIDTH" 2 "english" "English" "german" "German" 3>&1 1>&2 2>&3)
        if [ "$ARCH_LANGUAGE" = "english" ]; then
            ARCH_TIMEZONE="Europe/Berlin"
            ARCH_LOCALE_LANG="en_US.UTF-8"
            ARCH_LOCALE_GEN_LIST=("en_US.UTF-8" "UTF-8")
            ARCH_VCONSOLE_KEYMAP="en-latin1-nodeadkeys"
            ARCH_VCONSOLE_FONT="eurlatgr"
            ARCH_KEYBOARD_LAYOUT="en"
            ARCH_KEYBOARD_VARIANT="nodeadkeys"
        fi
        if [ "$ARCH_LANGUAGE" = "german" ]; then
            ARCH_TIMEZONE="Europe/Berlin"
            ARCH_LOCALE_LANG="de_DE.UTF-8"
            ARCH_LOCALE_GEN_LIST=("de_DE.UTF-8 UTF-8" "de_DE ISO-8859-1" "de_DE@euro ISO-8859-15" "en_US.UTF-8 UTF-8")
            ARCH_VCONSOLE_KEYMAP="de-latin1-nodeadkeys"
            ARCH_VCONSOLE_FONT="eurlatgr"
            ARCH_KEYBOARD_LAYOUT="de"
            ARCH_KEYBOARD_VARIANT="nodeadkeys"
        fi
        ;;

    "hostname")
        ARCH_HOSTNAME=$(whiptail --title "$TUI_TITLE" --inputbox "\nEnter Hostname" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$ARCH_HOSTNAME" 3>&1 1>&2 2>&3)
        [ -z "$ARCH_HOSTNAME" ] && whiptail --title "$TUI_TITLE" --msgbox "Error: Hostname is null" "$TUI_HEIGHT" "$TUI_WIDTH" && continue
        ;;

    "user")
        ARCH_USERNAME=$(whiptail --title "$TUI_TITLE" --inputbox "\nEnter Username" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$ARCH_USERNAME" 3>&1 1>&2 2>&3)
        [ -z "$ARCH_USERNAME" ] && whiptail --title "$TUI_TITLE" --msgbox "Error: Username is null" "$TUI_HEIGHT" "$TUI_WIDTH" && continue
        ;;

    "password")
        ARCH_PASSWORD=$(whiptail --title "$TUI_TITLE" --passwordbox "\nEnter Password" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" 3>&1 1>&2 2>&3)
        [ -z "$ARCH_PASSWORD" ] && whiptail --title "$TUI_TITLE" --msgbox "Error: Password is null" "$TUI_HEIGHT" "$TUI_WIDTH" && continue
        password_check=$(whiptail --title "$TUI_TITLE" --passwordbox "\nEnter Password (again)" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" 3>&1 1>&2 2>&3)
        [ "$ARCH_PASSWORD" != "$password_check" ] && ARCH_PASSWORD="" && whiptail --title "$TUI_TITLE" --msgbox "Error: Password not identical" "$TUI_HEIGHT" "$TUI_WIDTH" && continue
        ;;

    "disk")
        disk_array=()
        while read -r disk_line; do
            disk_array+=("/dev/$disk_line")
            disk_array+=(" ($(lsblk -d -n -o SIZE /dev/"$disk_line"))")
        done < <(lsblk -I 8,259,254 -d -o KNAME -n)

        # If no disk found
        [ "${#disk_array[@]}" = "0" ] && whiptail --title "$TUI_TITLE" --msgbox "No Disk found" "$TUI_HEIGHT" "$TUI_WIDTH" && continue

        # Select Disk
        ARCH_DISK=$(whiptail --title "$TUI_TITLE" --menu "\nChoose Installation Disk" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "${#disk_array[@]}" "${disk_array[@]}" 3>&1 1>&2 2>&3)
        [[ "$ARCH_DISK" = "/dev/nvm"* ]] && ARCH_BOOT_PARTITION="${ARCH_DISK}p1" || ARCH_BOOT_PARTITION="${ARCH_DISK}1"
        [[ "$ARCH_DISK" = "/dev/nvm"* ]] && ARCH_ROOT_PARTITION="${ARCH_DISK}p2" || ARCH_ROOT_PARTITION="${ARCH_DISK}2"
        ;;

    "encrypt")
        ARCH_ENCRYPTION_ENABLED="false" && whiptail --title "$TUI_TITLE" --yesno "Enable Disk Encryption?" "$TUI_HEIGHT" "$TUI_WIDTH" && ARCH_ENCRYPTION_ENABLED="true"
        ;;

    "swap")
        ARCH_SWAP_SIZE="$(($(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 + 1))"
        ARCH_SWAP_SIZE=$(whiptail --title "$TUI_TITLE" --inputbox "\nEnter Swap Size in GB (0 = disable)" --nocancel "$TUI_HEIGHT" "$TUI_WIDTH" "$ARCH_SWAP_SIZE" 3>&1 1>&2 2>&3) || continue
        [ -z "$ARCH_SWAP_SIZE" ] && ARCH_SWAP_SIZE="0"
        ;;

    "driver")
        driver_list=()
        driver_list+=("none" "None")
        driver_list+=("intel-hd" "Intel HD")
        driver_list+=("nvidia" "NVIDIA")
        driver_list+=("nvidia-optimus" "NVIDIA Optimus")
        driver_list+=("amd" "AMD")
        driver_list+=("amd-legacy" "AMD Legacy")
        ARCH_DRIVER=$(whiptail --title "$TUI_TITLE" --menu "\nSelect Graphics Driver (experimental)" --nocancel --notags "$TUI_HEIGHT" "$TUI_WIDTH" "$(((${#driver_list[@]} / 2) + (${#driver_list[@]} % 2)))" "${driver_list[@]}" 3>&1 1>&2 2>&3)
        ;;

    "install")
        check_config || continue
        whiptail --title "$TUI_TITLE" --yesno "Start Arch Linux Installation?\n\nAll data on ${ARCH_DISK} will be DELETED!" "$TUI_HEIGHT" "$TUI_WIDTH" || continue
        break # Break loop and continue installation
        ;;

    *) continue ;; # Do nothing

    esac
done

# ----------------------------------------------------------------------------------------------------
# SET RESULT TRAP
# ----------------------------------------------------------------------------------------------------

trap_result() {
    if [ -f /tmp/arch-install.success ]; then
        rm -f /tmp/arch-install.success
        whiptail --title "$TUI_TITLE" --yesno "Arch Installation successful.\n\nReboot now?" --yes-button "Reboot" --no-button "Exit" "$TUI_HEIGHT" "$TUI_WIDTH" && reboot
    else
        whiptail --title "Arch Installation failed" --msgbox "$(cat $LOG_FILE)" --scrolltext 30 90
    fi
}

trap trap_result EXIT

# //////////////////////////////////  START ARCH LINUX INSTALLATION //////////////////////////////////
(
    # Print nothing from stdin & stderr to console
    exec 3>&1 4>&2     # Saves file descriptors (new stdin: &3 new stderr: &4)
    exec 1>/dev/null   # Log stdin to /dev/null
    exec 2>"$LOG_FILE" # Log stderr to logfile

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Checkup"
    # ----------------------------------------------------------------------------------------------------

    [ ! -d /sys/firmware/efi ] && echo "ERROR: BIOS not supported! Please set your boot mode to UEFI." >&2 && exit 1
    [ "$(cat /proc/sys/kernel/hostname)" != "archiso" ] && echo "ERROR: You must execute the Installer from Arch ISO!" >&2 && exit 1

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Waiting for Reflector from Arch ISO"
    # ----------------------------------------------------------------------------------------------------

    while timeout 180 tail --pid=$(pgrep reflector) -f /dev/null &>/dev/null; do sleep 1; done
    pgrep reflector &>/dev/null && echo "ERROR: Reflector timeout after 180 seconds" >&2 && exit 1

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Prepare Installation"
    # ----------------------------------------------------------------------------------------------------

    # Sync clock
    timedatectl set-ntp true

    # Make sure everything is unmounted before start install
    swapoff -a &>/dev/null || true
    umount -A -R /mnt &>/dev/null || true
    cryptsetup close cryptroot &>/dev/null || true
    vgchange -an || true

    # Temporarily disable ECN (prevent traffic problems with some old routers)
    sysctl net.ipv4.tcp_ecn=0

    # Update & reinit keyring
    pacman -Sy --noconfirm archlinux-keyring

    # Detect microcode
    ARCH_MICROCODE=""
    grep -E "GenuineIntel" <<<"$(lscpu)" && ARCH_MICROCODE="intel-ucode"
    grep -E "AuthenticAMD" <<<"$(lscpu)" && ARCH_MICROCODE="amd-ucode"

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Wipe & Create Partitions (${ARCH_DISK})"
    # ----------------------------------------------------------------------------------------------------

    # Wipe all partitions
    wipefs -af "$ARCH_DISK"

    # Create new GPT partition table
    sgdisk -o "$ARCH_DISK"

    # Create partition /boot efi partition: 1 GiB
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot "$ARCH_DISK"

    # Create partition / partition: Rest of space
    sgdisk -n 2:0:0 -t 2:8300 -c 2:root "$ARCH_DISK"

    # Reload partition table
    partprobe "$ARCH_DISK"

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Enable Disk Encryption"
    # ----------------------------------------------------------------------------------------------------

    if [ "$ARCH_ENCRYPTION_ENABLED" = "true" ]; then
        echo -n "$ARCH_PASSWORD" | cryptsetup luksFormat "$ARCH_ROOT_PARTITION"
        echo -n "$ARCH_PASSWORD" | cryptsetup open "$ARCH_ROOT_PARTITION" cryptroot
    else
        echo "> Skipped"
    fi

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Format Disk"
    # ----------------------------------------------------------------------------------------------------

    mkfs.fat -F 32 -n BOOT "$ARCH_BOOT_PARTITION"
    [ "$ARCH_ENCRYPTION_ENABLED" = "true" ] && mkfs.ext4 -F -L ROOT /dev/mapper/cryptroot
    [ "$ARCH_ENCRYPTION_ENABLED" = "false" ] && mkfs.ext4 -F -L ROOT "$ARCH_ROOT_PARTITION"

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Mount Disk"
    # ----------------------------------------------------------------------------------------------------

    [ "$ARCH_ENCRYPTION_ENABLED" = "true" ] && mount -v /dev/mapper/cryptroot /mnt
    [ "$ARCH_ENCRYPTION_ENABLED" = "false" ] && mount -v "$ARCH_ROOT_PARTITION" /mnt
    mkdir -p /mnt/boot
    mount -v "$ARCH_BOOT_PARTITION" /mnt/boot

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Pacstrap System Packages (This may take a while)"
    # ----------------------------------------------------------------------------------------------------

    packages=()
    packages+=("base")
    packages+=("base-devel")
    packages+=("linux-lts")
    packages+=("linux-firmware")
    packages+=("networkmanager")
    packages+=("pacman-contrib")
    packages+=("reflector")
    packages+=("git")
    packages+=("nano")
    packages+=("bash-completion")
    packages+=("pkgfile")
    [ -n "$ARCH_MICROCODE" ] && packages+=("$ARCH_MICROCODE")

    # Install core and initialize an empty pacman keyring in the target
    pacstrap -K /mnt "${packages[@]}" "${ARCH_OPT_PACKAGE_LIST[@]}" --disable-download-timeout

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Configure Pacman & Reflector"
    # ----------------------------------------------------------------------------------------------------

    # Configure parrallel downloads, colors & multilib
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /mnt/etc/pacman.conf
    sed -i 's/^#Color/Color/' /mnt/etc/pacman.conf
    sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf
    arch-chroot /mnt pacman -Syy --noconfirm

    # Configure reflector service
    {
        echo "# Reflector config for the systemd service"
        echo "--save /etc/pacman.d/mirrorlist"
        echo "--protocol https"
        echo "--latest 10"
        echo "--sort rate"
    } >/mnt/etc/xdg/reflector/reflector.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Generate /etc/fstab"
    # ----------------------------------------------------------------------------------------------------

    genfstab -U /mnt >>/mnt/etc/fstab

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Create Swap"
    # ----------------------------------------------------------------------------------------------------

    if [ "$ARCH_SWAP_SIZE" != "0" ] && [ -n "$ARCH_SWAP_SIZE" ]; then
        dd if=/dev/zero of=/mnt/swapfile bs=1G count="$ARCH_SWAP_SIZE" status=progress
        chmod 600 /mnt/swapfile
        mkswap /mnt/swapfile
        swapon /mnt/swapfile
        echo "# Swapfile" >>/mnt/etc/fstab
        echo "/swapfile none swap defaults 0 0" >>/mnt/etc/fstab
    else
        echo "> Skipped"
    fi

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Timezone & System Clock"
    # ----------------------------------------------------------------------------------------------------

    arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$ARCH_TIMEZONE" /etc/localtime
    arch-chroot /mnt hwclock --systohc # Set hardware clock from system clock

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Set Console Keymap"
    # ----------------------------------------------------------------------------------------------------

    echo "KEYMAP=$ARCH_VCONSOLE_KEYMAP" >/mnt/etc/vconsole.conf
    echo "FONT=$ARCH_VCONSOLE_FONT" >>/mnt/etc/vconsole.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Generate Locale"
    # ----------------------------------------------------------------------------------------------------

    echo "LANG=$ARCH_LOCALE_LANG" >/mnt/etc/locale.conf
    for ((i = 0; i < ${#ARCH_LOCALE_GEN_LIST[@]}; i++)); do sed -i "s/^#${ARCH_LOCALE_GEN_LIST[$i]}/${ARCH_LOCALE_GEN_LIST[$i]}/g" "/mnt/etc/locale.gen"; done
    arch-chroot /mnt locale-gen

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Set Hostname (${ARCH_HOSTNAME})"
    # ----------------------------------------------------------------------------------------------------

    echo "$ARCH_HOSTNAME" >/mnt/etc/hostname

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Set /etc/hosts"
    # ----------------------------------------------------------------------------------------------------

    {
        echo '127.0.0.1    localhost'
        echo '::1          localhost'
    } >/mnt/etc/hosts

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Set /etc/environment"
    # ----------------------------------------------------------------------------------------------------

    {
        echo 'EDITOR=nano'
        echo 'VISUAL=nano'
    } >/mnt/etc/environment

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Create Initial Ramdisk"
    # ----------------------------------------------------------------------------------------------------

    [ "$ARCH_ENCRYPTION_ENABLED" = "true" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd autodetect modconf keyboard sd-vconsole block sd-encrypt filesystems resume fsck)/" /mnt/etc/mkinitcpio.conf
    [ "$ARCH_ENCRYPTION_ENABLED" = "false" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd autodetect modconf keyboard sd-vconsole block filesystems resume fsck)/" /mnt/etc/mkinitcpio.conf
    arch-chroot /mnt mkinitcpio -P

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install Bootloader (systemdboot)"
    # ----------------------------------------------------------------------------------------------------

    # Install systemdboot to /boot
    arch-chroot /mnt bootctl --esp-path=/boot install

    # Kernel args
    swap_device_uuid="$(findmnt -no UUID -T /mnt/swapfile)"
    swap_file_offset="$(filefrag -v /mnt/swapfile | awk '$1=="0:" {print substr($4, 1, length($4)-2)}')"
    if [ "$ARCH_ENCRYPTION_ENABLED" = "true" ]; then
        kernel_args="rd.luks.name=$(blkid -s UUID -o value "${ARCH_ROOT_PARTITION}")=cryptroot root=/dev/mapper/cryptroot rw init=/usr/lib/systemd/systemd nowatchdog quiet splash vt.global_cursor_default=0 resume=/dev/mapper/cryptroot resume_offset=${swap_file_offset}"
    else
        kernel_args="root=PARTUUID=$(lsblk -dno PARTUUID "${ARCH_ROOT_PARTITION}") rw init=/usr/lib/systemd/systemd nowatchdog quiet splash vt.global_cursor_default=0 resume=UUID=${swap_device_uuid} resume_offset=${swap_file_offset}"
    fi

    # Create Bootloader config
    {
        echo 'default arch.conf'
        echo 'console-mode max'
        echo 'timeout 0'
        echo 'editor yes'
    } >/mnt/boot/loader/loader.conf

    # Create arch default entry
    {
        echo 'title   Arch Linux'
        echo 'linux   /vmlinuz-linux-lts'
        [ -n "$ARCH_MICROCODE" ] && echo "initrd  /${ARCH_MICROCODE}.img"
        echo 'initrd  /initramfs-linux-lts.img'
        echo "options ${kernel_args}"
    } >/mnt/boot/loader/entries/arch.conf

    # Create arch fallback entry
    {
        echo 'title   Arch Linux (Fallback)'
        echo 'linux   /vmlinuz-linux-lts'
        [ -n "$ARCH_MICROCODE" ] && echo "initrd  /${ARCH_MICROCODE}.img"
        echo 'initrd  /initramfs-linux-lts-fallback.img'
        echo "options ${kernel_args}"
    } >/mnt/boot/loader/entries/arch-fallback.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Create User (${ARCH_USERNAME})"
    # ----------------------------------------------------------------------------------------------------

    # Create new user
    arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$ARCH_USERNAME"

    # Allow users in group wheel to use sudo
    sed -i 's^# %wheel ALL=(ALL:ALL) ALL^%wheel ALL=(ALL:ALL) ALL^g' /mnt/etc/sudoers

    # Add password feedback
    echo -e "\n## Enable sudo password feedback\nDefaults pwfeedback" >>/mnt/etc/sudoers

    # Change passwords
    printf "%s\n%s" "${ARCH_PASSWORD}" "${ARCH_PASSWORD}" | arch-chroot /mnt passwd
    printf "%s\n%s" "${ARCH_PASSWORD}" "${ARCH_PASSWORD}" | arch-chroot /mnt passwd "$ARCH_USERNAME"

    # Add sudo needs no password rights (only for installation)
    sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /mnt/etc/sudoers

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Enable Essential Services"
    # ----------------------------------------------------------------------------------------------------

    arch-chroot /mnt systemctl enable NetworkManager            # Network Manager
    arch-chroot /mnt systemctl enable systemd-timesyncd.service # Sync time from internet after boot
    arch-chroot /mnt systemctl enable reflector.service         # Rank mirrors after boot
    arch-chroot /mnt systemctl enable paccache.timer            # Discard cached/unused packages weekly
    arch-chroot /mnt systemctl enable pkgfile-update.timer      # Pkgfile update timer
    arch-chroot /mnt systemctl enable fstrim.timer              # SSD support

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Configure System"
    # ----------------------------------------------------------------------------------------------------

    # Reduce shutdown timeout
    sed -i "s/^#DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=5s/" /mnt/etc/systemd/system.conf

    # Set Nano colors
    sed -i 's;^# include "/usr/share/nano/\*\.nanorc";include "/usr/share/nano/*.nanorc"\ninclude "/usr/share/nano/extra/*.nanorc";g' /mnt/etc/nanorc

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install AUR Helper"
    # ----------------------------------------------------------------------------------------------------

    # Install paru as user
    repo_url="https://aur.archlinux.org/paru-bin.git"
    tmp_name=$(mktemp -u "/home/${ARCH_USERNAME}/paru-bin.XXXXXXXXXX")
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- git clone "$repo_url" "$tmp_name"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- bash -c "cd $tmp_name && makepkg -si --noconfirm"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- rm -rf "$tmp_name"

    # Paru config
    sed -i 's/^#BottomUp/BottomUp/g' /mnt/etc/paru.conf
    sed -i 's/^#SudoLoop/SudoLoop/g' /mnt/etc/paru.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install GNOME Packages (This may take a while)"
    # ----------------------------------------------------------------------------------------------------

    # Install packages
    packages=()

    # GNOME base
    packages+=("gnome")                            # GNOME core
    packages+=("gnome-tweaks")                     # GNOME tweaks
    packages+=("gnome-themes-extra")               # GNOME themes
    packages+=("gnome-software-packagekit-plugin") # GNOME software center support
    packages+=("power-profiles-daemon")            # GNOME power profile support
    packages+=("fwupd")                            # GNOME security settings
    packages+=("rygel")                            # GNOME media sharing support
    packages+=("cups")                             # GNOME printer support

    # GNOME screensharing, flatpak & pipewire support
    packages+=("xdg-desktop-portal")
    packages+=("xdg-desktop-portal-gtk")
    packages+=("xdg-desktop-portal-gnome")

    # GNOME Indicator support
    packages+=("libappindicator-gtk2") && packages+=("lib32-libappindicator-gtk2")
    packages+=("libappindicator-gtk3") && packages+=("lib32-libappindicator-gtk3")

    # Audio
    packages+=("pipewire")       # Pipewire
    packages+=("pipewire-pulse") # Replacement for pulse
    packages+=("pipewire-jack")  # Replacement for jack
    packages+=("wireplumber")    # Pipewire session manager

    # Networking
    packages+=("samba")
    packages+=("gvfs")
    packages+=("gvfs-mtp")
    packages+=("gvfs-smb")
    packages+=("gvfs-nfs")
    packages+=("gvfs-afc")
    packages+=("gvfs-goa")
    packages+=("gvfs-gphoto2")
    packages+=("gvfs-google")

    # Utils (https://wiki.archlinux.org/title/File_systems)
    packages+=("nfs-utils")
    packages+=("f2fs-tools")
    packages+=("udftools")
    packages+=("ntfs-3g")
    packages+=("exfat-utils")
    packages+=("p7zip")
    packages+=("zip")
    packages+=("unrar")
    packages+=("tar")

    # Codecs
    packages+=("gst-libav")
    packages+=("gst-plugin-pipewire")
    packages+=("gst-plugins-ugly")
    packages+=("libdvdcss")

    # Driver
    packages+=("xf86-input-synaptics")

    # Fonts
    packages+=("noto-fonts")
    packages+=("noto-fonts-emoji")
    packages+=("ttf-liberation")
    packages+=("ttf-dejavu")

    # E-Mail
    packages+=("geary")

    # VM Guest support (if VM detected)
    if [ "$(systemd-detect-virt)" != 'none' ]; then
        packages+=("spice")
        packages+=("spice-vdagent")
        packages+=("spice-protocol")
        packages+=("spice-gtk")
    fi

    # Install packages
    arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install GNOME Browser Connector"
    # ----------------------------------------------------------------------------------------------------

    repo_url="https://aur.archlinux.org/gnome-browser-connector.git"
    tmp_name=$(mktemp -u "/home/${ARCH_USERNAME}/gnome-browser-connector.XXXXXXXXXX")
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- git clone "$repo_url" "$tmp_name"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- bash -c "cd $tmp_name && makepkg -si --noconfirm"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- rm -rf "$tmp_name"

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install Plymouth"
    # ----------------------------------------------------------------------------------------------------

    repo_url="https://aur.archlinux.org/plymouth.git"
    tmp_name=$(mktemp -u "/home/${ARCH_USERNAME}/plymouth.XXXXXXXXXX")
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- git clone "$repo_url" "$tmp_name"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- bash -c "cd $tmp_name && yes | LC_ALL=en_US.UTF-8 makepkg -sif"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- rm -rf "$tmp_name"

    # Install Plymouth (GDM)
    repo_url="https://aur.archlinux.org/gdm-plymouth.git"
    tmp_name=$(mktemp -u "/home/${ARCH_USERNAME}/gdm-plymouth.XXXXXXXXXX")
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- git clone "$repo_url" "$tmp_name"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- sed -i 's/^options=(debug)/options=(!debug)/' "${tmp_name}/PKGBUILD"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- bash -c "cd $tmp_name && yes | LC_ALL=en_US.UTF-8 makepkg -sif"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- rm -rf "$tmp_name"

    # Download Plymouth config & watermark
    curl -Lf "${ASSET_BASE_URL}/plymouth/spinner.plymouth" -o "/mnt/usr/share/plymouth/themes/spinner/spinner.plymouth"
    curl -Lf "${ASSET_BASE_URL}/plymouth/watermark.png" -o "/mnt/usr/share/plymouth/themes/spinner/watermark.png"

    # Configure mkinitcpio
    sed -i "s/base systemd autodetect/base systemd sd-plymouth autodetect/g" /mnt/etc/mkinitcpio.conf

    # Rebuild
    arch-chroot /mnt mkinitcpio -P

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Enable GNOME Auto Login"
    # ----------------------------------------------------------------------------------------------------

    grep -qrnw /mnt/etc/gdm/custom.conf -e "AutomaticLoginEnable" || sed -i "s/^\[security\]/AutomaticLoginEnable=True\nAutomaticLogin=${ARCH_USERNAME}\n\n\[security\]/g" /mnt/etc/gdm/custom.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Configure Git"
    # ----------------------------------------------------------------------------------------------------

    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- mkdir -p "/home/${ARCH_USERNAME}/.config/git"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- touch "/home/${ARCH_USERNAME}/.config/git/config"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- git config --global credential.helper /usr/lib/git-core/git-credential-libsecret

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Configure Samba"
    # ----------------------------------------------------------------------------------------------------

    mkdir -p "/mnt/etc/samba/"
    {
        echo "[global]"
        echo "   workgroup = WORKGROUP"
        echo "   log file = /var/log/samba/%m"
    } >/mnt/etc/samba/smb.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Create X11 Layouts"
    # ----------------------------------------------------------------------------------------------------

    # Keyboard layout
    {
        echo 'Section "InputClass"'
        echo '    Identifier "keyboard"'
        echo '    MatchIsKeyboard "yes"'
        echo '    Option "XkbLayout" "'"${ARCH_KEYBOARD_LAYOUT}"'"'
        echo '    Option "XkbModel" "pc105"'
        echo '    Option "XkbVariant" "'"${ARCH_KEYBOARD_VARIANT}"'"'
        echo 'EndSection'
    } >/mnt/etc/X11/xorg.conf.d/00-keyboard.conf

    # Mouse layout
    {
        echo 'Section "InputClass"'
        echo '    Identifier "mouse"'
        echo '    Driver "libinput"'
        echo '    MatchIsPointer "yes"'
        echo '    Option "AccelProfile" "flat"'
        echo '    Option "AccelSpeed" "0"'
        echo 'EndSection'
    } >/mnt/etc/X11/xorg.conf.d/50-mouse.conf

    # Touchpad layout
    {
        echo 'Section "InputClass"'
        echo '    Identifier "touchpad"'
        echo '    Driver "libinput"'
        echo '    MatchIsTouchpad "on"'
        echo '    Option "ClickMethod" "clickfinger"'
        echo '    Option "Tapping" "off"'
        echo '    Option "NaturalScrolling" "true"'
        echo 'EndSection'
    } >/mnt/etc/X11/xorg.conf.d/70-touchpad.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Enable Desktop Services"
    # ----------------------------------------------------------------------------------------------------

    arch-chroot /mnt systemctl enable gdm.service                                                           # GNOME
    arch-chroot /mnt systemctl enable bluetooth.service                                                     # Bluetooth
    arch-chroot /mnt systemctl enable avahi-daemon                                                          # Network browsing service
    arch-chroot /mnt systemctl enable cups.service                                                          # Printer
    arch-chroot /mnt systemctl enable smb.service                                                           # Samba
    arch-chroot /mnt systemctl enable nmb.service                                                           # Samba
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- systemctl enable --user pipewire.service       # Pipewire
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- systemctl enable --user pipewire-pulse.service # Pipewire
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- systemctl enable --user wireplumber.service    # Pipewire

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Hide Applications"
    # ----------------------------------------------------------------------------------------------------

    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- mkdir -p "/home/$ARCH_USERNAME/.local/share/applications"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- echo -e '[Desktop Entry]\nHidden=true' >"/mnt/home/$ARCH_USERNAME/.local/share/applications/avahi-discover.desktop"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- echo -e '[Desktop Entry]\nHidden=true' >"/mnt/home/$ARCH_USERNAME/.local/share/applications/bssh.desktop"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- echo -e '[Desktop Entry]\nHidden=true' >"/mnt/home/$ARCH_USERNAME/.local/share/applications/bvnc.desktop"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- echo -e '[Desktop Entry]\nHidden=true' >"/mnt/home/$ARCH_USERNAME/.local/share/applications/qv4l2.desktop"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_USERNAME" -- echo -e '[Desktop Entry]\nHidden=true' >"/mnt/home/$ARCH_USERNAME/.local/share/applications/qvidcap.desktop"

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install Graphics Driver (${ARCH_DRIVER})"
    # ----------------------------------------------------------------------------------------------------

    if [ "$ARCH_DRIVER" = "intel-hd" ]; then

        # https://wiki.archlinux.org/title/Intel_graphics#Installation

        # Intel Driver
        packages=()
        packages+=("vulkan-intel") && packages+=("lib32-vulkan-intel")
        packages+=("gamemode") && packages+=("lib32-gamemode")
        packages+=("libva-intel-driver")
        packages+=("intel-media-driver")

        # Install packages
        arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"

        # Configure mkinitcpio
        sed -i "s/MODULES=()/MODULES=(i915)/g" /mnt/etc/mkinitcpio.conf

        # Rebuild initramfs
        arch-chroot /mnt mkinitcpio -P
    fi

    # ////////////////////////////////////////////////////////////////////////////////////////////////////

    if [ "$ARCH_DRIVER" = "nvidia" ]; then

        # https://wiki.archlinux.org/title/NVIDIA#Installation

        # NVIDIA Driver
        packages=()
        packages+=("xorg-xrandr")
        packages+=("nvidia-lts")
        packages+=("nvidia-settings")
        packages+=("nvidia-utils") && packages+=("lib32-nvidia-utils")
        packages+=("opencl-nvidia") && packages+=("lib32-opencl-nvidia")
        packages+=("gamemode") && packages+=("lib32-gamemode")

        # Install packages
        arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"

        # Early Loading
        sed -i "s/MODULES=()/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/g" /mnt/etc/mkinitcpio.conf

        # DRM kernel mode setting
        sed -i "s/nowatchdog quiet/nowatchdog nvidia_drm.modeset=1 quiet/g" /mnt/boot/loader/entries/arch.conf

        # Rebuild
        arch-chroot /mnt mkinitcpio -P

        # Enable Wayland Support (https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver)
        arch-chroot /mnt ln -s /dev/null /etc/udev/rules.d/61-gdm.rules
    fi

    # ////////////////////////////////////////////////////////////////////////////////////////////////////

    if [ "$ARCH_DRIVER" = "nvidia-optimus" ]; then

        # https://wiki.archlinux.org/title/NVIDIA_Optimus#Use_NVIDIA_graphics_only

        packages=()

        # NVIDIA Driver
        packages+=("xorg-xrandr")
        packages+=("nvidia-lts")
        packages+=("nvidia-settings")
        packages+=("nvidia-utils") && packages+=("lib32-nvidia-utils")
        packages+=("opencl-nvidia") && packages+=("lib32-opencl-nvidia")
        packages+=("gamemode") && packages+=("lib32-gamemode")
        packages+=("libva-intel-driver") # (fixed errors on loading NVIDIA)
        packages+=("intel-media-driver")

        # Install packages
        arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"

        # Early Loading
        sed -i "s/MODULES=()/MODULES=(i915 nvidia nvidia_modeset nvidia_uvm nvidia_drm)/g" /mnt/etc/mkinitcpio.conf

        # DRM kernel mode setting (enable prime sync and fix screen-tearing issues)
        sed -i "s/nowatchdog quiet/nowatchdog nvidia_drm.modeset=1 quiet/g" /mnt/boot/loader/entries/arch.conf

        # Rebuild
        arch-chroot /mnt mkinitcpio -P

        # Configure Xorg
        {
            echo 'Section "OutputClass"'
            echo '    Identifier "intel"'
            echo '    MatchDriver "i915"'
            echo '    Driver "modesetting"'
            echo 'EndSection'
            echo ''
            echo 'Section "OutputClass"'
            echo '    Identifier "nvidia"'
            echo '    MatchDriver "nvidia-drm"'
            echo '    Driver "nvidia"'
            echo '    Option "AllowEmptyInitialConfiguration"'
            echo '    Option "PrimaryGPU" "yes"'
            echo '    ModulePath "/usr/lib/nvidia/xorg"'
            echo '    ModulePath "/usr/lib/xorg/modules"'
            echo 'EndSection'
        } | tee /mnt/etc/X11/xorg.conf.d/10-nvidia-drm-outputclass.conf

        # Configure GDM
        {
            echo '[Desktop Entry]'
            echo 'Type=Application'
            echo 'Name=Optimus'
            echo 'Exec=sh -c "xrandr --setprovideroutputsource modesetting NVIDIA-0; xrandr --auto"'
            echo 'NoDisplay=true'
            echo 'X-GNOME-Autostart-Phase=DisplayServer'
        } | tee /mnt/usr/share/gdm/greeter/autostart/optimus.desktop /mnt/etc/xdg/autostart/optimus.desktop

        # Disable Wayland Support (https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver)
        [ -f /mnt/etc/udev/rules.d/61-gdm.rules ] && rm -f /mnt/etc/udev/rules.d/61-gdm.rules

        # GNOME: Enable X11 instead of Wayland
        sed -i "s/^#WaylandEnable=false/WaylandEnable=false/g" /mnt/etc/gdm/custom.conf
    fi

    # ////////////////////////////////////////////////////////////////////////////////////////////////////

    if [ "$ARCH_DRIVER" = "amd" ]; then

        # https://wiki.archlinux.org/title/AMDGPU#Installation

        # AMDGPU Driver
        packages=()
        packages+=("xf86-video-amdgpu")
        packages+=("libva-mesa-driver") && packages+=("lib32-libva-mesa-driver")
        packages+=("vulkan-radeon") && packages+=("lib32-vulkan-radeon")
        packages+=("mesa-vdpau") && packages+=("lib32-mesa-vdpau")
        packages+=("gamemode") && packages+=("lib32-gamemode")

        # Install packages
        arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"

        # Early Loading
        sed -i "s/MODULES=()/MODULES=(radeon)/g" /mnt/etc/mkinitcpio.conf

        # Rebuild
        arch-chroot /mnt mkinitcpio -P
    fi

    # ////////////////////////////////////////////////////////////////////////////////////////////////////

    if [ "$ARCH_DRIVER" = "amd-legacy" ]; then

        # https://wiki.archlinux.org/title/ATI#Installation

        # ATI Driver
        packages=()
        packages+=("xf86-video-ati")
        packages+=("libva-mesa-driver") && packages+=("lib32-libva-mesa-driver")
        packages+=("mesa-vdpau") && packages+=("lib32-mesa-vdpau")
        packages+=("gamemode") && packages+=("lib32-gamemode")

        # Install packages
        arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"

        # Early Loading
        sed -i "s/MODULES=()/MODULES=(amdgpu radeon)/g" /mnt/etc/mkinitcpio.conf

        # Rebuild
        arch-chroot /mnt mkinitcpio -P
    fi

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Cleanup Installation"
    # ----------------------------------------------------------------------------------------------------

    # Remove sudo needs no password rights
    sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /mnt/etc/sudoers

    # Set home permission
    arch-chroot /mnt chown -R "$ARCH_USERNAME":"$ARCH_USERNAME" "/home/${ARCH_USERNAME}"

    # Remove orphans
    arch-chroot /mnt bash -c "pacman -Qtd &>/dev/null && pacman -Qtdq | pacman -Rns --noconfirm -"

    # Unmount
    swapoff -a
    umount -A -R /mnt
    [ "$ARCH_ENCRYPTION_ENABLED" = "true" ] && cryptsetup close cryptroot

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Arch Installation finished"
    # ----------------------------------------------------------------------------------------------------

    # Save success result
    touch /tmp/arch-install.success

) | whiptail --title "Arch Linux Installation" --gauge "Start Arch Installation..." 7 "$TUI_WIDTH" 0
