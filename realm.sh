#!/bin/bash

# 定义全局变量
ROLE=""  # 服务器角色：relay（中转）或 exit（落地）
LISTEN_PORT=""  # 监听端口
LISTEN_IP="::"  # 监听 IP，默认支持 IPv4 和 IPv6 双栈
REMOTE_IP=""  # 远程服务器 IP（中转服务器用）
REMOTE_PORT=""  # 远程服务器端口（中转服务器用）
FORWARD_TARGET=""  # 转发目标地址（落地服务器用）
SECURITY_MODE="standard"  # 安全模式：standard（无加密）、tls_self（自签名 TLS）、tls_ca（CA 证书 TLS）
TLS_CERT=""  # TLS 证书路径
TLS_KEY=""  # TLS 私钥路径
TLS_SNI="www.example.com"  # 默认 SNI 域名

# 定义核心路径
INSTALL_DIR="/usr/local/portforward"
CONFIG_DIR="${INSTALL_DIR}/config"
CONFIG_FILE="${CONFIG_DIR}/config.json"
RULES_DIR="${CONFIG_DIR}/rules"
LOG_FILE="/var/log/portforward.log"
SERVICE_FILE="/etc/systemd/system/portforward.service"

# 定义颜色代码
RED='\033[0;31m'    # 错误提示
GREEN='\033[0;32m'  # 成功提示
YELLOW='\033[1;33m' # 警告提示
BLUE='\033[0;34m'   # 信息提示
NC='\033[0m'        # 重置颜色

# 检查 root 权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo -e "${RED}错误：请以 root 权限运行此脚本${NC}"
        exit 1
    fi
}

# 检查系统是否为 Ubuntu/Debian
check_system() {
    if ! command -v apt-get >/dev/null 2>&1; then
        echo -e "${RED}错误：仅支持 Ubuntu/Debian 系统${NC}"
        exit 1
    fi
}

# 安装必要依赖
install_dependencies() {
    echo -e "${YELLOW}正在检查和安装依赖...${NC}"
    local dependencies=("curl" "netcat-openbsd" "jq")
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            echo -e "${BLUE}安装 $dep...${NC}"
            apt-get update -qq && apt-get install -y "$dep" >/dev/null 2>&1 || {
                echo -e "${RED}安装 $dep 失败${NC}"
                exit 1
            }
        else
            echo -e "${GREEN}$dep 已安装${NC}"
        fi
    done
}

# 获取公网 IP
get_public_ip() {
    local ip_type="$1"  # ipv4 或 ipv6
    if [ "$ip_type" = "ipv4" ]; then
        curl -s --connect-timeout 5 https://api.ipify.org
    else
        curl -s --connect-timeout 5 -6 https://api6.ipify.org
    fi
}

# 验证端口格式
validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    echo -e "${RED}错误：端口 $port 无效（必须为 1-65535）${NC}"
    return 1
}

# 验证 IP 或域名格式
validate_address() {
    local addr="$1"
    # 检查 IPv4
    if [[ "$addr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra octets <<< "$addr"
        for o in "${octets[@]}"; do
            [ "$o" -gt 255 ] && return 1
        done
        return 0
    fi
    # 检查 IPv6
    if [[ "$addr" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$addr" == *":"* ]]; then
        return 0
    fi
    # 检查域名
    if [[ "$addr" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]] || [ "$addr" = "localhost" ]; then
        return 0
    fi
    echo -e "${RED}错误：地址 $addr 格式无效${NC}"
    return 1
}

# 检查端口占用
check_port() {
    local port="$1"
    if ss -tuln | grep -q ":${port} "; then
        echo -e "${YELLOW}警告：端口 $port 已被占用${NC}"
        read -p "是否继续？(y/n): " confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && return 1
    fi
    return 0
}

# 检查防火墙并放行端口
open_firewall() {
    local port="$1"
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
        echo -e "${BLUE}检测到 UFW 防火墙${NC}"
        read -p "是否放行端口 $port？(y/n): " allow
        if [[ "$allow" =~ ^[Yy]$ ]]; then
            ufw allow "$port" >/dev/null 2>&1
            echo -e "${GREEN}已放行端口 $port${NC}"
        fi
    fi
}

# 配置中转服务器
configure_relay() {
    echo -e "${YELLOW}配置中转服务器${NC}"
    read -p "请输入监听端口: " LISTEN_PORT
    validate_port "$LISTEN_PORT" || return 1
    check_port "$LISTEN_PORT" || return 1
    open_firewall "$LISTEN_PORT"

    read -p "请输入远程服务器 IP 或域名: " REMOTE_IP
    validate_address "$REMOTE_IP" || return 1
    read -p "请输入远程服务器端口: " REMOTE_PORT
    validate_port "$REMOTE_PORT" || return 1

    echo -e "${BLUE}选择安全模式：1) 无加密 2) 自签名 TLS 3) CA 证书 TLS${NC}"
    read -p "请输入选择 [1-3]: " mode
    case "$mode" in
        1) SECURITY_MODE="standard" ;;
        2) SECURITY_MODE="tls_self" ;;
        3) 
            SECURITY_MODE="tls_ca"
            read -p "请输入 TLS 证书路径: " TLS_CERT
            read -p "请输入 TLS 私钥路径: " TLS_KEY
            [ ! -f "$TLS_CERT" ] || [ ! -f "$TLS_KEY" ] && {
                echo -e "${RED}证书或私钥文件不存在${NC}"
                return 1
            }
            ;;
        *) 
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
    read -p "请输入 TLS SNI 域名（默认 $TLS_SNI）: " input_sni
    [ -n "$input_sni" ] && TLS_SNI="$input_sni"
    ROLE="relay"
}

