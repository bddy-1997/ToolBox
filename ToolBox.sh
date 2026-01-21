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
FIREWALL_TYPE=""  # 自动检测防火墙类型
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

# 检测系统使用的防火墙类型
detect_firewall_type() {
    if command -v ufw &>/dev/null && systemctl is-active --quiet ufw; then
        FIREWALL_TYPE="ufw"
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        FIREWALL_TYPE="firewalld"
    elif command -v iptables &>/dev/null; then
        FIREWALL_TYPE="iptables"
    else
        FIREWALL_TYPE="none"
    fi
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

# 开放所有端口函数
open_all_ports() {
    echo -e "${BLUE}======= 开放所有端口 =======${NC}"
    
    detect_firewall_type
    
    case "$FIREWALL_TYPE" in
        "ufw")
            echo -e "${YELLOW}检测到UFW防火墙${NC}"
            ufw --force reset
            ufw default allow
            ufw --force enable
            echo -e "${GREEN}UFW已设置为默认允许所有连接${NC}"
            ;;
        "firewalld")
            echo -e "${YELLOW}检测到Firewalld防火墙${NC}"
            firewall-cmd --permanent --add-service=ssh
            firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="0.0.0.0/0" port protocol="tcp" port="*" accept'
            firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="0.0.0.0/0" port protocol="udp" port="*" accept'
            firewall-cmd --reload
            echo -e "${GREEN}Firewalld已配置允许所有TCP/UDP端口${NC}"
            ;;
        "iptables")
            echo -e "${YELLOW}检测到Iptables防火墙${NC}"
            iptables -P INPUT ACCEPT
            iptables -P FORWARD ACCEPT
            iptables -P OUTPUT ACCEPT
            iptables -F
            iptables -X
            # 保存规则
            if [[ "$PKG_MANAGER" == "apt" ]]; then
                # Debian/Ubuntu
                if command -v iptables-persistent &>/dev/null; then
                    iptables-save > /etc/iptables/rules.v4
                fi
            else
                # CentOS/RHEL
                service iptables save 2>/dev/null || echo "无法自动保存iptables规则"
            fi
            echo -e "${GREEN}Iptables已配置允许所有连接${NC}"
            ;;
        *)
            echo -e "${YELLOW}未检测到活动的防火墙服务，或者系统未使用常见防火墙${NC}"
            ;;
    esac
    
    # 显示当前防火墙状态
    case "$FIREWALL_TYPE" in
        "ufw")
            echo -e "\n${BLUE}当前UFW状态:${NC}"
            ufw status verbose
            ;;
        "firewalld")
            echo -e "\n${BLUE}当前Firewalld区域配置:${NC}"
            firewall-cmd --list-all
            ;;
        "iptables")
            echo -e "\n${BLUE}当前Iptables规则:${NC}"
            iptables -L -n -v
            ;;
    esac
    
    echo -e "\n${YELLOW}警告: 所有端口已开放，这可能带来安全风险！${NC}"
    read -p "按回车键继续..."
}

# 内核参数优化主函数
kernel_parameter_optimization() {
    echo -e "${BLUE}======= 内核参数优化 =======${NC}"
    echo -e "${GREEN}请选择优化模式:${NC}"
    echo -e "${YELLOW}1) 高性能模式${NC}"
    echo -e "${YELLOW}2) 均衡模式${NC}"
    echo -e "${YELLOW}3) 网站搭建模式${NC}"
    echo -e "${YELLOW}4) 还原默认设置${NC}"
    echo -e "${YELLOW}5) 返回主菜单${NC}"
    read -p "请输入选项 [1-5]: " opt_choice
    
    case $opt_choice in
        1)
            optimize_high_performance
            ;;
        2)
            optimize_balanced
            ;;
        3)
            optimize_web_server
            ;;
        4)
            restore_defaults
            ;;
        5)
            return
            ;;
        *)
            echo -e "${RED}无效选项${NC}"
            sleep 2
            kernel_parameter_optimization
            ;;
    esac
}

