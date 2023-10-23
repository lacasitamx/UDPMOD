#!/bin/bash

red() {
    echo -e "\033[31m\033[01m$1\033[0m"
}

green() {
    echo -e "\033[32m\033[01m$1\033[0m"
}

yellow() {
    echo -e "\033[33m\033[01m$1\033[0m"
}
PASSWORD=""
RED="\033[31m"      # Error message
GREEN="\033[32m"    # Success message
YELLOW="\033[33m"   # Warning message
BLUE="\033[36m"     # Info message
PLAIN='\033[0m'

# 判断系统及定义系统安装依赖方式
REGEX=("debian" "ubuntu" "centos|red hat|kernel|oracle linux|alma|rocky" "'amazon linux'")
RELEASE=("Debian" "Ubuntu" "CentOS" "CentOS")
PACKAGE_UPDATE=("apt -y update" "apt -y update" "yum -y update" "yum -y update")
PACKAGE_INSTALL=("apt -y install" "apt -y install" "yum -y install" "yum -y install")
PACKAGE_REMOVE=("apt -y remove" "apt -y remove" "yum -y remove" "yum -y remove")
PACKAGE_UNINSTALL=("apt -y autoremove" "apt -y autoremove" "yum -y autoremove" "yum -y autoremove")

[[ $EUID -ne 0 ]] && red "PARA USAR ESTE SCRIPT ES NECESARIO ESTAR EN MODO ROOT" && exit 1

CMD=("$(grep -i pretty_name /etc/os-release 2>/dev/null | cut -d \" -f2)" "$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)" "$(lsb_release -sd 2>/dev/null)" "$(grep -i description /etc/lsb-release 2>/dev/null | cut -d \" -f2)" "$(grep . /etc/redhat-release 2>/dev/null)" "$(grep . /etc/issue 2>/dev/null | cut -d \\ -f1 | sed '/^[ ]*$/d')") 

for i in "${CMD[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done

for ((int = 0; int < ${#REGEX[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${REGEX[int]} ]] && SYSTEM="${RELEASE[int]}" && [[ -n $SYSTEM ]] && break
done

IP=$(curl -s6m8 ip.sb) || IP=$(curl -s4m8 ip.sb)

if [[ -n $(echo $IP | grep ":") ]]; then
    IP="[$IP]"
fi

check_tun(){
    TUN=$(cat /dev/net/tun 2>&1 | tr '[:upper:]' '[:lower:]')
    if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ 'estado erronea' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then
        if [[ $vpsvirt == "openvz" ]]; then
            wget -N --no-check-certificate https://raw.githubusercontents.com/Misaka-blog/tun-script/master/tun.sh && bash tun.sh
        else
            red "Se detecta que el módulo TUN no está encendido, por favor diríjase al panel de control del VPS para encenderlo." 
            exit 1
        fi
    fi
}

checkCentOS8(){
    if [[ -n $(cat /etc/os-release | grep "CentOS Linux 8") ]]; then
        yellow "检测到当前VPS系统为CentOS 8，是否升级为CentOS Stream 8以确保软件包正常安装？"
        read -p "请输入选项 [y/n]：" comfirmCentOSStream
        if [[ $comfirmCentOSStream == "y" ]]; then
            yellow "正在为你升级到CentOS Stream 8，大概需要10-30分钟的时间"
            sleep 1
            sed -i -e "s|releasever|releasever-stream|g" /etc/yum.repos.d/CentOS-*
            yum clean all && yum makecache
            dnf swap centos-linux-repos centos-stream-repos distro-sync -y
        else
            red "已取消升级过程，脚本即将退出！"
            exit 1
        fi
    fi
}

archAffix(){
    case "$(uname -m)" in
        i686 | i386) echo '386' ;;
        x86_64 | amd64) echo 'amd64' ;;
        armv5tel) echo 'arm-5' ;;
        armv7 | armv7l) echo 'arm-7' ;;
        armv8 | aarch64) echo 'arm64' ;;
        s390x) echo 's390x' ;;
        *) red " 不支持的CPU架构！" && exit 1 ;;
    esac
    return 0
}

install_base() {
    if [[ $SYSTEM != "CentOS" ]]; then
        ${PACKAGE_UPDATE[int]}
    fi
    ${PACKAGE_INSTALL[int]} wget curl sudo
}

