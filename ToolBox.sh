#!/bin/bash
# Linux系统一键配置脚本
# 作者: Lingma / Gemini / Optimized by Grok
# 功能: 提供系统信息查看、更新、优化等功能的自动化脚本


# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 全局变量
SSH_PORT=5522
SWAP_SIZE="1G"
SYSCTL_CONF="/etc/sysctl.conf"
# GitHub Raw 地址
UPDATE_URL="https://raw.githubusercontent.com/bddy-1997/ToolBox/main/ToolBox.sh"
# 获取当前脚本的绝对路径
CURRENT_SCRIPT=$(readlink -f "$0")

# --- 核心工具函数 ---

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本必须以root权限运行${NC}"
        exit 1
    fi
}

# 自动安装/修复快捷指令函数
auto_install_shortcut() {
    if [[ ! -L "/usr/bin/q" ]] || [[ "$(readlink -f /usr/bin/q)" != "$CURRENT_SCRIPT" ]]; then
        echo -e "${YELLOW}正在配置快捷指令 'q'...${NC}"
        rm -f /usr/bin/q
        ln -s "$CURRENT_SCRIPT" /usr/bin/q
        chmod +x "$CURRENT_SCRIPT"
        if [[ -L "/usr/bin/q" ]]; then
            echo -e "${GREEN}快捷指令安装成功！以后输入 'q' 即可启动本脚本。${NC}"
        else
            echo -e "${RED}快捷指令安装失败，请检查系统权限。${NC}"
        fi
    fi
}

# 幂等配置修改（备份原文件）
set_config() {
    local key=$1
    local value=$2
    local file=$3
    if [[ ! -f "$file.bak" ]]; then
        cp "$file" "$file.bak"
    fi
    sed -i "/^$key/d" "$file" 2>/dev/null
    echo "$key = $value" >> "$file"
}

# 智能包管理器检测与运行
detect_pkg_manager() {
    if command -v apt &>/dev/null; then
        PKG_MANAGER="apt"
    elif command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
    elif command -v yum &>/dev/null; then
        PKG_MANAGER="yum"
    else
        echo -e "${RED}不支持的包管理器。请手动安装工具。${NC}"
        exit 1
    fi
}

pkg_manager_run() {
    local action=$1
    shift
    case "$PKG_MANAGER" in
        apt) apt "$action" -y "$@" ;;
        dnf) dnf "$action" -y "$@" ;;
        yum) yum "$action" -y "$@" ;;
    esac
}

# --- 更新脚本函数 ---

update_script() {
    echo -e "${BLUE}======= 检查并更新脚本 =======${NC}"
    echo -e "正在从 GitHub 获取最新版本..."
    
    # 使用curl优先，fallback到wget
    if command -v curl &>/dev/null; then
        curl -s -o /tmp/ToolBox.sh "$UPDATE_URL"
    elif command -v wget &>/dev/null; then
        wget -q -O /tmp/ToolBox.sh "$UPDATE_URL"
    else
        echo -e "${RED}需要curl或wget来下载更新。${NC}"
        return
    fi
    
    if [[ -s /tmp/ToolBox.sh ]] && grep -q "#!/bin/bash" /tmp/ToolBox.sh; then
        mv /tmp/ToolBox.sh "$CURRENT_SCRIPT"
        chmod +x "$CURRENT_SCRIPT"
        rm -f /usr/bin/q
        ln -s "$CURRENT_SCRIPT" /usr/bin/q
        echo -e "${GREEN}脚本更新成功！正在重启脚本...${NC}"
        exec "$CURRENT_SCRIPT"
    else
        echo -e "${RED}下载失败或文件无效。请检查网络或GitHub地址。${NC}"
        rm -f /tmp/ToolBox.sh
    fi
    read -p "按回车键继续..."
}

# --- 菜单与信息函数 ---

show_menu() {
    clear
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}      Linux系统一键配置脚本${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo -e "${GREEN}1. 系统信息概览${NC}"
    echo -e "${GREEN}2. 系统更新${NC}"
    echo -e "${GREEN}3. 系统清理${NC}"
    echo -e "${GREEN}4. BBR加速优化${NC}"
    echo -e "${GREEN}5. 设置虚拟内存(1G)${NC}"
    echo -e "${GREEN}6. 优化DNS${NC}"
    echo -e "${GREEN}7. 修改SSH端口(5522)${NC}"
    echo -e "${GREEN}8. 系统参数调优${NC}"
    echo -e "${GREEN}9. 安装基础工具${NC}"
    echo -e "${GREEN}10. 设置时区为上海${NC}"
    echo -e "${GREEN}11. 禁用防火墙${NC}"
    echo -e "${GREEN}12. 重启服务器${NC}"
    echo -e "${BLUE}--------------------------------------------${NC}"
    echo -e "${YELLOW}13. 在线更新脚本${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo -e "${YELLOW}0. 退出${NC}"
    echo -e "${YELLOW}请输入选项 [0-13]: ${NC}"
}

