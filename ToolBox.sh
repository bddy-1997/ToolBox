#!/bin/bash
# Linux系统一键配置脚本 (逻辑优化+经典菜单版)
# 作者: Lingma / Gemini
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

# --- 核心工具函数 ---

check_root() {
    [[ $EUID -ne 0 ]] && echo -e "${RED}错误: 此脚本必须以root权限运行${NC}" && exit 1
}

# 幂等配置修改：防止配置项重复堆叠
set_config() {
    local key=$1
    local value=$2
    local file=$3
    sed -i "/^$key/d" "$file" 2>/dev/null
    echo "$key = $value" >> "$file"
}

# 智能包管理器封装
pkg_manager_run() {
    local action=$1
    shift
    if command -v apt &>/dev/null; then
        apt "$action" -y "$@"
    elif command -v dnf &>/dev/null; then
        dnf "$action" -y "$@"
    elif command -v yum &>/dev/null; then
        yum "$action" -y "$@"
    fi
}

# --- 功能模块 ---

show_menu() {
    clear
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}      Linux系统一键配置脚本 (经典菜单版)${NC}"
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
    echo -e "${YELLOW}0. 退出${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo -e "${YELLOW}请输入选项 [0-12]: ${NC}"
}

system_info() {
    echo -e "${BLUE}======= 系统信息概览 =======${NC}"
    echo "操作系统: $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "内核版本: $(uname -r)"
    
    # 网络信息增强
    local private_ip=$(hostname -I | awk '{print $1}')
    local public_ip=$(curl -s --connect-timeout 2 ipv4.icanhazip.com || echo "无法获取")
    local dns_servers=$(grep nameserver /etc/resolv.conf | awk '{print $2}' | xargs)
    echo "内网 IP:  $private_ip"
    echo "公网 IP:  $public_ip"
    echo "DNS服务器: $dns_servers"
    
    # 时区与运行状态
    echo "系统时区: $(timedatectl | grep "Time zone" | awk '{print $3}') ($(date))"
    echo "运行时间: $(uptime -p)"
    echo "内存使用: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
    echo "磁盘使用: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
    echo "CPU负载:  $(uptime | awk -F'load average:' '{print $2}')"
    echo -e "${BLUE}============================${NC}"
    read -p "按回车键继续..."
}

system_update() {
    echo -e "${BLUE}======= 系统更新 =======${NC}"
    pkg_manager_run upgrade
    echo -e "${GREEN}系统更新完成${NC}"
    read -p "按回车键继续..."
}

system_clean() {
    echo -e "${BLUE}======= 系统清理 =======${NC}"
    pkg_manager_run autoremove
    if command -v apt &>/dev/null; then apt clean; else yum clean all; fi
    journalctl --vacuum-time=7d
    find /tmp -type f -mtime +7 -delete
    echo -e "${GREEN}系统清理完成${NC}"
    read -p "按回车键继续..."
}

enable_bbr() {
    echo -e "${BLUE}======= BBR加速优化 =======${NC}"
    set_config "net.core.default_qdisc" "fq" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_congestion_control" "bbr" "$SYSCTL_CONF"
    sysctl -p >/dev/null
    if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
        echo -e "${GREEN}BBR加速已成功启用${NC}"
    else
        echo -e "${RED}BBR加速启用失败${NC}"
    fi
    read -p "按回车键继续..."
}

setup_swap() {
    echo -e "${BLUE}======= 设置虚拟内存 =======${NC}"
    if swapon --show | grep -q swap; then
        echo -e "${YELLOW}警告: 已经存在交换分区${NC}"
        read -p "是否重新创建1G交换文件? (y/N): " confirm
        [[ ! $confirm =~ ^[Yy]$ ]] && return
        swapoff -a
    fi
    fallocate -l $SWAP_SIZE /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=1024
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
        *) return ;;
    esac
    echo -e "nameserver $p_dns\nnameserver $s_dns" > /etc/resolv.conf
    echo -e "${GREEN}DNS已更新${NC}"
    read -p "按回车键继续..."
}

change_ssh_port() {
    echo -e "${BLUE}======= 修改SSH端口 =======${NC}"
    [[ ! -f /etc/ssh/sshd_config ]] && { echo -e "${RED}SSH配置不存在${NC}"; return; }
    if ss -tuln | grep -q ":$SSH_PORT "; then
        echo -e "${RED}错误: 端口 $SSH_PORT 已被占用${NC}"; return
    fi
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    sed -i "s/^#\?Port [0-9]*/Port $SSH_PORT/" /etc/ssh/sshd_config
    systemctl restart sshd || service ssh restart
    echo -e "${GREEN}SSH端口已修改为 $SSH_PORT${NC}"
    read -p "按回车键继续..."
}

system_tuning() {
    echo -e "${BLUE}======= 系统参数调优 =======${NC}"
    echo -e "1) 高性能  2) 游戏  3) 均衡  4) 网站  5) 直播"
    read -p "请选择模式 [1-5]: " mode_choice
    case $mode_choice in
        1) set_config "fs.file-max" "1000000" "$SYSCTL_CONF"; mode="高性能" ;;
        2) set_config "net.ipv4.tcp_low_latency" "1" "$SYSCTL_CONF"; mode="游戏" ;;
        3) set_config "net.core.netdev_max_backlog" "5000" "$SYSCTL_CONF"; mode="均衡" ;;
        4) set_config "net.core.somaxconn" "65535" "$SYSCTL_CONF"; mode="网站" ;;
        5) set_config "net.ipv4.tcp_slow_start_after_idle" "0" "$SYSCTL_CONF"; mode="直播" ;;
        *) return ;;
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

reboot_system() {
    read -p "确定要重启服务器吗? (Y/N): " confirm
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}服务器将在5秒后重启...${NC}"
        sleep 5 && reboot
    fi
}

# --- 主循环 ---

main() {
    check_root
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
            10) timedatectl set-timezone Asia/Shanghai && echo "时区已设为上海" && sleep 2 ;;
            11) 
                ufw disable &>/dev/null; systemctl stop firewalld &>/dev/null
                echo -e "${YELLOW}防火墙已禁用${NC}"; sleep 2 ;;
            12) reboot_system ;;
            0) echo -e "${GREEN}感谢使用！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选项${NC}"; sleep 2 ;;
        esac
    done
}

main "$@"