# 高性能模式优化函数
optimize_high_performance() {
    echo -e "${BLUE}======= 高性能模式优化 =======${NC}"
    
    echo -e "${GREEN}优化文件描述符...${NC}"
    ulimit -n 65535
    
    echo -e "${GREEN}优化虚拟内存...${NC}"
    sysctl -w vm.swappiness=10 2>/dev/null
    sysctl -w vm.dirty_ratio=15 2>/dev/null
    sysctl -w vm.dirty_background_ratio=5 2>/dev/null
    sysctl -w vm.overcommit_memory=1 2>/dev/null
    sysctl -w vm.min_free_kbytes=65536 2>/dev/null
    
    echo -e "${GREEN}优化网络设置...${NC}"
    sysctl -w net.core.rmem_max=16777216 2>/dev/null
    sysctl -w net.core.wmem_max=16777216 2>/dev/null
    sysctl -w net.core.netdev_max_backlog=250000 2>/dev/null
    sysctl -w net.core.somaxconn=4096 2>/dev/null
    sysctl -w net.ipv4.tcp_rmem='4096 87380 16777216' 2>/dev/null
    sysctl -w net.ipv4.tcp_wmem='4096 65536 16777216' 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_max_syn_backlog=8192 2>/dev/null
    sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
    sysctl -w net.ipv4.ip_local_port_range='1024 65535' 2>/dev/null
    
    echo -e "${GREEN}优化缓存管理...${NC}"
    sysctl -w vm.vfs_cache_pressure=50 2>/dev/null
    
    echo -e "${GREEN}优化CPU设置...${NC}"
    sysctl -w kernel.sched_autogroup_enabled=0 2>/dev/null
    
    echo -e "${GREEN}其他优化...${NC}"
    # 禁用透明大页面，减少延迟
    echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null
    # 禁用 NUMA balancing
    sysctl -w kernel.numa_balancing=0 2>/dev/null
    
    # 将优化设置永久保存到sysctl.conf
    set_config "vm.swappiness" "10" "$SYSCTL_CONF"
    set_config "vm.dirty_ratio" "15" "$SYSCTL_CONF"
    set_config "vm.dirty_background_ratio" "5" "$SYSCTL_CONF"
    set_config "vm.overcommit_memory" "1" "$SYSCTL_CONF"
    set_config "vm.min_free_kbytes" "65536" "$SYSCTL_CONF"
    set_config "net.core.rmem_max" "16777216" "$SYSCTL_CONF"
    set_config "net.core.wmem_max" "16777216" "$SYSCTL_CONF"
    set_config "net.core.netdev_max_backlog" "250000" "$SYSCTL_CONF"
    set_config "net.core.somaxconn" "4096" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_rmem" "4096 87380 16777216" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_wmem" "4096 65536 16777216" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_congestion_control" "bbr" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_max_syn_backlog" "8192" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_tw_reuse" "1" "$SYSCTL_CONF"
    set_config "net.ipv4.ip_local_port_range" "1024 65535" "$SYSCTL_CONF"
    set_config "vm.vfs_cache_pressure" "50" "$SYSCTL_CONF"
    set_config "kernel.sched_autogroup_enabled" "0" "$SYSCTL_CONF"
    set_config "kernel.numa_balancing" "0" "$SYSCTL_CONF"
    
    echo -e "${GREEN}高性能模式优化完成${NC}"
    read -p "按回车键继续..."
}

