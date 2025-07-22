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
    # 尝试重启sshd服务
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
    elif command -v firewall-cmd &> /dev/null; then
        echo -e "${BLUE}检测到 Firewalld，正在停止并禁用...${NC}"
        systemctl stop firewalld
        systemctl disable firewalld
    else
        echo -e "${YELLOW}未检测到 UFW 或 Firewalld，可能没有防火墙在运行。${NC}"
        return
    fi
    echo -e "${GREEN}防火墙已禁用。${NC}"
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
    read -p "请输入您的选择 [1-2]: " dns_choice

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
        *)
            echo -e "${RED}无效输入，操作取消。${NC}"
            return
            ;;
    esac
    # chattr +i /etc/resolv.conf # 可选：锁定文件防止被覆盖，但可能引起其他问题
    echo -e "${GREEN}DNS设置成功！${NC}"
    echo -e "${YELLOW}注意：某些系统会自动覆盖此设置。如果DNS被重置，请考虑修改网络管理器的配置。${NC}"
}

function install_tools() {
    echo -e "${BLUE}开始安装基础工具...${NC}"
    # btop 可能在老版本系统中需要EPEL源，这里尝试安装
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
        # 将当前用户加入docker组
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

function tune_performance() {
    echo -e "${BLUE}正在切换到高性能模式...${NC}"
    
    cat > /etc/sysctl.d/99-performance.conf << EOF
#
# 高性能模式内核参数
#
# 文件描述符限制
fs.file-max = 1000000
fs.nr_open = 1000000

# 网络性能
net.core.netdev_max_backlog = 32768
net.core.somaxconn = 65535
net.core.wmem_default = 8388608
net.core.rmem_default = 8388608
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216

# TCP 优化
net.ipv4.tcp_max_syn_backlog = 16384
net.ipv4.tcp_max_tw_buckets = 6000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_syncookies = 1

# VM 优化
vm.swappiness = 10
EOF

    sysctl --system > /dev/null 2>&1
    
    if ! grep -q "* soft nofile 1000000" /etc/security/limits.conf; then
        echo "* soft nofile 1000000" >> /etc/security/limits.conf
        echo "* hard nofile 1000000" >> /etc/security/limits.conf
    fi
    
    echo -e "${GREEN}系统已切换到高性能模式！${NC}"
    echo -e "${YELLOW}部分参数 (如 nofile) 需要重新登录或重启系统才能完全生效。${NC}"
}


# --- 主菜单 ---
function main_menu() {
    while true; do
        clear
        echo -e "${BLUE}================================================================${NC}"
        echo -e "${GREEN}                Linux 系统全能工具箱 (By Gemini)                ${NC}"
        echo -e "${BLUE}================================================================${NC}"
        echo -e " ${YELLOW}1.${NC} 更新系统到最新       ${YELLOW}6.${NC} 开启BBR加速"
        echo -e " ${YELLOW}2.${NC} 清理系统垃圾文件     ${YELLOW}7.${NC} 设置时区到上海"
        echo -e " ${YELLOW}3.${NC} 设置虚拟内存1G       ${YELLOW}8.${NC} 优化DNS地址"
        echo -e " ${YELLOW}4.${NC} 设置SSH端口为5522    ${YELLOW}9.${NC} 安装基础工具"
        echo -e " ${YELLOW}5.${NC} 禁用防火墙(危险!)    ${YELLOW}10.${NC}切换到高性能模式"
        echo -e ""
        echo -e " ${YELLOW}0.${NC} 退出脚本"
        echo -e "${BLUE}================================================================${NC}"
        read -p "请输入您的选择 [0-10]: " choice
        
        # 返回主菜单前的等待
        function back_to_menu() {
            read -p "按任意键返回主菜单..."
        }

        case $choice in
            1) update_system; back_to_menu ;;
            2) clean_system; back_to_menu ;;
            3) set_swap; back_to_menu ;;
            4) set_ssh_port; back_to_menu ;;
            5) open_all_ports; back_to_menu ;;
            6) enable_bbr; back_to_menu ;;
            7) set_timezone; back_to_menu ;;
            8) set_dns; back_to_menu ;;
            9) install_tools; back_to_menu ;;
            10) tune_performance; back_to_menu ;;
            0) echo -e "${GREEN}感谢使用，再见！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效输入，请输入 0-10 之间的数字。${NC}"; sleep 2 ;;
        esac
    done
}

# 脚本入口
main_menu