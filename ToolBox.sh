#!/bin/bash

#================================================================
#   SYSTEM      : Linux
#   DESCRIPTION : Linux 系统全能工具箱脚本
#   AUTHOR      : Gemini
#   CREATED     : 2025-07-22
#================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本环境初始化
# -------------------------------------------------------------
# 检查root权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}错误：此脚本必须以root权限运行！${NC}"
   echo -e "请尝试使用 'sudo ./toolbox.sh' 命令运行。"
   exit 1
fi

# 检测包管理器
if command -v apt-get &> /dev/null; then
    PKG_MANAGER="apt-get"
    UPDATE_CMD="update"
    INSTALL_CMD="install -y"
    CLEAN_CMD="autoremove -y && apt-get clean"
elif command -v dnf &> /dev/null; then
    PKG_MANAGER="dnf"
    UPDATE_CMD="update -y"
    INSTALL_CMD="install -y"
    CLEAN_CMD="autoremove -y && dnf clean all"
elif command -v yum &> /dev/null; then
    PKG_MANAGER="yum"
    UPDATE_CMD="update -y"
    INSTALL_CMD="install -y"
    CLEAN_CMD="autoremove -y && yum clean all"
else
    echo -e "${RED}错误: 未检测到支持的包管理器 (apt, dnf, yum).${NC}"
    exit 1
fi
# -------------------------------------------------------------

# --- 功能函数定义 ---

function system_info() {
    echo -e "${BLUE}=== 系统信息汇总 ===${NC}"

    # 系统基本信息
    echo -e "${YELLOW}系统版本:${NC} $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '"')"
    echo -e "${YELLOW}内核版本:${NC} $(uname -r)"
    echo -e "${YELLOW}主机名:${NC} $(hostname)"
    echo -e "${YELLOW}架构:${NC} $(uname -m)"
    echo -e "${YELLOW}运行时间:${NC} $(uptime -p)"
    echo -e "${YELLOW}负载:${NC} $(uptime | awk -F'load average:' '{print $2}' | sed 's/^ //')"

    # CPU 信息
    echo -e "\n${YELLOW}CPU 信息:${NC}"
    echo -e "  型号: $(lscpu | grep 'Model name:' | cut -d: -f2 | sed 's/^ *//')"
    echo -e "  核心数: $(nproc)"
    echo -e "  使用率: $(top -bn1 | grep '%Cpu(s)' | awk '{print 100 - $8"% idle"}')"

    # 内存信息
    echo -e "\n${YELLOW}内存信息:${NC}"
    free -h | awk 'NR==1 {print "  " $0} NR==2 {print "  " $0}'

    # 磁盘信息
    echo -e "\n${YELLOW}磁盘信息:${NC}"
    df -h | awk 'NR==1 {print "  " $0} NR>1 && $NF=="/" {print "  " $0}'

    # 网络信息
    echo -e "\n${YELLOW}网络信息:${NC}"
    echo -e "  IP 地址: $(ip addr show | grep -o 'inet [0-9.]\+' | awk '{print $2}' | paste -sd ', ')"
    echo -e "  DNS 配置: $(cat /etc/resolv.conf | grep nameserver | awk '{print $2}' | paste -sd ', ')"
    echo -e "  网络接口: $(ip link show | grep -o '^[0-9]: [^:]\+' | cut -d: -f2 | sed 's/^ //')"

    # 进程信息
    echo -e "\n${YELLOW}进程信息:${NC}"
    echo -e "  进程数: $(ps aux | wc -l)"
    echo -e "  前5个高CPU进程:"
    ps aux --sort=-%cpu | head -6 | awk 'NR>1 {print "    " $0}'

    # 其他信息
    echo -e "\n${YELLOW}Swap 信息:${NC} $(free -h | grep Swap)"
    echo -e "${YELLOW}防火墙状态:${NC} $( (command -v ufw && ufw status | grep Status) || (command -v firewall-cmd && firewall-cmd --state) || echo "未检测到防火墙")"
    echo -e "${YELLOW}SSH 端口:${NC} $(grep '^Port ' /etc/ssh/sshd_config | cut -d' ' -f2 || echo "默认22")"
    echo -e "${YELLOW}时区:${NC} $(timedatectl | grep 'Time zone' | cut -d: -f2 | sed 's/^ //')"
    echo -e "${YELLOW}BBR 状态:${NC} $(sysctl net.ipv4.tcp_congestion_control | cut -d= -f2 | sed 's/^ //' || echo "未启用")"

    echo -e "${GREEN}系统信息显示完成！${NC}"
}

