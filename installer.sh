#!/usr/bin/env bash

VERSION='1.2.7'

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# //////////////////////////////////////// ARCH OS INSTALLER /////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////

# SOURCE:   https://github.com/murkl/arch-os
# AUTOR:    murkl
# ORIGIN:   Germany
# LICENCE:  GPL-V2

# CONFIGURATION
set -o pipefail # A pipeline error results in the error status of the entire pipeline
set -u          # Uninitialized variables trigger errors
set -e          # Terminate if any command exits with a non-zero
set -E          # ERR trap inherited by shell functions (errtrace)

# ENVIRONMENT
SCRIPT_CONF="./installer.conf"
SCRIPT_LOG="./installer.log"

# ----------------------------------------------------------------------------------------------------
# DESCRIPTORS
# ----------------------------------------------------------------------------------------------------

# Print nothing from stdin & stderr to console
exec 3>&1 4>&2       # Saves file descriptors (new stdin: &3 new stderr: &4)
exec 1>"$SCRIPT_LOG" # Log stdin to logfile
exec 2>"$SCRIPT_LOG" # Log stderr to logfile

# ----------------------------------------------------------------------------------------------------
# PRINT FUNCTIONS
# ----------------------------------------------------------------------------------------------------

print_info() {
    echo -e "INFO:  ${*}" >&3
}

print_warn() {
    echo -e "WARN:  ${*}" >&3
}

print_error() {
    echo -e "ERROR: ${*}" >&4
}

print_header() {
    echo -e '
           █████  ██████   ██████ ██   ██      ██████  ███████ 
          ██   ██ ██   ██ ██      ██   ██     ██    ██ ██      
          ███████ ██████  ██      ███████     ██    ██ ███████ 
          ██   ██ ██   ██ ██      ██   ██     ██    ██      ██ 
          ██   ██ ██   ██  ██████ ██   ██      ██████  ███████
    ' >&3
}

# ----------------------------------------------------------------------------------------------------
# TRAP
# ----------------------------------------------------------------------------------------------------

# This trap is called on error in installation: ERR
# shellcheck disable=SC2317
trap_error() {

    local result_code="$?"
    local line_no="$1"
    local func_name="$2"

    # Print to stderr (will be logged in installer.log)
    echo "###ERR" >&2 # Print marker for exit logging trap
    echo "'${BASH_COMMAND}' failed with exit code ${result_code} in function '${func_name}' (line ${line_no})" >&4
    echo "RESULT: $result_code" >&4
}

# Set error trap for setup
trap 'trap_error ${LINENO} ${FUNCNAME-main}' EXIT

# ----------------------------------------------------------------------------------------------------
# CHECK PROPERTIES
# ----------------------------------------------------------------------------------------------------
[ -z "${ARCH_OS_USERNAME}" ] && TUI_POSITION="user" && return 1
[ -z "${ARCH_OS_PASSWORD}" ] && TUI_POSITION="password" && return 1
[ -z "${ARCH_OS_TIMEZONE}" ] && TUI_POSITION="language" && return 1
[ -z "${ARCH_OS_LOCALE_LANG}" ] && TUI_POSITION="language" && return 1
[ -z "${ARCH_OS_LOCALE_GEN_LIST[*]}" ] && TUI_POSITION="language" && return 1
[ -z "${ARCH_OS_VCONSOLE_KEYMAP}" ] && TUI_POSITION="keyboard" && return 1
[ -z "${ARCH_OS_DISK}" ] && TUI_POSITION="disk" && return 1
[ -z "${ARCH_OS_BOOT_PARTITION}" ] && TUI_POSITION="disk" && return 1
[ -z "${ARCH_OS_ROOT_PARTITION}" ] && TUI_POSITION="disk" && return 1
[ -z "${ARCH_OS_ENCRYPTION_ENABLED}" ] && TUI_POSITION="encrypt" && return 1
[ -z "${ARCH_OS_BOOTSPLASH_ENABLED}" ] && TUI_POSITION="bootsplash" && return 1
[ -z "${ARCH_OS_VARIANT}" ] && TUI_POSITION="variant" && return 1
[ "${ARCH_OS_VARIANT}" = "desktop" ] && [ -z "${ARCH_OS_GRAPHICS_DRIVER}" ] && TUI_POSITION="variant" && return 1
[ "${ARCH_OS_VARIANT}" = "desktop" ] && [ -z "${ARCH_OS_X11_KEYBOARD_LAYOUT}" ] && TUI_POSITION="variant" && return 1

# Source properties file
# shellcheck disable=SC1090
[ -f "$SCRIPT_CONF" ] && source "$SCRIPT_CONF"

# ----------------------------------------------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------------------------------------------

# Print header
print_header
echo 'Welcome to the Arch OS Installer!'
echo 'Your Arch OS Installation Configuration:' >&3
cat installer.conf >&3

echo "Start Installation? [y/N]"

# ----------------------------------------------------------------------------------------------------

