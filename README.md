# Attention: all development has moved to Gitlab: https://gitlab.manjaro.org/applications/manjaro-architect

# manjaro-architect
CLI net-installer for Manjarolinux, forked from Carl Duff's Architect

This installer provides netinstallation for different manjaro editions. It sources the iso-profiles git repo, so it should be always up to date. 

**menu overview of v0.9.9:**

```
Main Menu
|
├── Prepare Installation
|   ├── Set Virtual Console
|   ├── List Devices
|   ├── Partition Disk
|   ├── LUKS Encryption
|   ├── Logical Volume Management
|   ├── Mount Partitions
|   ├── Configure Installer Mirrorlist
|   |   ├── Edit Pacman Configuration
|   |   ├── Edit Pacman Mirror Configuration
|   |   └── Rank Mirrors by Speed
|   |
│   └── Refresh Pacman Keys
|
├── Install Desktop System
│   ├── Install Manjaro Desktop
│   ├── Install Bootloader
│   ├── Configure Base
|   │   ├── Generate FSTAB
|   │   ├── Set Hostname
|   │   ├── Set System Locale
|   │   ├── Set Desktop Keyboard Layout
|   │   ├── Set Timezone and Clock
|   │   ├── Set Root Password
|   │   └── Add New User(s)
|   │
│   ├── System Tweaks
|   │   ├── Enable Automatic Login
|   │   ├── Enable Hibernation
|   │   ├── Performance
|   |   │   ├── I/O schedulers
|   |   │   ├── Swap configuration
|   |   │   └── Preload
|   |   │
|   │   ├── Security and systemd Tweaks
|   |   │   ├── Amend journald Logging
|   |   │   ├── Disable Coredump Logging
|   |   │   └── Restrict Access to Kernel Logs
|   |   │
|   │   └── Restrict Access to Kernel Logs
|   │
│   ├── Review Configuration Files
│   └── Chroot into Installation
|
├── Install CLI System
│   ├── Install Base Packages
│   ├── Install Bootloader
│   ├── Configure Base
|   │   ├── Generate FSTAB
|   │   ├── Set Hostname
|   │   ├── Set System Locale
|   │   ├── Set Timezone and Clock
|   │   ├── Set Root Password
|   │   └── Add New User(s)
|   │
│   ├── Install Custom Packages
│   ├── System tweaks
|   │   └── ... (see 'Install Desktop System')
|   │
│   ├── Review Configuration Files
│   └── Chroot into Installation
|
├── Install Custom System
│   ├── Install Base Packages
│   ├── Install Unconfigured Desktop Environments
|   │   ├── Install Display Server
|   │   ├── Install Desktop Environment
|   │   ├── Install Display Manager
|   │   ├── Install Networking Capabilities
|   │   |   ├── Display Wireless Devices
|   │   |   ├── Install Wireless Device Packages
|   │   |   ├── Install Network Connection Manager
|   │   |   └── Install CUPS / Printer Packages
|   │   |
|   │   └── Install Multimedia Support
|   │       ├── Install Sound Driver(s)
|   │       ├── Install Codecs
|   │       └── Accessibility Packages
|   │
│   ├── Install Bootloader
│   ├── Configure Base
|   |   └── ... (see 'Install Desktop System')
|   │
│   ├── Install Custom Packages
│   ├── System Tweaks
|   |   └── ... (see 'Install Desktop System')
|   │
│   ├── Review Configuration Files
│   └── Chroot into Installation
|
└── System Rescue
    ├── Install Hardware Drivers
    │   ├── Install Display Drivers
    │   └── Install Network Drivers
    |
    ├── Install Bootloader
    ├── Configure Base
    |   └── ... (see 'Install Desktop System')
    │
    ├── Install Custom Packages
    ├── Remove Packages
    ├── Review Configuration Files
    ├── Chroot into Installation
    ├── Data Recovery
    │   ├── Clonezilla
    │   └── Photorec
    │
    └── View System Logs
        ├── Dmesg
        ├── Pacman log
        ├── Xorg log
        └── Journalctl
```