# 均衡模式优化函数
optimize_balanced() {
    echo -e "${BLUE}======= 均衡模式优化 =======${NC}"
    
    echo -e "${GREEN}优化文件描述符...${NC}"
    ulimit -n 32768
    
    echo -e "${GREEN}优化虚拟内存...${NC}"
    sysctl -w vm.swappiness=30 2>/dev/null
    sysctl -w vm.dirty_ratio=20 2>/dev/null
    sysctl -w vm.dirty_background_ratio=10 2>/dev/null
    sysctl -w vm.overcommit_memory=0 2>/dev/null
    sysctl -w vm.min_free_kbytes=32768 2>/dev/null
    
    echo -e "${GREEN}优化网络设置...${NC}"
    sysctl -w net.core.rmem_max=8388608 2>/dev/null
    sysctl -w net.core.wmem_max=8388608 2>/dev/null
    sysctl -w net.core.netdev_max_backlog=125000 2>/dev/null
    sysctl -w net.core.somaxconn=2048 2>/dev/null
    sysctl -w net.ipv4.tcp_rmem='4096 87380 8388608' 2>/dev/null
    sysctl -w net.ipv4.tcp_wmem='4096 32768 8388608' 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_max_syn_backlog=4096 2>/dev/null
    sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
    sysctl -w net.ipv4.ip_local_port_range='1024 49151' 2>/dev/null
    
    echo -e "${GREEN}优化缓存管理...${NC}"
    sysctl -w vm.vfs_cache_pressure=75 2>/dev/null
    
    echo -e "${GREEN}优化CPU设置...${NC}"
    sysctl -w kernel.sched_autogroup_enabled=1 2>/dev/null
    
    echo -e "${GREEN}其他优化...${NC}"
    # 还原透明大页面
    echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null
    # 还原 NUMA balancing
    sysctl -w kernel.numa_balancing=1 2>/dev/null
    
    # 将优化设置永久保存到sysctl.conf
    set_config "vm.swappiness" "30" "$SYSCTL_CONF"
    set_config "vm.dirty_ratio" "20" "$SYSCTL_CONF"
    set_config "vm.dirty_background_ratio" "10" "$SYSCTL_CONF"
    set_config "vm.overcommit_memory" "0" "$SYSCTL_CONF"
    set_config "vm.min_free_kbytes" "32768" "$SYSCTL_CONF"
    set_config "net.core.rmem_max" "8388608" "$SYSCTL_CONF"
    set_config "net.core.wmem_max" "8388608" "$SYSCTL_CONF"
    set_config "net.core.netdev_max_backlog" "125000" "$SYSCTL_CONF"
    set_config "net.core.somaxconn" "2048" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_rmem" "4096 87380 8388608" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_wmem" "4096 32768 8388608" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_congestion_control" "bbr" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_max_syn_backlog" "4096" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_tw_reuse" "1" "$SYSCTL_CONF"
    set_config "net.ipv4.ip_local_port_range" "1024 49151" "$SYSCTL_CONF"
    set_config "vm.vfs_cache_pressure" "75" "$SYSCTL_CONF"
    set_config "kernel.sched_autogroup_enabled" "1" "$SYSCTL_CONF"
    set_config "kernel.numa_balancing" "1" "$SYSCTL_CONF"
    
    echo -e "${GREEN}均衡模式优化完成${NC}"
}

# 还原默认设置函数
restore_defaults() {
    echo -e "${BLUE}======= 还原到默认设置 =======${NC}"
    
    echo -e "${GREEN}还原文件描述符...${NC}"
    ulimit -n 1024
    
    echo -e "${GREEN}还原虚拟内存...${NC}"
    sysctl -w vm.swappiness=60 2>/dev/null
    sysctl -w vm.dirty_ratio=20 2>/dev/null
    sysctl -w vm.dirty_background_ratio=10 2>/dev/null
    sysctl -w vm.overcommit_memory=0 2>/dev/null
    sysctl -w vm.min_free_kbytes=16384 2>/dev/null
    
    echo -e "${GREEN}还原网络设置...${NC}"
    sysctl -w net.core.rmem_max=212992 2>/dev/null
    sysctl -w net.core.wmem_max=212992 2>/dev/null
    sysctl -w net.core.netdev_max_backlog=1000 2>/dev/null
    sysctl -w net.core.somaxconn=128 2>/dev/null
    sysctl -w net.ipv4.tcp_rmem='4096 87380 6291456' 2>/dev/null
    sysctl -w net.ipv4.tcp_wmem='4096 16384 4194304' 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=cubic 2>/dev/null
    sysctl -w net.ipv4.tcp_max_syn_backlog=2048 2>/dev/null
    sysctl -w net.ipv4.tcp_tw_reuse=0 2>/dev/null
    sysctl -w net.ipv4.ip_local_port_range='32768 60999' 2>/dev/null
    
    echo -e "${GREEN}还原缓存管理...${NC}"
    sysctl -w vm.vfs_cache_pressure=100 2>/dev/null
    
    echo -e "${GREEN}还原CPU设置...${NC}"
    sysctl -w kernel.sched_autogroup_enabled=1 2>/dev/null
    
    echo -e "${GREEN}还原其他优化...${NC}"
    # 还原透明大页面
    echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null
    # 还原 NUMA balancing
    sysctl -w kernel.numa_balancing=1 2>/dev/null
    
    # 将默认设置永久保存到sysctl.conf
    set_config "vm.swappiness" "60" "$SYSCTL_CONF"
    set_config "vm.dirty_ratio" "20" "$SYSCTL_CONF"
    set_config "vm.dirty_background_ratio" "10" "$SYSCTL_CONF"
    set_config "vm.overcommit_memory" "0" "$SYSCTL_CONF"
    set_config "vm.min_free_kbytes" "16384" "$SYSCTL_CONF"
    set_config "net.core.rmem_max" "212992" "$SYSCTL_CONF"
    set_config "net.core.wmem_max" "212992" "$SYSCTL_CONF"
    set_config "net.core.netdev_max_backlog" "1000" "$SYSCTL_CONF"
    set_config "net.core.somaxconn" "128" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_rmem" "4096 87380 6291456" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_wmem" "4096 16384 4194304" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_congestion_control" "cubic" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_max_syn_backlog" "2048" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_tw_reuse" "0" "$SYSCTL_CONF"
    set_config "net.ipv4.ip_local_port_range" "32768 60999" "$SYSCTL_CONF"
    set_config "vm.vfs_cache_pressure" "100" "$SYSCTL_CONF"
    set_config "kernel.sched_autogroup_enabled" "1" "$SYSCTL_CONF"
    set_config "kernel.numa_balancing" "1" "$SYSCTL_CONF"
    
    echo -e "${GREEN}还原默认设置完成${NC}"
    read -p "按回车键继续..."
}

