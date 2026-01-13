#!/bin/bash
# Linux系统一键配置脚本
# 作者: Lingma
# 功能: 提供系统信息查看、更新、优化等功能的自动化脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查是否以root权限运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}错误: 此脚本必须以root权限运行${NC}"
        exit 1
    fi
}

# 显示菜单
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
    echo -e "${YELLOW}0. 退出${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo -e "${YELLOW}请输入选项 [0-12]: ${NC}"
}

# 系统信息概览
system_info() {
    echo -e "${BLUE}======= 系统信息概览 =======${NC}"
    echo "操作系统: $(lsb_release -d 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "内核版本: $(uname -r)"
    echo "主机名: $(hostname)"
    echo "IP地址: $(hostname -I 2>/dev/null || ip route get 1.1.1.1 2>/dev/null | awk '{print $7}' | head -1)"
    echo "运行时间: $(uptime -p)"
    echo "内存使用: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
    echo "磁盘使用: $(df -h / | awk 'NR==2 {print $3 "/" $2 " (" $5 ")"}')"
    echo "CPU负载: $(uptime | awk -F'load average:' '{print $2}')"
    echo -e "${BLUE}============================${NC}"
    read -p "按回车键继续..."
}

# 系统更新
system_update() {
    echo -e "${BLUE}======= 系统更新 =======${NC}"
    
    # 检测发行版并执行相应更新命令
    if command -v apt &> /dev/null; then
        echo "检测到Debian/Ubuntu系统"
        apt update && apt upgrade -y
    elif command -v yum &> /dev/null; then
        echo "检测到CentOS/RHEL系统"
        yum update -y
    elif command -v dnf &> /dev/null; then
        echo "检测到Fedora系统"
        dnf update -y
    else
        echo -e "${RED}未识别的包管理器${NC}"
        return 1
    fi
    
    echo -e "${GREEN}系统更新完成${NC}"
    read -p "按回车键继续..."
}