function update_system() {
    echo -e "${BLUE}开始更新系统软件包...${NC}"
    $PKG_MANAGER $UPDATE_CMD
    echo -e "${GREEN}系统更新完成！${NC}"
}

function clean_system() {
    echo -e "${BLUE}开始清理系统垃圾文件...${NC}"
    $PKG_MANAGER $CLEAN_CMD
    echo -e "${GREEN}系统清理完成！${NC}"
}

function install_tools() {
    echo -e "${BLUE}开始安装基础工具...${NC}"
    if [ "$PKG_MANAGER" == "yum" ] || [ "$PKG_MANAGER" == "dnf" ]; then
        $PKG_MANAGER $INSTALL_CMD epel-release
    fi
    
    tools="wget sudo tar unzip socat btop nano vim"
    $PKG_MANAGER $INSTALL_CMD $tools
    
    echo -e "${BLUE}正在安装 Docker...${NC}"
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com -o get-docker.sh
        sh get-docker.sh
        rm get-docker.sh
        if [ -n "$SUDO_USER" ]; then
            usermod -aG docker $SUDO_USER
            echo -e "${YELLOW}已将用户 $SUDO_USER 加入 docker 组，请重新登录以生效。${NC}"
        fi
        systemctl start docker
        systemctl enable docker
    else
        echo -e "${YELLOW}Docker 已安装。${NC}"
    fi
    
    echo -e "${GREEN}所有工具安装完成！${NC}"
}

function set_timezone() {
    echo -e "${BLUE}正在设置系统时区为 Asia/Shanghai...${NC}"
    timedatectl set-timezone Asia/Shanghai
    echo -e "${GREEN}时区设置成功！当前系统时间:${NC}"
    date
}

function set_dns() {
    echo -e "${BLUE}请选择您的服务器位置以优化DNS:${NC}"
    echo -e " ${YELLOW}1.${NC} 中国国内 (使用 223.5.5.5, 119.29.29.29)"
    echo -e " ${YELLOW}2.${NC} 海外 (使用 1.1.1.1, 8.8.8.8)"
    echo -e " ${YELLOW}3.${NC} 自定义 DNS (输入主、次 DNS 服务器)"
    read -p "请输入您的选择 [1-3]: " dns_choice

    case $dns_choice in
        1)
            cat > /etc/resolv.conf << EOF
nameserver 223.5.5.5
nameserver 119.29.29.29
EOF
            ;;
        2)
            cat > /etc/resolv.conf << EOF
nameserver 1.1.1.1
nameserver 8.8.8.8
EOF
            ;;
        3)
            read -p "请输入主 DNS 服务器 (e.g., 8.8.8.8): " primary_dns
            read -p "请输入次 DNS 服务器 (e.g., 8.8.4.4): " secondary_dns
            if [[ -z "$primary_dns" || -z "$secondary_dns" ]]; then
                echo -e "${RED}输入无效，操作取消。${NC}"
                return
            fi
            cat > /etc/resolv.conf << EOF
nameserver $primary_dns
nameserver $secondary_dns
EOF
            ;;
        *)
            echo -e "${RED}无效输入，操作取消。${NC}"
            return
            ;;
    esac
    # chattr +i /etc/resolv.conf # 可选：锁定文件防止被覆盖，但可能引起其他问题
    echo -e "${GREEN}DNS设置成功！${NC}"
    echo -e "${YELLOW}注意：某些系统会自动覆盖此设置。如果DNS被重置，请考虑修改网络管理器的配置。${NC}"
}

function enable_bbr() {
    echo -e "${BLUE}开始配置BBR加速...${NC}"
    kernel_version=$(uname -r | cut -d- -f1)
    if [ "$(printf '%s\n' "4.9" "$kernel_version" | sort -V | head -n1)" != "4.9" ]; then
        echo -e "${RED}错误：内核版本(${kernel_version})过低，需要 4.9 或更高版本。${NC}"
        return
    fi
    
    cat > /etc/sysctl.d/98-bbr.conf << EOF
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
EOF

    sysctl --system > /dev/null 2>&1
    if [[ "$(sysctl -n net.ipv4.tcp_congestion_control)" == "bbr" ]]; then
        echo -e "${GREEN}成功！BBR已开启。${NC}"
    else
        echo -e "${RED}错误：BBR开启失败。${NC}"
    fi
}