system_info() {
    echo -e "${BLUE}======= 系统信息概览 =======${NC}"
    echo "操作系统: $(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '"')"
    echo "内核版本: $(uname -r)"
    local private_ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "未知")
    local public_ip=$(curl -s --connect-timeout 2 ipv4.icanhazip.com 2>/dev/null || echo "无法获取")
    local dns_servers=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | xargs || echo "未知")
    echo "内网 IP:  $private_ip"
    echo "公网 IP:  $public_ip"
    echo "DNS服务器: $dns_servers"
    echo "系统时区: $(timedatectl | grep "Time zone" | awk '{print $3}' || echo "未知") ($(date))"
    echo "运行时间: $(uptime -p)"
    echo "内存使用: $(free -h | awk '/^Mem:/ {print $3 "/" $2}' || echo "未知")"
    echo "磁盘使用: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}' || echo "未知")"
    echo "CPU负载:  $(uptime | awk -F'load average:' '{print $2}' || echo "未知")"
    echo -e "${BLUE}============================${NC}"
    read -p "按回车键继续..."
}

# --- 系统维护函数 ---

system_update() {
    echo -e "${BLUE}======= 系统更新 =======${NC}"
    pkg_manager_run update
    pkg_manager_run upgrade
    echo -e "${GREEN}系统更新完成${NC}"
    read -p "按回车键继续..."
}

system_clean() {
    echo -e "${BLUE}======= 系统清理 =======${NC}"
    pkg_manager_run autoremove
    case "$PKG_MANAGER" in
        apt) apt clean ;;
        *) yum clean all || dnf clean all ;;
    esac
    journalctl --vacuum-time=7d 2>/dev/null
    find /tmp -type f -mtime +7 -delete 2>/dev/null
    echo -e "${GREEN}系统清理完成${NC}"
    read -p "按回车键继续..."
}

enable_bbr() {
    echo -e "${BLUE}======= BBR加速优化 =======${NC}"
    if lsmod | grep -q bbr; then
        echo -e "${YELLOW}BBR已启用，无需重复操作。${NC}"
        read -p "按回车键继续..."
        return
    fi
    set_config "net.core.default_qdisc" "fq" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_congestion_control" "bbr" "$SYSCTL_CONF"
    sysctl -p >/dev/null
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo -e "${GREEN}BBR加速已成功启用${NC}"
    else
        echo -e "${RED}BBR加速启用失败，请检查内核是否支持BBR。${NC}"
    fi
    read -p "按回车键继续..."
}

setup_swap() {
    echo -e "${BLUE}======= 设置虚拟内存 =======${NC}"
    if swapon --show | grep -q '/swapfile'; then
        echo -e "${YELLOW}警告: 已经存在/swapfile交换文件${NC}"
        read -p "是否重新创建1G交换文件? (y/N): " confirm
        [[ ! $confirm =~ ^[Yy]$ ]] && { read -p "按回车键继续..."; return; }
        swapoff -a
        rm -f /swapfile
    fi
    fallocate -l $SWAP_SIZE /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 conv=notrunc
    chmod 600 /swapfile
    mkswap /swapfile && swapon /swapfile
    grep -q "/swapfile" /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    set_config "vm.swappiness" "10" "$SYSCTL_CONF"
    sysctl -p >/dev/null
    echo -e "${GREEN}1G虚拟内存设置完成${NC}"
    read -p "按回车键继续..."
}