# 配置落地服务器
configure_exit() {
    echo -e "${YELLOW}配置落地服务器${NC}"
    read -p "请输入监听端口: " LISTEN_PORT
    validate_port "$LISTEN_PORT" || return 1
    check_port "$LISTEN_PORT" || return 1
    open_firewall "$LISTEN_PORT"

    read -p "请输入转发目标（IP:端口）: " FORWARD_TARGET
    validate_address "${FORWARD_TARGET%:*}" || return 1
    validate_port "${FORWARD_TARGET##*:}" || return 1

    echo -e "${BLUE}选择安全模式：1) 无加密 2) 自签名 TLS 3) CA 证书 TLS${NC}"
    read -p "请输入选择 [1-3]: " mode
    case "$mode" in
        1) SECURITY_MODE="standard" ;;
        2) SECURITY_MODE="tls_self" ;;
        3) 
            SECURITY_MODE="tls_ca"
            read -p "请输入 TLS 证书路径: " TLS_CERT
            read -p "请输入 TLS 私钥路径: " TLS_KEY
            [ ! -f "$TLS_CERT" ] || [ ! -f "$TLS_KEY" ] && {
                echo -e "${RED}证书或私钥文件不存在${NC}"
                return 1
            }
            ;;
        *) 
            echo -e "${RED}无效选择${NC}"
            return 1
            ;;
    esac
    read -p "请输入 TLS SNI 域名（默认 $TLS_SNI）: " input_sni
    [ -n "$input_sni" ] && TLS_SNI="$input_sni"
    ROLE="exit"
}

# 生成配置文件
generate_config() {
    mkdir -p "$CONFIG_DIR" "$RULES_DIR"
    local rule_id=$(date +%s)
    local rule_file="${RULES_DIR}/rule-${rule_id}.conf"

    # 保存规则
    cat > "$rule_file" << EOF
ROLE=$ROLE
LISTEN_PORT=$LISTEN_PORT
LISTEN_IP=$LISTEN_IP
REMOTE_IP=$REMOTE_IP
REMOTE_PORT=$REMOTE_PORT
FORWARD_TARGET=$FORWARD_TARGET
SECURITY_MODE=$SECURITY_MODE
TLS_CERT=$TLS_CERT
TLS_KEY=$TLS_KEY
TLS_SNI=$TLS_SNI
ENABLED=true
CREATED_TIME=$(date '+%Y-%m-%d %H:%M:%S')
EOF

    # 生成 JSON 配置文件
    local transport=""
    if [ "$SECURITY_MODE" = "tls_self" ]; then
        transport="\"transport\": \"tls;sni=$TLS_SNI${ROLE="relay" && ";insecure" || ""}\""
    elif [ "$SECURITY_MODE" = "tls_ca" ] && [ "$ROLE" = "exit" ]; then
        transport="\"transport\": \"tls;cert=$TLS_CERT;key=$TLS_KEY\""
    fi

    if [ "$ROLE" = "relay" ]; then
        cat > "$CONFIG_FILE" << EOF
{
    "endpoints": [
        {
            "listen": "${LISTEN_IP}:${LISTEN_PORT}",
            "remote": "${REMOTE_IP}:${REMOTE_PORT}"${transport:+, $transport}
        }
    ]
}
EOF
    else
        cat > "$CONFIG_FILE" << EOF
{
    "endpoints": [
        {
            "listen": "${LISTEN_IP}:${LISTEN_PORT}",
            "remote": "${FORWARD_TARGET}"${transport:+, $transport}
        }
    ]
}
EOF
    fi

    if command -v jq >/dev/null 2>&1 && ! jq . "$CONFIG_FILE" >/dev/null 2>&1; then
        echo -e "${RED}JSON 配置文件语法错误${NC}"
        return 1
    fi
    echo -e "${GREEN}配置已保存：$rule_file${NC}"
}