# 网站搭建优化函数
optimize_web_server() {
    echo -e "${BLUE}======= 网站搭建优化模式 =======${NC}"
    
    echo -e "${GREEN}优化文件描述符...${NC}"
    ulimit -n 65535
    
    echo -e "${GREEN}优化虚拟内存...${NC}"
    sysctl -w vm.swappiness=10 2>/dev/null
    sysctl -w vm.dirty_ratio=20 2>/dev/null
    sysctl -w vm.dirty_background_ratio=10 2>/dev/null
    sysctl -w vm.overcommit_memory=1 2>/dev/null
    sysctl -w vm.min_free_kbytes=65536 2>/dev/null
    
    echo -e "${GREEN}优化网络设置...${NC}"
    sysctl -w net.core.rmem_max=16777216 2>/dev/null
    sysctl -w net.core.wmem_max=16777216 2>/dev/null
    sysctl -w net.core.netdev_max_backlog=5000 2>/dev/null
    sysctl -w net.core.somaxconn=4096 2>/dev/null
    sysctl -w net.ipv4.tcp_rmem='4096 87380 16777216' 2>/dev/null
    sysctl -w net.ipv4.tcp_wmem='4096 65536 16777216' 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_max_syn_backlog=8192 2>/dev/null
    sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
    sysctl -w net.ipv4.ip_local_port_range='1024 65535' 2>/dev/null
    
    echo -e "${GREEN}优化缓存管理...${NC}"
    sysctl -w vm.vfs_cache_pressure=50 2>/dev/null
    
    echo -e "${GREEN}优化CPU设置...${NC}"
    sysctl -w kernel.sched_autogroup_enabled=0 2>/dev/null
    
    echo -e "${GREEN}其他优化...${NC}"
    # 禁用透明大页面，减少延迟
    echo never > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null
    # 禁用 NUMA balancing
    sysctl -w kernel.numa_balancing=0 2>/dev/null
    
    # 将优化设置永久保存到sysctl.conf
    set_config "vm.swappiness" "10" "$SYSCTL_CONF"
    set_config "vm.dirty_ratio" "20" "$SYSCTL_CONF"
    set_config "vm.dirty_background_ratio" "10" "$SYSCTL_CONF"
    set_config "vm.overcommit_memory" "1" "$SYSCTL_CONF"
    set_config "vm.min_free_kbytes" "65536" "$SYSCTL_CONF"
    set_config "net.core.rmem_max" "16777216" "$SYSCTL_CONF"
    set_config "net.core.wmem_max" "16777216" "$SYSCTL_CONF"
    set_config "net.core.netdev_max_backlog" "5000" "$SYSCTL_CONF"
    set_config "net.core.somaxconn" "4096" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_rmem" "4096 87380 16777216" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_wmem" "4096 65536 16777216" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_congestion_control" "bbr" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_max_syn_backlog" "8192" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_tw_reuse" "1" "$SYSCTL_CONF"
    set_config "net.ipv4.ip_local_port_range" "1024 65535" "$SYSCTL_CONF"
    set_config "vm.vfs_cache_pressure" "50" "$SYSCTL_CONF"
    set_config "kernel.sched_autogroup_enabled" "0" "$SYSCTL_CONF"
    set_config "kernel.numa_balancing" "0" "$SYSCTL_CONF"
    
    echo -e "${GREEN}网站搭建优化模式完成${NC}"
    read -p "按回车键继续..."
}

