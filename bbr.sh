#!/usr/bin/env bash
#
# Auto install latest kernel for TCP BBR
#
# System Required:  CentOS 6+, Debian7+, Ubuntu12+
#
# Copyright (C) 2016 Teddysun <i@teddysun.com>
#
# URL: https://teddysun.com/489.html
#

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

[[ $EUID -ne 0 ]] && echo -e "${red}Error:${plain} This script must be run as root!" && exit 1

[[ -d "/proc/vz" ]] && echo -e "${red}Error:${plain} Your VPS is based on OpenVZ, not be supported." && exit 1

if [ -f /etc/redhat-release ]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
    release="centos"
fi

if [[ `getconf WORD_BIT` == "32" && `getconf LONG_BIT` == "64" ]]; then
    deb_kernel_url="http://kernel.ubuntu.com/~kernel-ppa/mainline/v4.9.1/linux-image-4.9.1-040901-generic_4.9.1-040901.201701060531_amd64.deb"
    deb_kernel_name="linux-image-4.9.1-amd64.deb"
else
    deb_kernel_url="http://kernel.ubuntu.com/~kernel-ppa/mainline/v4.9.1/linux-image-4.9.1-040901-generic_4.9.1-040901.201701060531_i386.deb"
    deb_kernel_name="linux-image-4.9.1-i386.deb"
fi

get_opsy() {
    [ -f /etc/redhat-release ] && awk '{print ($1,$3~/^[0-9]/?$3:$4)}' /etc/redhat-release && return
    [ -f /etc/os-release ] && awk -F'[= "]' '/PRETTY_NAME/{print $3,$4,$5}' /etc/os-release && return
    [ -f /etc/lsb-release ] && awk -F'[="]+' '/DESCRIPTION/{print $2}' /etc/lsb-release && return
}

opsy=$( get_opsy )
arch=$( uname -m )
lbit=$( getconf LONG_BIT )
kern=$( uname -r )

get_char() {
    SAVEDSTTY=`stty -g`
    stty -echo
    stty cbreak
    dd if=/dev/tty bs=1 count=1 2> /dev/null
    stty -raw
    stty echo
    stty $SAVEDSTTY
}

getversion() {
    if [[ -s /etc/redhat-release ]]; then
        grep -oE  "[0-9.]+" /etc/redhat-release
    else
        grep -oE  "[0-9.]+" /etc/issue
    fi
}

centosversion() {
    if [ "${release}" == "centos" ]; then
        local code=$1
        local version="$(getversion)"
        local main_ver=${version%%.*}
        if [ "$main_ver" == "$code" ]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

check_bbr_status() {
    local param=$(sysctl net.ipv4.tcp_available_congestion_control | awk '{print $3}')
    if uname -r | grep -Eqi "4.9."; then
        if [[ "${param}" == "bbr" ]]; then
            return 0
        else
            return 1
        fi
    else
        return 1
    fi
}

install_elrepo() {
    rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
    if centosversion 5; then
        echo -e "${red}Error:${plain} not supported CentOS 5."
        exit 1
    elif centosversion 6; then
        rpm -Uvh http://www.elrepo.org/elrepo-release-6-6.el6.elrepo.noarch.rpm
    elif centosversion 7; then
        rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm
    fi

    if [ ! -f /etc/yum.repos.d/elrepo.repo ]; then
        echo -e "${red}Error:${plain} Install ELRepo failed, please check it."
        exit 1
    fi
}

install_config() {
    if [[ "${release}" == "centos" ]]; then
        if centosversion 6; then
            if [ ! -f "/boot/grub/grub.conf" ]; then
                echo -e "${red}Error:${plain} /boot/grub/grub.conf not found, please check it."
                exit 1
            fi
            sed -i 's/^default=.*/default=0/g' /boot/grub/grub.conf
        elif centosversion 7; then
            if [ ! -f "/boot/grub2/grub.cfg" ]; then
                echo -e "${red}Error:${plain} /boot/grub2/grub.cfg not found, please check it."
                exit 1
            fi
            grub2-set-default 0
        fi
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        /usr/sbin/update-grub
    fi

    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
    echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
}

install_bbr() {
    check_bbr_status
    if [ $? -eq 0 ]; then
        echo
        echo -e "${green}Info:${plain} TCP BBR has been successfully installed. nothing to do..."
        exit
    fi

    if [[ "${release}" == "centos" ]]; then
        install_elrepo
        yum --enablerepo=elrepo-kernel -y install kernel-ml
        if [ $? -ne 0 ]; then
            echo -e "${red}Error:${plain} Install latest kernel failed, please check it."
            exit 1
        fi
    elif [[ "${release}" == "debian" || "${release}" == "ubuntu" ]]; then
        [[ ! -e "/usr/bin/wget" ]] && apt-get -y update && apt-get -y install wget
        wget -c -t3 -T60 -O ${deb_kernel_name} ${deb_kernel_url}
        if [ $? -ne 0 ]; then
            echo -e "${red}Error:${plain} Download ${deb_kernel_name} failed, please check it."
            exit 1
        fi
        dpkg -i ${deb_kernel_name}
        rm -f ${deb_kernel_name}
    else
        echo -e "${red}Error:${plain} OS is not be supported, please change to CentOS/Debian/Ubuntu and try again."
        exit 1
    fi

    install_config
}

clear
echo "---------- System Information ----------"
echo " OS      : $opsy"
echo " Arch    : $arch ($lbit Bit)"
echo " Kernel  : $kern"
echo "----------------------------------------"
echo " Auto install latest kernel for TCP BBR"
echo
echo " URL: https://teddysun.com/489.html"
echo "----------------------------------------"
echo
echo "Press any key to start...or Press Ctrl+C to cancel"
char=`get_char`

install_bbr

echo
read -p "Info: The system needs to be restart. Do you want to reboot? [y/n]" is_reboot
if [[ ${is_reboot} == "y" || ${is_reboot} == "Y" ]]; then
    reboot
else
    exit
fi
