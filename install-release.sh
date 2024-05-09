#!/usr/bin/env bash

set -euxo pipefail

# Identify architecture
case "$(arch -s)" in
    'i386' | 'i686')
        MACHINE='32'
        ;;
    'amd64' | 'x86_64')
        MACHINE='64'
        ;;
    'armv5tel')
        MACHINE='arm32-v5'
        ;;
    'armv6l')
        MACHINE='arm32-v6'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
        ;;
    'armv7' | 'armv7l')
        MACHINE='arm32-v7a'
        grep Features /proc/cpuinfo | grep -qw 'vfp' || MACHINE='arm32-v5'
        ;;
    'armv8' | 'aarch64')
        MACHINE='arm64-v8a'
        ;;
    'mips')
        MACHINE='mips32'
        ;;
    'mipsle')
        MACHINE='mips32le'
        ;;
    'mips64')
        MACHINE='mips64'
        ;;
    'mips64le')
        MACHINE='mips64le'
        ;;
    'ppc64')
        MACHINE='ppc64'
        ;;
    'ppc64le')
        MACHINE='ppc64le'
        ;;
    'riscv64')
        MACHINE='riscv64'
        ;;
    's390x')
        MACHINE='s390x'
        ;;
    *)
        echo "error: The architecture is not supported."
        exit 1
        ;;
esac

TMP_DIRECTORY="$(mktemp -d)/"
ZIP_FILE="${TMP_DIRECTORY}Xray-linux-$MACHINE.zip"
DOWNLOAD_LINK="https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-$MACHINE.zip"

install_software() {
    if [[ -n "$(command -v curl)" ]]; then
        return
    fi
    if [[ -n "$(command -v unzip)" ]]; then
        return
    fi
    if [ "$(command -v apk)" ]; then
        apk add curl unzip
    else
        echo "error: The script does not support the package manager in this operating system."
        exit 1
    fi
}

download_xray() {
    curl -L -H 'Cache-Control: no-cache' -o "$ZIP_FILE" "$DOWNLOAD_LINK" -#
    if [ "$?" -ne '0' ]; then
        echo 'error: Download failed! Please check your network or try again.'
        exit 1
    fi
    curl -L -H 'Cache-Control: no-cache' -o "$ZIP_FILE.dgst" "$DOWNLOAD_LINK.dgst" -#
    if [ "$?" -ne '0' ]; then
        echo 'error: Download failed! Please check your network or try again.'
        exit 1
    fi
}

verification_xray() {
  CHECKSUM=$(cat "$ZIP_FILE".dgst | awk -F '= ' '/256=/ {print $2}')
  LOCALSUM=$(sha256sum "$ZIP_FILE" | awk '{printf $1}')
  if [[ "$CHECKSUM" != "$LOCALSUM" ]]; then
    echo 'error: SHA256 check failed! Please check your network or try again.'
    return 1
  fi
}

decompression() {
    unzip -q "$ZIP_FILE" -d "$TMP_DIRECTORY"
}

is_it_running() {
    XRAY_RUNNING='0'
    if [ -n "$(pgrep xray)" ]; then
        rc-service xray stop
        XRAY_RUNNING='1'
    fi
}

install_xray() {
    install -m 755 "${TMP_DIRECTORY}xray" "/usr/local/bin/xray"
    install -d /usr/local/lib/xray/
    install -m 755 "${TMP_DIRECTORY}geoip.dat" "/usr/local/lib/xray/geoip.dat"
    install -m 755 "${TMP_DIRECTORY}geosite.dat" "/usr/local/lib/xray/geosite.dat"
}

install_confdir() {
    CONFDIR='0'
    if [ ! -d '/usr/local/etc/xray/' ]; then
        install -d /usr/local/etc/xray/
        echo '{}' > "/usr/local/etc/xray/config.json"
        CONFDIR='1'
    fi
}

install_log() {
    LOG='0'
    if [ ! -d '/var/log/xray/' ]; then
        install -d -o nobody -g nobody /var/log/xray/
        install -m 600 -o nobody -g nobody /dev/null /var/log/xray/access.log
        install -m 600 -o nobody -g nobody /dev/null /var/log/xray/error.log
        LOG='1'
    fi
}

install_startup_service_file() {
    OPENRC='0'
    if [ ! -f '/etc/init.d/xray' ]; then
        mkdir "${TMP_DIRECTORY}init.d/"
        curl -o "${TMP_DIRECTORY}init.d/xray" https://raw.githubusercontent.com/XTLS/alpinelinux-install-xray/main/init.d/xray -s
        if [ "$?" -ne '0' ]; then
            echo 'error: Failed to start service file download! Please check your network or try again.'
            exit 1
        fi
        install -m 755 "${TMP_DIRECTORY}init.d/xray" /etc/init.d/xray
        OPENRC='1'
    fi
}

information() {
    echo 'installed: /usr/local/bin/xray'
    echo 'installed: /usr/local/lib/xray/geoip.dat'
    echo 'installed: /usr/local/lib/xray/geosite.dat'
    if [ "$CONFDIR" -eq '1' ]; then
        echo 'installed: /usr/local/etc/xray/config.json'
    fi
    if [ "$LOG" -eq '1' ]; then
        echo 'installed: /var/log/xray/'
    fi
    if [ "$OPENRC" -eq '1' ]; then
        echo 'installed: /etc/init.d/xray'
    fi
    rm -r "$TMP_DIRECTORY"
    echo "removed: $TMP_DIRECTORY"
    echo "You may need to execute a command to remove dependent software: apk del curl unzip"
    if [ "$XRAY_RUNNING" -eq '1' ]; then
        rc-service xray start
    else
        echo 'Please execute the command: rc-update add xray; rc-service xray start'
    fi
    echo "info: Xray is installed."
}

main() {
    install_software
    install_software
    download_xray
    verification_xray
    decompression
    is_it_running
    install_xray
    install_confdir
    install_log
    install_startup_service_file
    information
}

main