pacman_install() {

    local packages=("$@")
    local pacman_failed="true"

    # Retry installing packages 5 times (in case of connection issues)
    for ((i = 1; i < 6; i++)); do

        # Print updated whiptail info
        [ $i -gt 1 ] && print_whiptail_info "${PROGRESS_TITLE} (${i}. retry)"

        # Try installing packages
        if ! arch-chroot /mnt pacman -S --noconfirm --needed --disable-download-timeout "${packages[@]}"; then
            sleep 10 && continue # Wait 10 seconds & try again
        else
            pacman_failed="false" && break # Success: break loop
        fi
    done

    # Result
    [ "$pacman_failed" = "true" ] && return 1  # Failed after 5 retries
    [ "$pacman_failed" = "false" ] && return 0 # Success
}

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ////////////////////////////////////////////  MAIN  ////////////////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////
# 1. START SETUP (TUI)

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ///////////////////////////////////  ARCH OS CORE INSTALLATION  ////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////
# 2. START INSTALLATION

# Messure execution time
SECONDS=0

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Checkup"
# ----------------------------------------------------------------------------------------------------

[ ! -d /sys/firmware/efi ] && echo "ERROR: BIOS not supported! Please set your boot mode to UEFI." >&2 && exit 1
[ "$(cat /proc/sys/kernel/hostname)" != "archiso" ] && echo "ERROR: You must execute the Installer from Arch ISO!" >&2 && exit 1

exit

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Waiting for Reflector from Arch ISO"
# ----------------------------------------------------------------------------------------------------

# This mirrorlist will copied to new Arch system during installation
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
[ "$ARCH_OS_ECN_ENABLED" = "false" ] && sysctl net.ipv4.tcp_ecn=0

# Update keyring
pacman -Sy --noconfirm archlinux-keyring

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Wipe & Create Partitions (${ARCH_OS_DISK})"
# ----------------------------------------------------------------------------------------------------

# Wipe all partitions
wipefs -af "$ARCH_OS_DISK"

# Create new GPT partition table
sgdisk -o "$ARCH_OS_DISK"

# Create partition /boot efi partition: 1 GiB
sgdisk -n 1:0:+1G -t 1:ef00 -c 1:boot "$ARCH_OS_DISK"

# Create partition / partition: Rest of space
sgdisk -n 2:0:0 -t 2:8300 -c 2:root "$ARCH_OS_DISK"

# Reload partition table
partprobe "$ARCH_OS_DISK"

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Enable Disk Encryption"
# ----------------------------------------------------------------------------------------------------

if [ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ]; then
    echo -n "$ARCH_OS_PASSWORD" | cryptsetup luksFormat "$ARCH_OS_ROOT_PARTITION"
    echo -n "$ARCH_OS_PASSWORD" | cryptsetup open "$ARCH_OS_ROOT_PARTITION" cryptroot
else
    echo "> Skipped"
fi

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Format Disk"
# ----------------------------------------------------------------------------------------------------