# 安装服务
install_service() {
    echo -e "${YELLOW}安装端口转发服务...${NC}"
    check_system
    install_dependencies

    # 下载端口转发二进制文件（假设使用 realm）
    if [ ! -f "$REALM_PATH" ]; then
        curl -sL "https://github.com/zhboner/realm/releases/latest/download/realm" -o "$REALM_PATH"
        chmod +x "$REALM_PATH"
    fi

    # 创建 systemd 服务
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Port Forward Service
After=network.target

[Service]
Type=simple
ExecStart=$REALM_PATH -c $CONFIG_FILE
Restart=always
RestartSec=5
StandardOutput=append:$LOG_FILE
StandardError=append:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable portforward.service >/dev/null 2>&1
    systemctl start portforward.service >/dev/null 2>&1
    echo -e "${GREEN}服务安装并启动成功${NC}"
}

# 列出规则
list_rules() {
    echo -e "${YELLOW}当前转发规则：${NC}"
    if [ ! -d "$RULES_DIR" ] || ! ls "$RULES_DIR"/rule-*.conf >/dev/null 2>&1; then
        echo -e "${BLUE}暂无规则${NC}"
        return
    fi

    for rule in "$RULES_DIR"/rule-*.conf; do
        [ -f "$rule" ] || continue
        source "$rule"
        local status="${GREEN}启用${NC}"
        [ "$ENABLED" != "true" ] && status="${RED}禁用${NC}"
        if [ "$ROLE" = "relay" ]; then
            echo -e "ID: ${rule##*-} 角色: 中转 监听: ${LISTEN_IP}:${LISTEN_PORT} -> 目标: ${REMOTE_IP}:${REMOTE_PORT} 状态: $status"
        else
            echo -e "ID: ${rule##*-} 角色: 落地 监听: ${LISTEN_IP}:${LISTEN_PORT} -> 目标: ${FORWARD_TARGET} 状态: $status"
        fi
    done
}

# 删除规则
delete_rule() {
    read -p "请输入要删除的规则 ID: " rule_id
    local rule_file="${RULES_DIR}/rule-${rule_id}.conf"
    if [ ! -f "$rule_file" ]; then
        echo -e "${RED}规则 $rule_id 不存在${NC}"
        return 1
    fi
    rm -f "$rule_file"
    echo -e "${GREEN}规则 $rule_id 已删除${NC}"
    generate_config && systemctl restart portforward.service
}

# 主菜单
show_menu() {
    while true; do
        clear
        echo -e "${GREEN}=== 端口转发管理脚本 ===${NC}"
        list_rules
        echo -e "\n操作选项："
        echo -e "${GREEN}1.${NC} 安装服务"
        echo -e "${BLUE}2.${NC} 添加中转规则"
        echo -e "${BLUE}3.${NC} 添加落地规则"
        echo -e "${YELLOW}4.${NC} 删除规则"
        echo -e "${GREEN}5.${NC} 重启服务"
        echo -e "${RED}6.${NC} 卸载服务"
        echo -e "${YELLOW}7.${NC} 退出"
        read -p "请输入选择 [1-7]: " choice

        case "$choice" in
            1)
                install_service
                read -p "按回车继续..."
                ;;
            2)
                configure_relay && generate_config && systemctl restart portforward.service
                read -p "按回车继续..."
                ;;
            3)
                configure_exit && generate_config && systemctl restart portforward.service
                read -p "按回车继续..."
                ;;
            4)
                delete_rule
                read -p "按回车继续..."
                ;;
            5)
                systemctl restart portforward.service && echo -e "${GREEN}服务已重启${NC}"
                read -p "按回车继续..."
                ;;
            6)
                systemctl stop portforward.service
                systemctl disable portforward.service
                rm -rf "$INSTALL_DIR" "$SERVICE_FILE" "$LOG_FILE"
                systemctl daemon-reload
                echo -e "${GREEN}服务已卸载${NC}"
                read -p "按回车继续..."
                ;;
            7)
                echo -e "${BLUE}退出脚本${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                read -p "按回车继续..."
                ;;
        esac
    done
}

# 主逻辑
main() {
    check_root
    if [ "$1" = "install" ]; then
        install_service
    else
        show_menu
    fi
}

main "$@"