function set_swap() {
    echo -e "${BLUE}开始设置1GB虚拟内存(Swap)...${NC}"
    if free | awk '/^Swap:/ {exit $2>0?0:1}'; then
        echo -e "${YELLOW}检测到已存在Swap，操作取消。${NC}"
        return
    fi
    fallocate -l 1G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    if ! grep -q "/swapfile" /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    echo -e "${GREEN}1GB虚拟内存创建并挂载成功！${NC}"
    free -h
}

function tune_performance() {
    echo -e "${BLUE}请选择优化模式:${NC}"
    echo -e " ${YELLOW}1.${NC} 高性能优化模式 (最大化性能，优化文件描述符、虚拟内存、网络、缓存、CPU)"
    echo -e " ${YELLOW}2.${NC} 均衡优化模式 (性能与资源消耗平衡，适合日常使用)"
    echo -e " ${YELLOW}3.${NC} 网站优化模式 (优化并发连接、响应速度，适合网站服务器)"
    echo -e " ${YELLOW}4.${NC} 直播优化模式 (优化延迟和传输性能，适合直播推流)"
    echo -e " ${YELLOW}5.${NC} 游戏服优化模式 (优化并发和响应速度，适合游戏服务器)"
    echo -e " ${YELLOW}6.${NC} 还原默认设置 (恢复系统默认配置)"
    echo -e " ${YELLOW}0.${NC} 返回主菜单"
    read -p "请输入您的选择 [0-6]: " mode_choice

    case $mode_choice in
        1)
            echo -e "${BLUE}正在切换到高性能优化模式...${NC}"
            cat > /etc/sysctl.d/99-performance.conf << EOF
# 高性能模式内核参数
fs.file-max = 2097152
fs.nr_open = 2097152
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
net.core.netdev_max_backlog = 65536
net.core.somaxconn = 131072
net.core.wmem_default = 16777216
net.core.rmem_default = 16777216
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_max_syn_backlog = 32768
net.ipv4.tcp_max_tw_buckets = 8000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_low_latency = 1
EOF
            if ! grep -q "* soft nofile 2097152" /etc/security/limits.conf; then
                echo "* soft nofile 2097152" >> /etc/security/limits.conf
                echo "* hard nofile 2097152" >> /etc/security/limits.conf
            fi
            sysctl --system > /dev/null 2>&1
            echo -e "${GREEN}高性能优化模式设置完成！${NC}"
            echo -e "${YELLOW}部分参数需要重新登录或重启系统才能完全生效。${NC}"
            ;;
        2)
            echo -e "${BLUE}正在切换到均衡优化模式...${NC}"
            cat > /etc/sysctl.d/99-performance.conf << EOF
# 均衡优化模式内核参数
fs.file-max = 524288
fs.nr_open = 524288
vm.swappiness = 30
vm.dirty_ratio = 20
vm.dirty_background_ratio = 10
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 32768
net.core.wmem_default = 8388608
net.core.rmem_default = 8388608
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_syncookies = 1
EOF
            if ! grep -q "* soft nofile 524288" /etc/security/limits.conf; then
                echo "* soft nofile 524288" >> /etc/security/limits.conf
                echo "* hard nofile 524288" >> /etc/security/limits.conf
            fi
            sysctl --system > /dev/null 2>&1
            echo -e "${GREEN}均衡优化模式设置完成！${NC}"
            echo -e "${YELLOW}部分参数需要重新登录或重启系统才能完全生效。${NC}"
            ;;
        3)
            echo -e "${BLUE}正在切换到网站优化模式...${NC}"
            cat > /etc/sysctl.d/99-performance.conf << EOF
# 网站优化模式内核参数
fs.file-max = 1048576
fs.nr_open = 1048576
vm.swappiness = 20
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
net.core.netdev_max_backlog = 32768
net.core.somaxconn = 65536
net.core.wmem_default = 8388608
net.core.rmem_default = 8388608
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 20
net.ipv4.tcp_keepalive_time = 900
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_fastopen = 3
EOF
            if ! grep -q "* soft nofile 1048576" /etc/security/limits.conf; then
                echo "* soft nofile 1048576" >> /etc/security/limits.conf
                echo "* hard nofile 1048576" >> /etc/security/limits.conf
            fi
            sysctl --system > /dev/null 2>&1
            echo -e "${GREEN}网站优化模式设置完成！${NC}"
            echo -e "${YELLOW}部分参数需要重新登录或重启系统才能完全生效。${NC}"
            ;;
        4)
            echo -e "${BLUE}正在切换到直播优化模式...${NC}"
            cat > /etc/sysctl.d/99-performance.conf << EOF