mkfs.fat -F 32 -n BOOT "$ARCH_OS_BOOT_PARTITION"
[ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && mkfs.ext4 -F -L ROOT /dev/mapper/cryptroot
[ "$ARCH_OS_ENCRYPTION_ENABLED" = "false" ] && mkfs.ext4 -F -L ROOT "$ARCH_OS_ROOT_PARTITION"

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Mount Disk"
# ----------------------------------------------------------------------------------------------------

[ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && mount -v /dev/mapper/cryptroot /mnt
[ "$ARCH_OS_ENCRYPTION_ENABLED" = "false" ] && mount -v "$ARCH_OS_ROOT_PARTITION" /mnt
mkdir -p /mnt/boot
mount -v "$ARCH_OS_BOOT_PARTITION" /mnt/boot

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Pacstrap Arch OS Core Packages (May take about 8 minutes)"
# ----------------------------------------------------------------------------------------------------

# Core packages
packages=()
packages+=("base")
packages+=("base-devel")
packages+=("linux-firmware")
packages+=("zram-generator")
packages+=("networkmanager")
packages+=("${ARCH_OS_KERNEL}")

# Add microcode package
[ -n "$ARCH_OS_MICROCODE" ] && [ "$ARCH_OS_MICROCODE" != "none" ] && packages+=("$ARCH_OS_MICROCODE")

# Install core packages and initialize an empty pacman keyring in the target
pacstrap -K /mnt "${packages[@]}"

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Generate /etc/fstab"
# ----------------------------------------------------------------------------------------------------

genfstab -U /mnt >>/mnt/etc/fstab

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Create Swap (zram-generator)"
# ----------------------------------------------------------------------------------------------------
{
    # https://wiki.archlinux.org/title/Zram#Using_zram-generator
    echo '[zram0]'
    echo 'zram-size = ram / 2'
    echo 'compression-algorithm = zstd'
    echo 'swap-priority = 100'
    echo 'fs-type = swap'
} >/mnt/etc/systemd/zram-generator.conf

# Optimize swap on zram (https://wiki.archlinux.org/title/Zram#Optimizing_swap_on_zram)
{
    echo 'vm.swappiness = 180'
    echo 'vm.watermark_boost_factor = 0'
    echo 'vm.watermark_scale_factor = 125'
    echo 'vm.page-cluster = 0'
} >/mnt/etc/sysctl.d/99-vm-zram-parameters.conf

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Timezone & System Clock"
# ----------------------------------------------------------------------------------------------------

arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$ARCH_OS_TIMEZONE" /etc/localtime
arch-chroot /mnt hwclock --systohc # Set hardware clock from system clock

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Set Console Keymap"
# ----------------------------------------------------------------------------------------------------

echo "KEYMAP=$ARCH_OS_VCONSOLE_KEYMAP" >/mnt/etc/vconsole.conf
[ -n "$ARCH_OS_VCONSOLE_FONT" ] && echo "FONT=$ARCH_OS_VCONSOLE_FONT" >>/mnt/etc/vconsole.conf

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Generate Locale"
# ----------------------------------------------------------------------------------------------------

echo "LANG=${ARCH_OS_LOCALE_LANG}.UTF-8" >/mnt/etc/locale.conf
for ((i = 0; i < ${#ARCH_OS_LOCALE_GEN_LIST[@]}; i++)); do sed -i "s/^#${ARCH_OS_LOCALE_GEN_LIST[$i]}/${ARCH_OS_LOCALE_GEN_LIST[$i]}/g" "/mnt/etc/locale.gen"; done
arch-chroot /mnt locale-gen

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Set Hostname (${ARCH_OS_HOSTNAME})"
# ----------------------------------------------------------------------------------------------------

echo "$ARCH_OS_HOSTNAME" >/mnt/etc/hostname

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Set /etc/hosts"
# ----------------------------------------------------------------------------------------------------

{
    echo '127.0.0.1    localhost'
    echo '::1          localhost'
} >/mnt/etc/hosts

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Create Initial Ramdisk"
# ----------------------------------------------------------------------------------------------------

[ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd keyboard autodetect modconf block sd-encrypt filesystems sd-vconsole fsck)/" /mnt/etc/mkinitcpio.conf
[ "$ARCH_OS_ENCRYPTION_ENABLED" = "false" ] && sed -i "s/^HOOKS=(.*)$/HOOKS=(base systemd keyboard autodetect modconf block filesystems sd-vconsole fsck)/" /mnt/etc/mkinitcpio.conf
arch-chroot /mnt mkinitcpio -P

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Install Bootloader (systemdboot)"
# ----------------------------------------------------------------------------------------------------

# Install systemdboot to /boot
arch-chroot /mnt bootctl --esp-path=/boot install

# Kernel args
# Zswap should be disabled when using zram (https://github.com/archlinux/archinstall/issues/881)
kernel_args_default="rw init=/usr/lib/systemd/systemd zswap.enabled=0 nowatchdog quiet splash vt.global_cursor_default=0"
[ "$ARCH_OS_ENCRYPTION_ENABLED" = "true" ] && kernel_args="rd.luks.name=$(blkid -s UUID -o value "${ARCH_OS_ROOT_PARTITION}")=cryptroot root=/dev/mapper/cryptroot ${kernel_args_default}"
[ "$ARCH_OS_ENCRYPTION_ENABLED" = "false" ] && kernel_args="root=PARTUUID=$(lsblk -dno PARTUUID "${ARCH_OS_ROOT_PARTITION}") ${kernel_args_default}"

# Create Bootloader config
{
    echo 'default arch.conf'
    echo 'console-mode auto'
    echo 'timeout 0'
    echo 'editor yes'
} >/mnt/boot/loader/loader.conf

# Create default boot entry
{
    echo 'title   Arch OS'
    echo "linux   /vmlinuz-${ARCH_OS_KERNEL}"
    [ -n "$ARCH_OS_MICROCODE" ] && [ "$ARCH_OS_MICROCODE" != "none" ] && echo "initrd  /${ARCH_OS_MICROCODE}.img"
    echo "initrd  /initramfs-${ARCH_OS_KERNEL}.img"
    echo "options ${kernel_args}"
} >/mnt/boot/loader/entries/arch.conf

# Create fallback boot entry
{
    echo 'title   Arch OS (Fallback)'
    echo "linux   /vmlinuz-${ARCH_OS_KERNEL}"
    [ -n "$ARCH_OS_MICROCODE" ] && [ "$ARCH_OS_MICROCODE" != "none" ] && echo "initrd  /${ARCH_OS_MICROCODE}.img"
    echo "initrd  /initramfs-${ARCH_OS_KERNEL}-fallback.img"
    echo "options ${kernel_args}"
} >/mnt/boot/loader/entries/arch-fallback.conf

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Create User (${ARCH_OS_USERNAME})"
# ----------------------------------------------------------------------------------------------------

# Create new user
arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$ARCH_OS_USERNAME"

# Allow users in group wheel to use sudo
sed -i 's^# %wheel ALL=(ALL:ALL) ALL^%wheel ALL=(ALL:ALL) ALL^g' /mnt/etc/sudoers

# Add password feedback
echo -e "\n## Enable sudo password feedback\nDefaults pwfeedback" >>/mnt/etc/sudoers

# Change passwords
printf "%s\n%s" "${ARCH_OS_PASSWORD}" "${ARCH_OS_PASSWORD}" | arch-chroot /mnt passwd
printf "%s\n%s" "${ARCH_OS_PASSWORD}" "${ARCH_OS_PASSWORD}" | arch-chroot /mnt passwd "$ARCH_OS_USERNAME"

# Add sudo needs no password rights (only for installation)
sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /mnt/etc/sudoers

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Enable Core Services"
# ----------------------------------------------------------------------------------------------------

arch-chroot /mnt systemctl enable NetworkManager                   # Network Manager
arch-chroot /mnt systemctl enable fstrim.timer                     # SSD support
arch-chroot /mnt systemctl enable systemd-zram-setup@zram0.service # Swap (zram-generator)
arch-chroot /mnt systemctl enable systemd-oomd.service             # Out of memory killer (swap is required)
arch-chroot /mnt systemctl enable systemd-boot-update.service      # Auto bootloader update
arch-chroot /mnt systemctl enable systemd-timesyncd.service        # Sync time from internet after boot

# ----------------------------------------------------------------------------------------------------
# END ARCH OS CORE
# ----------------------------------------------------------------------------------------------------

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Install Bootsplash"
# ----------------------------------------------------------------------------------------------------

if [ "$ARCH_OS_BOOTSPLASH_ENABLED" = "true" ]; then

    # Install packages
    packages=()
    packages+=("plymouth")
    packages+=("git") # need when core variant is used
    pacman_install "${packages[@]}"

    # Configure mkinitcpio
    sed -i "s/base systemd keyboard/base systemd plymouth keyboard/g" /mnt/etc/mkinitcpio.conf

    # Install Arch OS plymouth theme
    repo_url="https://aur.archlinux.org/plymouth-theme-arch-os.git"
    tmp_name=$(mktemp -u "/home/${ARCH_OS_USERNAME}/plymouth-theme-arch-os.XXXXXXXXXX")
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- git clone "$repo_url" "$tmp_name"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "cd $tmp_name && makepkg -si --noconfirm"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- rm -rf "$tmp_name"

    # Set Theme & rebuild initram disk
    arch-chroot /mnt plymouth-set-default-theme -R arch-os
fi

# ----------------------------------------------------------------------------------------------------
# END BOOTSPLASH
# ----------------------------------------------------------------------------------------------------

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ////////////////////////////////////  ARCH OS BASE INSTALLATION ////////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////
# 3. BASE INSTALLATION

if [ "$ARCH_OS_VARIANT" != "core" ]; then

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install Arch OS Base Packages"
    # ----------------------------------------------------------------------------------------------------

    # Install Base packages
    packages=()
    packages+=("pacman-contrib")
    packages+=("reflector")
    packages+=("pkgfile")
    packages+=("git")
    packages+=("nano")
    pacman_install "${packages[@]}"

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Enable Arch OS Base Services"
    # ----------------------------------------------------------------------------------------------------

    # Base Services
    arch-chroot /mnt systemctl enable reflector.service    # Rank mirrors after boot (reflector)
    arch-chroot /mnt systemctl enable paccache.timer       # Discard cached/unused packages weekly (pacman-contrib)
    arch-chroot /mnt systemctl enable pkgfile-update.timer # Pkgfile update timer (pkgfile)

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Configure Pacman & Reflector"
    # ----------------------------------------------------------------------------------------------------

    # Configure parrallel downloads, colors & multilib
    sed -i 's/^#ParallelDownloads/ParallelDownloads/' /mnt/etc/pacman.conf
    sed -i 's/^#Color/Color\nILoveCandy/' /mnt/etc/pacman.conf
    if [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ]; then
        sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf
        arch-chroot /mnt pacman -Syy --noconfirm
    fi

    # Configure reflector service
    {
        echo "# Reflector config for the systemd service"
        echo "--save /etc/pacman.d/mirrorlist"
        [ -n "$ARCH_OS_REFLECTOR_COUNTRY" ] && echo "--country ${ARCH_OS_REFLECTOR_COUNTRY}"
        echo "--completion-percent 95"
        echo "--protocol https"
        echo "--latest 5"
        echo "--sort rate"
    } >/mnt/etc/xdg/reflector/reflector.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Configure System"
    # ----------------------------------------------------------------------------------------------------

    # Set nano environment
    {
        echo 'EDITOR=nano'
        echo 'VISUAL=nano'
    } >/mnt/etc/environment

    # Set Nano colors
    sed -i "s/^# set linenumbers/set linenumbers/" /mnt/etc/nanorc
    sed -i "s/^# set minibar/set minibar/" /mnt/etc/nanorc
    sed -i 's;^# include "/usr/share/nano/\*\.nanorc";include "/usr/share/nano/*.nanorc"\ninclude "/usr/share/nano/extra/*.nanorc";g' /mnt/etc/nanorc

    # Reduce shutdown timeout
    sed -i "s/^#DefaultTimeoutStopSec=.*/DefaultTimeoutStopSec=10s/" /mnt/etc/systemd/system.conf

    # Set max VMAs (need for some apps/games)
    echo vm.max_map_count=1048576 >/mnt/etc/sysctl.d/vm.max_map_count.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install AUR Helper"
    # ----------------------------------------------------------------------------------------------------

    if [ -n "$ARCH_OS_AUR_HELPER" ] && [ "$ARCH_OS_AUR_HELPER" != "none" ]; then

        # Install AUR Helper as user
        repo_url="https://aur.archlinux.org/${ARCH_OS_AUR_HELPER}.git"
        tmp_name=$(mktemp -u "/home/${ARCH_OS_USERNAME}/${ARCH_OS_AUR_HELPER}.XXXXXXXXXX")
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- git clone "$repo_url" "$tmp_name"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- bash -c "cd $tmp_name && makepkg -si --noconfirm"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- rm -rf "$tmp_name"

        # Paru config
        if [ "$ARCH_OS_AUR_HELPER" = "paru" ] || [ "$ARCH_OS_AUR_HELPER" = "paru-bin" ] || [ "$ARCH_OS_AUR_HELPER" = "paru-git" ]; then
            sed -i 's/^#BottomUp/BottomUp/g' /mnt/etc/paru.conf
            sed -i 's/^#SudoLoop/SudoLoop/g' /mnt/etc/paru.conf
        fi
    else
        echo "> Skipped"
    fi

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install Shell Enhancement"
    # ----------------------------------------------------------------------------------------------------

    if [ "$ARCH_OS_SHELL_ENHANCED_ENABLED" = "true" ]; then

        # Install packages
        packages=()
        packages+=("fish")
        packages+=("starship")
        packages+=("eza")
        packages+=("bat")
        packages+=("neofetch")
        packages+=("mc")
        packages+=("btop")
        packages+=("man-db")
        pacman_install "${packages[@]}"

        # Create config dirs for root & user
        mkdir -p "/mnt/root/.config/fish" "/mnt/home/${ARCH_OS_USERNAME}/.config/fish"
        mkdir -p "/mnt/root/.config/neofetch" "/mnt/home/${ARCH_OS_USERNAME}/.config/neofetch"

        # shellcheck disable=SC2016
        { # Create fish config for root & user
            echo 'if status is-interactive'
            echo '    # Commands to run in interactive sessions can go here'
            echo 'end'
            echo ''
            echo '# https://wiki.archlinux.de/title/Fish#Troubleshooting'
            echo 'if status --is-login'
            echo '    set PATH $PATH /usr/bin /sbin'
            echo 'end'
            echo ''
            echo '# Disable welcome message'
            echo 'set fish_greeting'
            echo ''
            echo '# Colorize man pages (bat)'
            echo -n 'export MANPAGER="sh -c ' && echo -n "'col -bx | bat -l man -p'" && echo '"'
            echo 'export MANROFFOPT="-c"'
            echo ''
            echo '# Source user aliases'
            echo 'source "$HOME/.config/fish/aliases.fish"'
            echo ''
            echo '# Source starship promt'
            echo 'starship init fish | source'
        } | tee "/mnt/root/.config/fish/config.fish" "/mnt/home/${ARCH_OS_USERNAME}/.config/fish/config.fish" >/dev/null

        { # Create fish aliases for root & user
            echo 'alias ls="eza --color=always --group-directories-first"'
            echo 'alias diff="diff --color=auto"'
            echo 'alias grep="grep --color=auto"'
            echo 'alias ip="ip -color=auto"'
            echo 'alias lt="ls -Tal"'
            echo 'alias open="xdg-open"'
            echo 'alias fetch="neofetch"'
            echo 'alias logs="systemctl --failed; echo; journalctl -p 3 -b"'
            echo 'alias q="exit"'
        } | tee "/mnt/root/.config/fish/aliases.fish" "/mnt/home/${ARCH_OS_USERNAME}/.config/fish/aliases.fish" >/dev/null

        { # Create starship config for root & user
            echo "# Get editor completions based on the config schema"
            echo "\"\$schema\" = 'https://starship.rs/config-schema.json'"
            echo ""
            echo "# Wait 10 milliseconds for starship to check files under the current directory"
            echo "scan_timeout = 10"
            echo ""
            echo "# Set command timeout"
            echo "command_timeout = 10000"
            echo ""
            echo "# Inserts a blank line between shell prompts"
            echo "add_newline = true"
            echo ""
            echo "# Replace the promt symbol"
            echo "[character]"
            echo "success_symbol = '[>](bold purple)'"
            echo ""
            echo "# Disable the package module, hiding it from the prompt completely"
            echo "[package]"
            echo "disabled = true"
        } | tee "/mnt/root/.config/starship.toml" "/mnt/home/${ARCH_OS_USERNAME}/.config/starship.toml" >/dev/null

        # shellcheck disable=SC2028,SC2016
        { # Create neofetch config for root & user
            echo '# https://github.com/dylanaraps/neofetch/wiki/Customizing-Info'
            echo ''
            echo 'print_info() {'
            echo '    prin'
            echo '    prin "Distro\t" "Arch OS"'
            echo '    info "Kernel\t" kernel'
            #echo '    info "Host\t" model'
            echo '    info "CPU\t" cpu'
            echo '    info "GPU\t" gpu'
            echo '    prin'
            echo '    info "Desktop\t" de'
            echo '    prin "Window\t" "$([ $XDG_SESSION_TYPE = "x11" ] && echo X11 || echo Wayland)"'
            echo '    info "Manager\t" wm'
            echo '    info "Shell\t" shell'
            echo '    info "Terminal\t" term'
            echo '    prin'
            echo '    info "Disk\t" disk'
            echo '    info "Memory\t" memory'
            echo '    info "IP\t" local_ip'
            echo '    info "Uptime\t" uptime'
            echo '    info "Packages\t" packages'
            echo '    prin'
            echo '    prin "$(color 1) ● \n $(color 2) ● \n $(color 3) ● \n $(color 4) ● \n $(color 5) ● \n $(color 6) ● \n $(color 7) ● \n $(color 8) ●"'
            echo '}'
            echo ''
            echo '# Config'
            echo 'separator=" → "'
            echo 'ascii_distro="auto"'
            echo 'ascii_bold="on"'
            echo 'ascii_colors=(5 5 5 5 5 5)'
            echo 'bold="on"'
            echo 'colors=(7 7 7 7 7 7)'
            echo 'gap=8'
            echo 'os_arch="off"'
            echo 'shell_version="off"'
            echo 'cpu_speed="off"'
            echo 'cpu_brand="on"'
            echo 'cpu_cores="off"'
            echo 'cpu_temp="off"'
            echo 'memory_display="info"'
            echo 'memory_percent="on"'
            echo 'memory_unit="gib"'
            echo 'disk_display="info"'
            echo 'disk_subtitle="none"'
        } | tee "/mnt/root/.config/neofetch/config.conf" "/mnt/home/${ARCH_OS_USERNAME}/.config/neofetch/config.conf" >/dev/null

        # Set correct user permissions
        arch-chroot /mnt chown -R "$ARCH_OS_USERNAME":"$ARCH_OS_USERNAME" "/home/${ARCH_OS_USERNAME}/"

        # Set Shell for root & user
        arch-chroot /mnt chsh -s /usr/bin/fish
        arch-chroot /mnt chsh -s /usr/bin/fish "$ARCH_OS_USERNAME"
    else
        # Install bash-completion
        pacman_install bash-completion
    fi

    # ----------------------------------------------------------------------------------------------------
    # END ARCH OS BASE
    # ----------------------------------------------------------------------------------------------------

fi

# ////////////////////////////////////////////////////////////////////////////////////////////////////
# ///////////////////////////////////  ARCH OS DESKTOP INSTALLATION //////////////////////////////////
# ////////////////////////////////////////////////////////////////////////////////////////////////////
# 4. DESKTOP INSTALLATION

if [ "$ARCH_OS_VARIANT" = "desktop" ]; then

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install GNOME Packages (May take about 12 minutes)"
    # ----------------------------------------------------------------------------------------------------

    # Install packages
    packages=()

    # GNOME base
    packages+=("gnome")                   # GNOME core
    packages+=("gnome-tweaks")            # GNOME tweaks
    packages+=("gnome-browser-connector") # GNOME Extensions browser connector
    packages+=("gnome-themes-extra")      # GNOME themes
    packages+=("gnome-firmware")          # GNOME firmware manager
    packages+=("power-profiles-daemon")   # GNOME power profiles support
    packages+=("fwupd")                   # GNOME security settings
    packages+=("rygel")                   # GNOME media sharing support
    packages+=("cups")                    # GNOME printer support

    # GNOME wayland screensharing, flatpak & pipewire support
    packages+=("xdg-desktop-portal")
    packages+=("xdg-desktop-portal-gtk")
    packages+=("xdg-desktop-portal-gnome")

    # GNOME legacy Indicator support (need for systray) (51 packages)
    packages+=("libappindicator-gtk2")
    packages+=("libappindicator-gtk3")
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-libappindicator-gtk2")
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-libappindicator-gtk3")

    # Audio
    packages+=("pipewire")                                                        # Pipewire
    packages+=("pipewire-alsa")                                                   # Replacement for alsa
    packages+=("pipewire-pulse")                                                  # Replacement for pulse
    packages+=("pipewire-jack")                                                   # Replacement for jack
    packages+=("wireplumber")                                                     # Pipewire session manager
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-pipewire")      # Pipewire 32 bit
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-pipewire-jack") # Replacement for jack 32 bit

    # Networking & Access
    packages+=("samba") # Windows Network Share
    packages+=("gvfs")  # Need for Nautilus
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
    packages+=("dosfstools")
    packages+=("ntfs-3g")
    packages+=("exfat-utils")
    packages+=("p7zip")
    packages+=("zip")
    packages+=("unzip")
    packages+=("unrar")
    packages+=("tar")

    # Codecs
    packages+=("gstreamer")
    packages+=("gst-libav")
    packages+=("gst-plugin-pipewire")
    packages+=("gst-plugins-ugly")
    packages+=("libdvdcss")
    packages+=("libheif")
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-gstreamer")

    # Optimization
    packages+=("gamemode")
    [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-gamemode")

    # Fonts
    packages+=("noto-fonts")
    packages+=("noto-fonts-emoji")
    packages+=("ttf-firacode-nerd")
    packages+=("ttf-liberation")
    packages+=("ttf-dejavu")

    # Driver
    #packages+=("xf86-input-synaptics") # For some legacy touchpads

    # Install packages
    pacman_install "${packages[@]}"

    # Add user to gamemode group
    arch-chroot /mnt gpasswd -a "$ARCH_OS_USERNAME" gamemode

    # ----------------------------------------------------------------------------------------------------

    # VM Guest support (if VM detected)
    if [ "$ARCH_OS_VM_SUPPORT_ENABLED" = "true" ]; then

        # Set detected VM (need return true in case of native machine)
        hypervisor=$(systemd-detect-virt) || true

        case $hypervisor in

        kvm)
            print_whiptail_info "KVM has been detected, setting up guest tools."
            pacman_install spice spice-vdagent spice-protocol spice-gtk qemu-guest-agent
            arch-chroot /mnt systemctl enable qemu-guest-agent
            ;;

        vmware)
            print_whiptail_info "VMWare Workstation/ESXi has been detected, setting up guest tools."
            pacman_install open-vm-tools
            arch-chroot /mnt systemctl enable vmtoolsd
            arch-chroot /mnt systemctl enable vmware-vmblock-fuse
            ;;

        oracle)
            print_whiptail_info "VirtualBox has been detected, setting up guest tools."
            pacman_install virtualbox-guest-utils
            arch-chroot /mnt systemctl enable vboxservice
            ;;

        microsoft)
            print_whiptail_info "Hyper-V has been detected, setting up guest tools."
            pacman_install hyperv
            arch-chroot /mnt systemctl enable hv_fcopy_daemon
            arch-chroot /mnt systemctl enable hv_kvp_daemon
            arch-chroot /mnt systemctl enable hv_vss_daemon
            ;;

        *)
            print_whiptail_info "No VM detected"
            # Do nothing
            ;;

        esac
    fi

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Enable GNOME Auto Login"
    # ----------------------------------------------------------------------------------------------------

    grep -qrnw /mnt/etc/gdm/custom.conf -e "AutomaticLoginEnable" || sed -i "s/^\[security\]/AutomaticLoginEnable=True\nAutomaticLogin=${ARCH_OS_USERNAME}\n\n\[security\]/g" /mnt/etc/gdm/custom.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Configure Git"
    # ----------------------------------------------------------------------------------------------------

    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- mkdir -p "/home/${ARCH_OS_USERNAME}/.config/git"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- touch "/home/${ARCH_OS_USERNAME}/.config/git/config"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- git config --global credential.helper /usr/lib/git-core/git-credential-libsecret

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
    print_whiptail_info "Set X11 Keyboard Layout"
    # ----------------------------------------------------------------------------------------------------

    {
        echo 'Section "InputClass"'
        echo '    Identifier "system-keyboard"'
        echo '    MatchIsKeyboard "yes"'
        echo '    Option "XkbLayout" "'"${ARCH_OS_X11_KEYBOARD_LAYOUT}"'"'
        echo '    Option "XkbModel" "'"${ARCH_OS_X11_KEYBOARD_MODEL}"'"'
        echo '    Option "XkbVariant" "'"${ARCH_OS_X11_KEYBOARD_VARIANT}"'"'
        echo 'EndSection'
    } >/mnt/etc/X11/xorg.conf.d/00-keyboard.conf

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Enable Arch OS Desktop Services"
    # ----------------------------------------------------------------------------------------------------

    arch-chroot /mnt systemctl enable gdm.service                                                              # GNOME
    arch-chroot /mnt systemctl enable bluetooth.service                                                        # Bluetooth
    arch-chroot /mnt systemctl enable avahi-daemon                                                             # Network browsing service
    arch-chroot /mnt systemctl enable cups.socket                                                              # Printer
    arch-chroot /mnt systemctl enable smb.service                                                              # Samba
    arch-chroot /mnt systemctl enable nmb.service                                                              # Samba
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user pipewire.service       # Pipewire
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user pipewire-pulse.service # Pipewire
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- systemctl enable --user wireplumber.service    # Pipewire

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Hide Applications Icons"
    # ----------------------------------------------------------------------------------------------------

    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- mkdir -p "/home/$ARCH_OS_USERNAME/.local/share/applications"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/avahi-discover.desktop"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/bssh.desktop"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/bvnc.desktop"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/qv4l2.desktop"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/qvidcap.desktop"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/lstopo.desktop"
    arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/cups.desktop"

    # Hide Shell Enhancement Apps
    if [ "$ARCH_OS_SHELL_ENHANCED_ENABLED" = "true" ]; then
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/fish.desktop"
        arch-chroot /mnt /usr/bin/runuser -u "$ARCH_OS_USERNAME" -- echo -e '[Desktop Entry]\nType=Application\nHidden=true' >"/mnt/home/$ARCH_OS_USERNAME/.local/share/applications/btop.desktop"
    fi

    # ----------------------------------------------------------------------------------------------------
    print_whiptail_info "Install Graphics Driver"
    # ----------------------------------------------------------------------------------------------------

    case "${ARCH_OS_GRAPHICS_DRIVER}" in

    "mesa") # https://wiki.archlinux.org/title/OpenGL#Installation
        packages=()
        packages+=("mesa")
        packages+=("mesa-utils")
        packages+=("vkd3d")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-mesa")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-mesa-utils")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vkd3d")
        pacman_install "${packages[@]}"
        ;;

    "intel_i915") # https://wiki.archlinux.org/title/Intel_graphics#Installation
        packages=()
        packages+=("vulkan-intel")
        packages+=("vkd3d")
        packages+=("libva-intel-driver")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vulkan-intel")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vkd3d")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-libva-intel-driver")
        pacman_install "${packages[@]}"
        sed -i "s/^MODULES=(.*)/MODULES=(i915)/g" /mnt/etc/mkinitcpio.conf
        arch-chroot /mnt mkinitcpio -P
        ;;

    "nvidia") # https://wiki.archlinux.org/title/NVIDIA#Installation
        packages=()
        packages+=("${ARCH_OS_KERNEL}-headers")
        packages+=("nvidia-dkms")
        packages+=("nvidia-settings")
        packages+=("nvidia-utils")
        packages+=("opencl-nvidia")
        packages+=("vkd3d")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-nvidia-utils")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-opencl-nvidia")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vkd3d")
        pacman_install "${packages[@]}"
        # https://wiki.archlinux.org/title/NVIDIA#DRM_kernel_mode_setting
        # Alternative (slow boot, bios logo twice, but correct plymouth resolution):
        #sed -i "s/nowatchdog quiet/nowatchdog nvidia_drm.modeset=1 nvidia_drm.fbdev=1 quiet/g" /mnt/boot/loader/entries/arch.conf
        mkdir -p /mnt/etc/modprobe.d/ && echo -e 'options nvidia_drm modeset=1 fbdev=1' >/mnt/etc/modprobe.d/nvidia.conf
        sed -i "s/^MODULES=(.*)/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/g" /mnt/etc/mkinitcpio.conf
        # https://wiki.archlinux.org/title/NVIDIA#pacman_hook
        mkdir -p /mnt/etc/pacman.d/hooks/
        {
            echo "[Trigger]"
            echo "Operation=Install"
            echo "Operation=Upgrade"
            echo "Operation=Remove"
            echo "Type=Package"
            echo "Target=nvidia"
            echo "Target=${ARCH_OS_KERNEL}"
            echo "# Change the linux part above if a different kernel is used"
            echo ""
            echo "[Action]"
            echo "Description=Update NVIDIA module in initcpio"
            echo "Depends=mkinitcpio"
            echo "When=PostTransaction"
            echo "NeedsTargets"
            echo "Exec=/bin/sh -c 'while read -r trg; do case \$trg in linux*) exit 0; esac; done; /usr/bin/mkinitcpio -P'"
        } >/mnt/etc/pacman.d/hooks/nvidia.hook
        # Enable Wayland Support (https://wiki.archlinux.org/title/GDM#Wayland_and_the_proprietary_NVIDIA_driver)
        [ ! -f /mnt/etc/udev/rules.d/61-gdm.rules ] && mkdir -p /mnt/etc/udev/rules.d/ && ln -s /dev/null /mnt/etc/udev/rules.d/61-gdm.rules
        # Rebuild initial ram disk
        arch-chroot /mnt mkinitcpio -P
        ;;

    "amd") # https://wiki.archlinux.org/title/AMDGPU#Installation
        packages=()
        packages+=("xf86-video-amdgpu")
        packages+=("libva-mesa-driver")
        packages+=("vulkan-radeon")
        packages+=("mesa-vdpau")
        packages+=("vkd3d")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-libva-mesa-driver")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vulkan-radeon")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-mesa-vdpau")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vkd3d")
        pacman_install "${packages[@]}"
        # Must be discussed: https://wiki.archlinux.org/title/AMDGPU#Disable_loading_radeon_completely_at_boot
        sed -i "s/^MODULES=(.*)/MODULES=(amdgpu radeon)/g" /mnt/etc/mkinitcpio.conf
        arch-chroot /mnt mkinitcpio -P
        ;;

    "ati") # https://wiki.archlinux.org/title/ATI#Installation
        packages=()
        packages+=("xf86-video-ati")
        packages+=("libva-mesa-driver")
        packages+=("mesa-vdpau")
        packages+=("vkd3d")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-libva-mesa-driver")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-mesa-vdpau")
        [ "$ARCH_OS_MULTILIB_ENABLED" = "true" ] && packages+=("lib32-vkd3d")
        pacman_install "${packages[@]}"
        sed -i "s/^MODULES=(.*)/MODULES=(radeon)/g" /mnt/etc/mkinitcpio.conf
        arch-chroot /mnt mkinitcpio -P
        ;;

    esac

# ----------------------------------------------------------------------------------------------------
# END ARCH OS DESKTOP
# ----------------------------------------------------------------------------------------------------

fi

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Cleanup Arch OS Installation"
# ----------------------------------------------------------------------------------------------------

# Copy installer.conf to users home dir
cp "$SCRIPT_CONF" "/mnt/home/${ARCH_OS_USERNAME}/installer.conf"

# Remove sudo needs no password rights
sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /mnt/etc/sudoers

# Set home permission
arch-chroot /mnt chown -R "$ARCH_OS_USERNAME":"$ARCH_OS_USERNAME" "/home/${ARCH_OS_USERNAME}"

# Remove orphans and force return true
# shellcheck disable=SC2016
arch-chroot /mnt bash -c 'pacman -Qtd &>/dev/null && pacman -Rns --noconfirm $(pacman -Qtdq) || true'

# ----------------------------------------------------------------------------------------------------
print_whiptail_info "Arch OS Installation finished"
# ----------------------------------------------------------------------------------------------------