# 系统清理
system_clean() {
    echo -e "${BLUE}======= 系统清理 =======${NC}"
    
    if command -v apt &> /dev/null; then
        # Debian/Ubuntu 清理
        apt autoremove -y
        apt autoclean
        apt clean
        journalctl --vacuum-time=7d
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL 清理
        yum autoremove -y
        yum clean all
        journalctl --vacuum-time=7d
    elif command -v dnf &> /dev/null; then
        # Fedora 清理
        dnf autoremove -y
        dnf clean all
        journalctl --vacuum-time=7d
    fi
    
    # 清理临时文件
    rm -rf /tmp/*
    rm -rf /var/tmp/*
    
    echo -e "${GREEN}系统清理完成${NC}"
    read -p "按回车键继续..."
}

# BBR加速优化
enable_bbr() {
    echo -e "${BLUE}======= BBR加速优化 =======${NC}"
    
    # 检查内核版本
    kernel_version=$(uname -r | cut -d'-' -f1)
    if [[ "$(printf '%s\n' "4.9" "$kernel_version" | sort -V | head -n1)" = "4.9" ]]; then
        # 启用BBR
        echo 'net.core.default_qdisc=fq' >> /etc/sysctl.conf
        echo 'net.ipv4.tcp_congestion_control=bbr' >> /etc/sysctl.conf
        sysctl -p
        
        # 验证BBR是否启用
        if [[ $(sysctl net.ipv4.tcp_congestion_control | awk '{print $3}') == "bbr" ]]; then
            echo -e "${GREEN}BBR加速已成功启用${NC}"
        else
            echo -e "${RED}BBR加速启用失败${NC}"
        fi
    else
        echo -e "${YELLOW}当前内核版本不支持BBR (需要4.9+), 当前版本: $kernel_version${NC}"
    fi
    
    read -p "按回车键继续..."
}

# 设置虚拟内存(1G)
setup_swap() {
    echo -e "${BLUE}======= 设置虚拟内存 =======${NC}"
    
    # 检查是否已经存在swap
    if swapon --show | grep -q swap; then
        echo -e "${YELLOW}警告: 已经存在交换分区${NC}"
        read -p "是否重新创建1G交换分区? (y/N): " confirm
        if [[ ! $confirm =~ ^[Yy]$ ]]; then
            echo "取消操作"
            read -p "按回车键继续..."
            return
        fi
        # 关闭现有swap
        swapoff -a
    fi
    
    # 创建1G交换文件
    echo "正在创建1G交换文件..."
    dd if=/dev/zero of=/swapfile bs=1M count=1024
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    
    # 添加到fstab实现开机自动挂载
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    
    # 调整swappiness参数
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
    sysctl -p
    
    echo -e "${GREEN}1G虚拟内存设置完成${NC}"
    read -p "按回车键继续..."
}

# 优化DNS
optimize_dns() {
    echo -e "${BLUE}======= 优化DNS =======${NC}"
    
    echo "可选的DNS服务:"
    echo "1) Cloudflare DNS (1.1.1.1)"
    echo "2) Google DNS (8.8.8.8)"
    echo "3) Alibaba DNS (223.5.5.5)"
    echo "4) 自定义DNS"
    echo "5) 取消"
    
    read -p "请选择DNS服务 [1-5]: " dns_choice
    
    case $dns_choice in
        1)
            primary_dns="1.1.1.1"
            secondary_dns="1.0.0.1"
            ;;
        2)
            primary_dns="8.8.8.8"
            secondary_dns="8.8.4.4"
            ;;
        3)
            primary_dns="223.5.5.5"
            secondary_dns="223.6.6.6"
            ;;
        4)
            read -p "请输入首选DNS服务器: " primary_dns
            read -p "请输入备用DNS服务器: " secondary_dns
            ;;
        *)
            echo "取消操作"
            read -p "按回车键继续..."
            return
            ;;
    esac
    
    # 备份原配置
    cp /etc/resolv.conf /etc/resolv.conf.backup
    
    # 写入新的DNS配置
    echo "nameserver $primary_dns" > /etc/resolv.conf
    echo "nameserver $secondary_dns" >> /etc/resolv.conf
    
    echo -e "${GREEN}DNS已更新为: $primary_dns, $secondary_dns${NC}"
    read -p "按回车键继续..."
}

# 修改SSH端口
change_ssh_port() {
    echo -e "${BLUE}======= 修改SSH端口 =======${NC}"
    
    # 检查SSH配置文件是否存在
    if [ ! -f /etc/ssh/sshd_config ]; then
        echo -e "${RED}SSH配置文件不存在${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    # 备份原配置文件
    cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
    
    # 修改端口号为5522
    sed -i 's/#Port 22/Port 5522/' /etc/ssh/sshd_config
    sed -i 's/Port [0-9]*/Port 5522/' /etc/ssh/sshd_config
    
    # 重启SSH服务
    if command -v systemctl &> /dev/null; then
        systemctl restart sshd
    else
        service ssh restart
    fi
    
    echo -e "${GREEN}SSH端口已修改为5522${NC}"
    echo -e "${YELLOW}注意: 请确保防火墙允许新端口通信${NC}"
    read -p "按回车键继续..."
}