# 直播优化模式内核参数
fs.file-max = 524288
fs.nr_open = 524288
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
net.core.netdev_max_backlog = 32768
net.core.somaxconn = 65536
net.core.wmem_default = 16777216
net.core.rmem_default = 16777216
net.core.rmem_max = 33554432
net.core.wmem_max = 33554432
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_congestion_control = bbr
EOF
            if ! grep -q "* soft nofile 524288" /etc/security/limits.conf; then
                echo "* soft nofile 524288" >> /etc/security/limits.conf
                echo "* hard nofile 524288" >> /etc/security/limits.conf
            fi
            sysctl --system > /dev/null 2>&1
            echo -e "${GREEN}直播优化模式设置完成！${NC}"
            echo -e "${YELLOW}部分参数需要重新登录或重启系统才能完全生效。${NC}"
            ;;
        5)
            echo -e "${BLUE}正在切换到游戏服优化模式...${NC}"
            cat > /etc/sysctl.d/99-performance.conf << EOF
# 游戏服优化模式内核参数
fs.file-max = 1048576
fs.nr_open = 1048576
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
net.core.netdev_max_backlog = 65536
net.core.somaxconn = 131072
net.core.wmem_default = 8388608
net.core.rmem_default = 8388608
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_max_syn_backlog = 32768
net.ipv4.tcp_max_tw_buckets = 8000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_congestion_control = bbr
EOF
            if ! grep -q "* soft nofile 1048576" /etc/security/limits.conf; then
                echo "* soft nofile 1048576" >> /etc/security/limits.conf
                echo "* hard nofile 1048576" >> /etc/security/limits.conf
            fi
            sysctl --system > /dev/null 2>&1
            echo -e "${GREEN}游戏服优化模式设置完成！${NC}"
            echo -e "${YELLOW}部分参数需要重新登录或重启系统才能完全生效。${NC}"
            ;;
        6)
            echo -e "${BLUE}正在还原系统默认设置...${NC}"
            rm -f /etc/sysctl.d/99-performance.conf
            sed -i '/^\* soft nofile/d' /etc/security/limits.conf
            sed -i '/^\* hard nofile/d' /etc/security/limits.conf
            sysctl --system > /dev/null 2>&1
            echo -e "${GREEN}系统设置已还原为默认配置！${NC}"
            echo -e "${YELLOW}部分参数需要重新登录或重启系统才能完全生效。${NC}"
            ;;
        0)
            echo -e "${BLUE}返回主菜单...${NC}"
            return
            ;;
        *)
            echo -e "${RED}无效输入，请输入 0-6 之间的数字。${NC}"
            sleep 2
            tune_performance
            ;;
    esac
}

function set_ssh_port() {
    echo -e "${RED}=== 重要安全警告 ===${NC}"
    echo -e "${YELLOW}修改SSH端口可能会导致您无法连接服务器！${NC}"
    echo -e "${YELLOW}在继续前，请确保您已经在【云服务商的安全组】或【物理防火墙】中放行了新端口 5522！${NC}"
    read -p "我已了解风险并已放行新端口，确认继续吗？ (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "${BLUE}操作已取消。${NC}"
        return
    fi
    
    echo -e "${BLUE}正在将SSH端口修改为 5522...${NC}"
    sed -i 's/^#*Port .*/Port 5522/' /etc/ssh/sshd_config
    echo -e "${GREEN}SSH配置文件修改完成。${NC}"
    
    echo -e "${BLUE}正在重启SSH服务...${NC}"
    if systemctl restart sshd; then
        echo -e "${GREEN}SSH服务重启成功！${NC}"
        echo -e "${YELLOW}请立即使用新端口 5522 重新连接服务器。例如: ssh user@your_ip -p 5522${NC}"
    else
        echo -e "${RED}SSH服务重启失败！请手动检查 'systemctl status sshd' 和 'journalctl -xe'。${NC}"
    fi
}