downloadHysteria() {
    rm -rf /root/Hysteria
    mkdir /root/Hysteria
    last_version=$(curl -Ls "https://api.github.com/repos/HyNetwork/Hysteria/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    if [[ ! -n "$last_version" ]]; then
        red "No se pudo detectar la versión de Hysteria. Es posible que se haya excedido el límite de la API de Github. Vuelve a intentarlo más tarde."
        exit 1
    fi
    yellow "Se detectó la última versión de Hysteria: ${last_version}, inicia la instalación"
    wget -N --no-check-certificate https://github.com/HyNetwork/Hysteria/releases/download/${last_version}/hysteria-linux-$(archAffix) -O /usr/bin/hysteria
    if [[ $? -ne 0 ]]; then
        red "No se pudo descargar Hysteria, asegúrese de que su servidor pueda conectarse y descargar archivos Github"
        exit 1
    fi
    chmod +x /usr/bin/hysteria
}

makeConfig() {
    read -p "Ingrese el puerto de conexión (predeterminado: 36712)：" PORT
    [[ -z $PORT ]] && PORT=36712
    read -p "Ingrese la contraseña de ofuscación de conexión (generada aleatoriamente de forma predeterminada)：" OBFS
    [[ -z $OBFS ]] && OBFS=$(date +%s%N | md5sum | cut -c 1-32)
    
    openssl ecparam -genkey -name prime256v1 -out /root/Hysteria/private.key
    openssl req -new -x509 -days 36500 -key /root/Hysteria/private.key -out /root/Hysteria/cert.crt -subj "/CN=www.bilibili.com"
    cat <<EOF > /root/Hysteria/server.json
{
    "listen": ":$PORT",
    "cert": "/root/Hysteria/cert.crt",
    "key": "/root/Hysteria/private.key",
    "up": "50 Mbps",
  "up_mbps": 100,
  "down": "50 Mbps",
  "down_mbps": 100,
  "disable_udp": false,
  "obfs": "$OBFS",
    "auth": {
	"mode": "system",
	"config": ["$PASSWORD"]
         }
    

}
EOF
    cat <<EOF > /root/Hysteria/client.json
{
    "server": "$IP:$PORT",
    "obfs": "$OBFS",
    "up_mbps": "100 Mbps" ,
    "down_mbps": "100 Mbps",
    "insecure": true,
    "socks5": {
        "listen": "127.0.0.1:1080"
    },
    "http": {
        "listen": "127.0.0.1:1081"
    }
}
EOF
    cat <<'TEXT' > /etc/systemd/system/hysteria.service
[Unit]
Description=Hysiteria Server
After=network.target

[Install]
WantedBy=multi-user.target

[Service]
Type=simple
WorkingDirectory=/root/Hysteria
ExecStart=/usr/bin/hysteria --config /root/Hysteria/server.json server
Restart=always
TEXT
}

installBBR() {
    result=$(lsmod | grep bbr)
    if [[ $result != "" ]]; then
        green "El módulo BBR está instalado"
        INSTALL_BBR=false
        return
    fi
    res=`systemd-detect-virt`
    if [[ $res =~ openvz|lxc ]]; then
        colorEcho $BLUE "由于你的VPS为OpenVZ或LXC架构的VPS，跳过安装"
        INSTALL_BBR=false
        return
    fi
    
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p
    result=$(lsmod | grep bbr)
    if [[ "$result" != "" ]]; then
        green "El módulo BBR está habilitado"
        INSTALL_BBR=false
        return
    fi

    green "instalando bbr..."
    if [[ $SYSTEM = "CentOS" ]]; then
            rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
            rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-4.el7.elrepo.noarch.rpm
            ${PACKAGE_INSTALL[int]} --enablerepo=elrepo-kernel kernel-ml
            ${PACKAGE_REMOVE[int]} kernel-3.*
            grub2-set-default 0
            echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
            INSTALL_BBR=true
    else
        ${PACKAGE_INSTALL[int]} --install-recommends linux-generic-hwe-16.04
        grub-set-default 0
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
        INSTALL_BBR=true
    fi
}

check_status(){
    if [[ -n $(service hysteria status 2>/dev/null | grep "inactive") ]]; then
        status="${RED}DESACTIVADO！${PLAIN}"
    elif [[ -n $(service hysteria status 2>/dev/null | grep "active") ]]; then
        status="${GREEN}ACTIVO！${PLAIN}"
    else
        status="${RED}No Instalado！${PLAIN}"
    fi
}
#installHysteria() {
    checkCentOS8
    install_base
    downloadHysteria
    installBBR
    makeConfig
    systemctl enable hysteria
    systemctl start hysteria
    check_status
    if [[ -n $(service hysteria status 2>/dev/null | grep "inactive") ]]; then
        red "Hysteria no instalado"
    elif [[ -n $(service hysteria status 2>/dev/null | grep "active") ]]; then
        green "Hysteria Instalado"
        yellow "CONFIG /root/Hysteria/server.json"
        yellow "CONFIG /root/Hysteria/client.json"
    fi
#}