# 一键优化函数
one_click_optimization() {
    echo -e "${BLUE}======= 一键优化开始 =======${NC}"
    echo -e "${YELLOW}即将执行以下操作:${NC}"
    echo -e "${YELLOW}1. 系统更新 (选项2)${NC}"
    echo -e "${YELLOW}2. 系统清理 (选项3)${NC}"
    echo -e "${YELLOW}3. BBR加速优化 (选项4)${NC}"
    echo -e "${YELLOW}4. 设置虚拟内存 (选项5)${NC}"
    echo -e "${YELLOW}5. 修改SSH端口 (选项7)${NC}"
    echo -e "${YELLOW}6. 安装基础工具 (选项8)${NC}"
    echo -e "${YELLOW}7. 内核参数优化 - 均衡模式 (选项11中的均衡模式)${NC}"
    
    read -p "确认执行一键优化? (Y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}取消一键优化${NC}"
        read -p "按回车键继续..."
        return
    fi
    
    echo -e "${BLUE}执行系统更新...${NC}"
    system_update_auto
    
    echo -e "${BLUE}执行系统清理...${NC}"
    system_clean_auto
    
    echo -e "${BLUE}执行BBR加速优化...${NC}"
    enable_bbr_auto
    
    echo -e "${BLUE}设置虚拟内存...${NC}"
    setup_swap_auto
    
    echo -e "${BLUE}修改SSH端口...${NC}"
    change_ssh_port_auto
    
    echo -e "${BLUE}安装基础工具...${NC}"
    install_tools_auto
    
    echo -e "${BLUE}应用内核参数均衡模式优化...${NC}"
    optimize_balanced_auto
    
    echo -e "${GREEN}======= 一键优化完成 =======${NC}"
    read -p "按回车键继续..."
}

# 自动化版本的系统更新函数（无暂停）
system_update_auto() {
    echo -e "${BLUE}======= 系统更新 =======${NC}"
    pkg_manager_run update
    pkg_manager_run upgrade
    echo -e "${GREEN}系统更新完成${NC}"
}

# 自动化版本的系统清理函数（无暂停）
system_clean_auto() {
    echo -e "${BLUE}======= 系统清理 =======${NC}"
    pkg_manager_run autoremove
    case "$PKG_MANAGER" in
        apt) apt clean ;;
        *) yum clean all || dnf clean all ;;
    esac
    journalctl --vacuum-time=7d 2>/dev/null
    find /tmp -type f -mtime +7 -delete 2>/dev/null
    echo -e "${GREEN}系统清理完成${NC}"
}

# 自动化版本的BBR加速优化函数（无暂停）
enable_bbr_auto() {
    echo -e "${BLUE}======= BBR加速优化 =======${NC}"
    if lsmod | grep -q bbr; then
        echo -e "${YELLOW}BBR已启用，无需重复操作。${NC}"
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
}

# 自动化版本的设置虚拟内存函数（无暂停）
setup_swap_auto() {
    echo -e "${BLUE}======= 设置虚拟内存 =======${NC}"
    if swapon --show | grep -q '/swapfile'; then
        echo -e "${YELLOW}警告: 已经存在/swapfile交换文件${NC}"
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
}

# 自动化版本的修改SSH端口函数（无暂停）
change_ssh_port_auto() {
    echo -e "${BLUE}======= 修改SSH端口 =======${NC}"
    if [[ ! -f /etc/ssh/sshd_config ]]; then
        echo -e "${RED}SSH配置不存在${NC}"
        return
    fi
    if ss -tuln | grep -q ":$SSH_PORT "; then
        echo -e "${RED}错误: 端口 $SSH_PORT 已被占用${NC}"
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
}

# 自动化版本的安装基础工具函数（无暂停）
install_tools_auto() {
    echo -e "${BLUE}======= 安装基础工具 =======${NC}"
    pkg_manager_run install curl wget vim htop git unzip zip tar screen tmux
    echo -e "${GREEN}基础工具安装完成${NC}"
}