function open_all_ports() {
    echo -e "${RED}=== 极度危险操作警告 ===${NC}"
    echo -e "${YELLOW}此操作将禁用系统防火墙，使服务器所有端口暴露在公网，极易受到攻击！${NC}"
    echo -e "${YELLOW}仅建议在受信任的内部网络或临时调试时使用。${NC}"
    read -p "我确认要禁用防火墙并承担所有风险吗？ (y/n): " confirm
    if [[ "$confirm" != "y" ]]; then
        echo -e "${BLUE}操作已取消。${NC}"
        return
    fi

    if command -v ufw &> /dev/null; then
        echo -e "${BLUE}检测到 UFW，正在禁用...${NC}"
        ufw disable
        echo -e "${GREEN}UFW 防火墙已禁用。${NC}"
    elif command -v firewall-cmd &> /dev/null; then
        echo -e "${BLUE}检测到 Firewalld，正在停止并禁用...${NC}"
        systemctl stop firewalld
        systemctl disable firewalld
        echo -e "${GREEN}Firewalld 防火墙已禁用。${NC}"
    else
        echo -e "${YELLOW}未检测到 UFW 或 Firewalld，正在安装适合的防火墙...${NC}"
        if [[ "$PKG_MANAGER" == "apt-get" ]]; then
            echo -e "${BLUE}为基于 Debian/Ubuntu 的系统安装 UFW...${NC}"
            $PKG_MANAGER $UPDATE_CMD
            $PKG_MANAGER $INSTALL_CMD ufw
            if command -v ufw &> /dev/null; then
                echo -e "${BLUE}启用 UFW 防火墙...${NC}"
                ufw enable
                echo -e "${GREEN}UFW 防火墙已安装并启用。${NC}"
                echo -e "${YELLOW}注意：防火墙已启用，建议配置适当的规则以确保服务可访问性。${NC}"
            else
                echo -e "${RED}UFW 安装失败，请手动检查包管理器日志。${NC}"
                return
            fi
        elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
            echo -e "${BLUE}为基于 RHEL 的系统安装 Firewalld...${NC}"
            $PKG_MANAGER $UPDATE_CMD
            $PKG_MANAGER $INSTALL_CMD firewalld
            if command -v firewall-cmd &> /dev/null; then
                echo -e "${BLUE}启用 Firewalld 防火墙...${NC}"
                systemctl start firewalld
                systemctl enable firewalld
                echo -e "${GREEN}Firewalld 防火墙已安装并启用。${NC}"
                echo -e "${YELLOW}注意：防火墙已启用，建议配置适当的规则以确保服务可访问性。${NC}"
            else
                echo -e "${RED}Firewalld 安装失败，请手动检查包管理器日志。${NC}"
                return
            fi
        fi
        echo -e "${YELLOW}防火墙安装完成，但未禁用。请运行 'ufw disable' 或 'systemctl stop firewalld' 以禁用防火墙。${NC}"
        return
    fi
    echo -e "${GREEN}防火墙已禁用。${NC}"
}

# --- 主菜单 ---
function main_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================================================${NC}"
        echo -e "${GREEN}                Linux 系统全能工具箱 (By Gemini)                ${NC}"
        echo -e "${BLUE}================================================================${NC}"
        echo -e " ${YELLOW}1.${NC} 查看系统信息         ${YELLOW}7.${NC} 开启BBR加速"
        echo -e " ${YELLOW}2.${NC} 更新系统到最新       ${YELLOW}8.${NC} 设置虚拟内存1G"
        echo -e " ${YELLOW}3.${NC} 清理系统垃圾文件     ${YELLOW}9.${NC} 切换到优化模式"
        echo -e " ${YELLOW}4.${NC} 安装基础工具         ${YELLOW}10.${NC} 设置SSH端口为5522"
        echo -e " ${YELLOW}5.${NC} 设置时区到上海       ${YELLOW}11.${NC} 禁用防火墙(危险!)"
        echo -e " ${YELLOW}6.${NC} 优化DNS地址"
        echo -e ""
        echo -e " ${YELLOW}0.${NC} 退出脚本"
        echo -e "${BLUE}================================================================${NC}"
        read -p "请输入您的选择 [0-11]: " choice
        
        function back_to_menu() {
            read -p "按任意键返回主菜单..."
        }

        case $choice in
            1) system_info; back_to_menu ;;
            2) update_system; back_to_menu ;;
            3) clean_system; back_to_menu ;;
            4) install_tools; back_to_menu ;;
            5) set_timezone; back_to_menu ;;
            6) set_dns; back_to_menu ;;
            7) enable_bbr; back_to_menu ;;
            8) set_swap; back_to_menu ;;
            9) tune_performance; back_to_menu ;;
            10) set_ssh_port; back_to_menu ;;
            11) open_all_ports; back_to_menu ;;
            0) echo -e "${GREEN}感谢使用，再见！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效输入，请输入 0-11 之间的数字。${NC}"; sleep 2 ;;
        esac
    done
}

# 脚本入口
main_menu