optimize_dns() {
    echo -e "${BLUE}======= 优化DNS =======${NC}"
    echo -e "1) Cloudflare (1.1.1.1)\n2) Google (8.8.8.8)\n3) Alibaba (223.5.5.5)\n4) 自定义\n5) 取消"
    read -p "请选择 [1-5]: " dns_choice
    case $dns_choice in
        1) p_dns="1.1.1.1"; s_dns="1.0.0.1" ;;
        2) p_dns="8.8.8.8"; s_dns="8.8.4.4" ;;
        3) p_dns="223.5.5.5"; s_dns="223.6.6.6" ;;
        4) read -p "首选DNS: " p_dns; read -p "备用DNS: " s_dns ;;
        *) read -p "按回车键继续..."; return ;;
    esac
    if [[ -n "$p_dns" ]]; then
        if [[ ! -f /etc/resolv.conf.bak ]]; then
            cp /etc/resolv.conf /etc/resolv.conf.bak
        fi
        echo -e "nameserver $p_dns\nnameserver $s_dns" > /etc/resolv.conf
        echo -e "${GREEN}DNS已更新（注意：systemd-resolved可能覆盖此配置）${NC}"
    fi
    read -p "按回车键继续..."
}

change_ssh_port() {
    echo -e "${BLUE}======= 修改SSH端口 =======${NC}"
    if [[ ! -f /etc/ssh/sshd_config ]]; then
        echo -e "${RED}SSH配置不存在${NC}"
        read -p "按回车键继续..."
        return
    fi
    if ss -tuln | grep -q ":$SSH_PORT "; then
        echo -e "${RED}错误: 端口 $SSH_PORT 已被占用${NC}"
        read -p "按回车键继续..."
        return
    fi
    if [[ ! -f /etc/ssh/sshd_config.bak ]]; then
        cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    fi
    sed -i "s/^#\?Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
    systemctl restart sshd 2>/dev/null || service ssh restart 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}SSH端口已修改为 $SSH_PORT${NC}"
    else
        echo -e "${RED}SSH重启失败，请检查配置。${NC}"
    fi
    read -p "按回车键继续..."
}

system_tuning() {
    echo -e "${BLUE}======= 系统参数调优 =======${NC}"
    echo -e "1) 高性能  2) 游戏  3) 均衡  4) 网站  5) 直播  6) 取消"
    read -p "请选择模式 [1-6]: " mode_choice
    local mode=""
    case $mode_choice in
        1) set_config "fs.file-max" "1000000" "$SYSCTL_CONF"; mode="高性能" ;;
        2) set_config "net.ipv4.tcp_low_latency" "1" "$SYSCTL_CONF"; mode="游戏" ;;
        3) set_config "net.core.netdev_max_backlog" "5000" "$SYSCTL_CONF"; mode="均衡" ;;
        4) set_config "net.core.somaxconn" "65535" "$SYSCTL_CONF"; mode="网站" ;;
        5) set_config "net.ipv4.tcp_slow_start_after_idle" "0" "$SYSCTL_CONF"; mode="直播" ;;
        *) read -p "按回车键继续..."; return ;;
    esac
    sysctl -p >/dev/null
    echo -e "${GREEN}$mode 模式配置完成${NC}"
    read -p "按回车键继续..."
}

install_tools() {
    echo -e "${BLUE}======= 安装基础工具 =======${NC}"
    pkg_manager_run install curl wget vim htop git unzip zip tar screen tmux
    echo -e "${GREEN}基础工具安装完成${NC}"
    read -p "按回车键继续..."
}

set_timezone() {
    timedatectl set-timezone Asia/Shanghai 2>/dev/null
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}时区已设为上海${NC}"
    else
        echo -e "${RED}时区设置失败，请检查timedatectl命令。${NC}"
    fi
    read -p "按回车键继续..."
}

disable_firewall() {
    ufw disable >/dev/null 2>&1
    systemctl stop firewalld >/dev/null 2>&1
    systemctl disable firewalld >/dev/null 2>&1
    echo -e "${YELLOW}防火墙已禁用${NC}"
    read -p "按回车键继续..."
}

reboot_system() {
    read -p "确定要重启服务器吗? (Y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}服务器将在5秒后重启...${NC}"
        sleep 5 && reboot
    else
        read -p "按回车键继续..."
    fi
}

# --- 主循环 ---

main() {
    check_root
    detect_pkg_manager
    auto_install_shortcut
    
    while true; do
        show_menu
        read -r choice
        case $choice in
            1) system_info ;;
            2) system_update ;;
            3) system_clean ;;
            4) enable_bbr ;;
            5) setup_swap ;;
            6) optimize_dns ;;
            7) change_ssh_port ;;
            8) system_tuning ;;
            9) install_tools ;;
            10) set_timezone ;;
            11) disable_firewall ;;
            12) reboot_system ;;
            13) update_script ;;
            0) echo -e "${GREEN}感谢使用！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选项${NC}"; sleep 2 ;;
        esac
    done
}

main "$@"