# 自动化版本的均衡模式优化函数（无暂停）
optimize_balanced_auto() {
    echo -e "${BLUE}======= 均衡模式优化 =======${NC}"
    
    echo -e "${GREEN}优化文件描述符...${NC}"
    ulimit -n 32768
    
    echo -e "${GREEN}优化虚拟内存...${NC}"
    sysctl -w vm.swappiness=30 2>/dev/null
    sysctl -w vm.dirty_ratio=20 2>/dev/null
    sysctl -w vm.dirty_background_ratio=10 2>/dev/null
    sysctl -w vm.overcommit_memory=0 2>/dev/null
    sysctl -w vm.min_free_kbytes=32768 2>/dev/null
    
    echo -e "${GREEN}优化网络设置...${NC}"
    sysctl -w net.core.rmem_max=8388608 2>/dev/null
    sysctl -w net.core.wmem_max=8388608 2>/dev/null
    sysctl -w net.core.netdev_max_backlog=125000 2>/dev/null
    sysctl -w net.core.somaxconn=2048 2>/dev/null
    sysctl -w net.ipv4.tcp_rmem='4096 87380 8388608' 2>/dev/null
    sysctl -w net.ipv4.tcp_wmem='4096 32768 8388608' 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_max_syn_backlog=4096 2>/dev/null
    sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null
    sysctl -w net.ipv4.ip_local_port_range='1024 49151' 2>/dev/null
    
    echo -e "${GREEN}优化缓存管理...${NC}"
    sysctl -w vm.vfs_cache_pressure=75 2>/dev/null
    
    echo -e "${GREEN}优化CPU设置...${NC}"
    sysctl -w kernel.sched_autogroup_enabled=1 2>/dev/null
    
    echo -e "${GREEN}其他优化...${NC}"
    # 还原透明大页面
    echo always > /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null
    # 还原 NUMA balancing
    sysctl -w kernel.numa_balancing=1 2>/dev/null
    
    # 将优化设置永久保存到sysctl.conf
    set_config "vm.swappiness" "30" "$SYSCTL_CONF"
    set_config "vm.dirty_ratio" "20" "$SYSCTL_CONF"
    set_config "vm.dirty_background_ratio" "10" "$SYSCTL_CONF"
    set_config "vm.overcommit_memory" "0" "$SYSCTL_CONF"
    set_config "vm.min_free_kbytes" "32768" "$SYSCTL_CONF"
    set_config "net.core.rmem_max" "8388608" "$SYSCTL_CONF"
    set_config "net.core.wmem_max" "8388608" "$SYSCTL_CONF"
    set_config "net.core.netdev_max_backlog" "125000" "$SYSCTL_CONF"
    set_config "net.core.somaxconn" "2048" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_rmem" "4096 87380 8388608" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_wmem" "4096 32768 8388608" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_congestion_control" "bbr" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_max_syn_backlog" "4096" "$SYSCTL_CONF"
    set_config "net.ipv4.tcp_tw_reuse" "1" "$SYSCTL_CONF"
    set_config "net.ipv4.ip_local_port_range" "1024 49151" "$SYSCTL_CONF"
    set_config "vm.vfs_cache_pressure" "75" "$SYSCTL_CONF"
    set_config "kernel.sched_autogroup_enabled" "1" "$SYSCTL_CONF"
    set_config "kernel.numa_balancing" "1" "$SYSCTL_CONF"
    
    echo -e "${GREEN}均衡模式优化完成${NC}"
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
    echo -e "${GREEN}2. 一键优化${NC}"
    echo -e "${GREEN}3. 系统更新${NC}"
    echo -e "${GREEN}4. 系统清理${NC}"
    echo -e "${GREEN}5. BBR加速优化${NC}"
    echo -e "${GREEN}6. 设置虚拟内存(1G)${NC}"
    echo -e "${GREEN}7. 优化DNS${NC}"
    echo -e "${GREEN}8. 修改SSH端口(5522)${NC}"
    echo -e "${GREEN}9. 安装基础工具${NC}"
    echo -e "${GREEN}10. 设置时区为上海${NC}"
    echo -e "${GREEN}11. 开放所有端口${NC}"
    echo -e "${GREEN}12. 内核参数优化${NC}"
    echo -e "${GREEN}13. 重启服务器${NC}"
    echo -e "${BLUE}--------------------------------------------${NC}"
    echo -e "${YELLOW}14. 在线更新脚本${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo -e "${YELLOW}0. 退出${NC}"
    printf "${YELLOW}请输入选项 [0-14]: ${NC}"
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
            2) one_click_optimization ;;
            3) system_update ;;
            4) system_clean ;;
            5) enable_bbr ;;
            6) setup_swap ;;
            7) optimize_dns ;;
            8) change_ssh_port ;;
            9) install_tools ;;
            10) set_timezone ;;
            11) open_all_ports ;;
            12) kernel_parameter_optimization ;;
            13) reboot_system ;;
            14) update_script ;;
            0) echo -e "${GREEN}感谢使用！${NC}"; exit 0 ;;
            *) echo -e "${RED}无效选项${NC}"; sleep 2 ;;
        esac
    done
}

main "$@"