# 系统参数调优
system_tuning() {
    echo -e "${BLUE}======= 系统参数调优 =======${NC}"
    
    echo "可选的优化模式:"
    echo "1) 高性能模式"
    echo "2) 游戏模式"
    echo "3) 均衡模式"
    echo "4) 网站模式"
    echo "5) 直播模式"
    
    read -p "请选择优化模式 [1-5]: " mode_choice
    
    # 备份sysctl配置
    cp /etc/sysctl.conf /etc/sysctl.conf.backup
    
    case $mode_choice in
        1)
            # 高性能模式
            echo "# 高性能模式优化" >> /etc/sysctl.conf
            echo "net.core.rmem_max = 134217728" >> /etc/sysctl.conf
            echo "net.core.wmem_max = 134217728" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_rmem = 4096 87380 134217728" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_wmem = 4096 65536 134217728" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_fastopen = 3" >> /etc/sysctl.conf
            echo "fs.file-max = 1000000" >> /etc/sysctl.conf
            mode_name="高性能模式"
            ;;
        2)
            # 游戏模式
            echo "# 游戏模式优化" >> /etc/sysctl.conf
            echo "net.core.rmem_max = 67108864" >> /etc/sysctl.conf
            echo "net.core.wmem_max = 67108864" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_rmem = 4096 87380 67108864" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_wmem = 4096 65536 67108864" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_low_latency = 1" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_sack = 1" >> /etc/sysctl.conf
            mode_name="游戏模式"
            ;;
        3)
            # 均衡模式
            echo "# 均衡模式优化" >> /etc/sysctl.conf
            echo "net.core.rmem_max = 16777216" >> /etc/sysctl.conf
            echo "net.core.wmem_max = 16777216" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_rmem = 4096 65536 16777216" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_wmem = 4096 65536 16777216" >> /etc/sysctl.conf
            echo "net.core.netdev_max_backlog = 5000" >> /etc/sysctl.conf
            mode_name="均衡模式"
            ;;
        4)
            # 网站模式
            echo "# 网站模式优化" >> /etc/sysctl.conf
            echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
            echo "net.core.netdev_max_backlog = 5000" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_max_syn_backlog = 65535" >> /etc/sysctl.conf
            echo "net.ipv4.ip_local_port_range = 1024 65535" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_tw_reuse = 1" >> /etc/sysctl.conf
            mode_name="网站模式"
            ;;
        5)
            # 直播模式
            echo "# 直播模式优化" >> /etc/sysctl.conf
            echo "net.core.rmem_default = 16777216" >> /etc/sysctl.conf
            echo "net.core.rmem_max = 33554432" >> /etc/sysctl.conf
            echo "net.core.wmem_default = 16777216" >> /etc/sysctl.conf
            echo "net.core.wmem_max = 33554432" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_mtu_probing = 1" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_slow_start_after_idle = 0" >> /etc/sysctl.conf
            mode_name="直播模式"
            ;;
        *)
            echo "无效选择"
            read -p "按回车键继续..."
            return
            ;;
    esac
    
    # 应用配置
    sysctl -p
    
    echo -e "${GREEN}$mode_name 配置已完成${NC}"
    read -p "按回车键继续..."
}

# 安装基础工具
install_tools() {
    echo -e "${BLUE}======= 安装基础工具 =======${NC}"
    
    if command -v apt &> /dev/null; then
        # Debian/Ubuntu
        apt update
        apt install -y curl wget vim htop git unzip zip tar screen tmux
    elif command -v yum &> /dev/null; then
        # CentOS/RHEL
        yum install -y curl wget vim-enhanced htop git unzip zip tar screen tmux
    elif command -v dnf &> /dev/null; then
        # Fedora
        dnf install -y curl wget vim htop git unzip zip tar screen tmux
    else
        echo -e "${RED}未识别的包管理器${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    echo -e "${GREEN}基础工具安装完成${NC}"
    read -p "按回车键继续..."
}

# 设置时区为上海
set_timezone() {
    echo -e "${BLUE}======= 设置时区 =======${NC}"
    
    # 设置时区为上海
    timedatectl set-timezone Asia/Shanghai
    
    # 启用时间同步
    timedatectl set-ntp true
    
    echo -e "${GREEN}时区已设置为Asia/Shanghai${NC}"
    echo "当前时间: $(date)"
    read -p "按回车键继续..."
}

# 禁用防火墙
disable_firewall() {
    echo -e "${BLUE}======= 禁用防火墙 =======${NC}"
    
    # 根据不同发行版禁用防火墙
    if command -v ufw &> /dev/null; then
        # Ubuntu防火墙
        ufw disable
    elif command -v firewall-cmd &> /dev/null; then
        # CentOS/Fedora firewalld
        systemctl stop firewalld
        systemctl disable firewalld
    elif command -v iptables &> /dev/null; then
        # 传统iptables
        iptables -P INPUT ACCEPT
        iptables -P FORWARD ACCEPT
        iptables -P OUTPUT ACCEPT
        iptables -F
    fi
    
    echo -e "${YELLOW}防火墙已禁用${NC}"
    echo -e "${RED}安全警告: 禁用防火墙会降低系统安全性，请根据实际需求决定是否禁用${NC}"
    read -p "按回车键继续..."
}

# 重启服务器
reboot_system() {
    echo -e "${BLUE}======= 重启服务器 =======${NC}"
    read -p "确定要重启服务器吗? (Y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}服务器将在5秒后重启...${NC}"
        sleep 5
        reboot
    else
        echo "取消重启"
        read -p "按回车键继续..."
    fi
}

# 主循环
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
            10) set_timezone ;;
            11) disable_firewall ;;
            12) reboot_system ;;
            0) 
                echo -e "${GREEN}感谢使用，再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项，请重新选择${NC}"
                sleep 2
                ;;
        esac
    done
}

# 如果脚本直接运行，则执行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
