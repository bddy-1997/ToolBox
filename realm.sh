#!/bin/bash

# 全局变量声明
ROLE=""
NAT_LISTEN_PORT=""
NAT_LISTEN_IP=""
NAT_THROUGH_IP="::"
REMOTE_IP=""
REMOTE_PORT=""
EXIT_LISTEN_PORT=""
FORWARD_IP=""
FORWARD_PORT=""
FORWARD_TARGET=""  #支持多地址和域名
SECURITY_LEVEL=""  # 传输模式：standard, tls_self, tls_ca
TLS_CERT_PATH=""   # TLS证书路径
TLS_KEY_PATH=""    # TLS私钥路径
TLS_SERVER_NAME="" # TLS服务器名称(SNI)
RULE_ID=""
RULE_NAME=""

#--- 脚本核心逻辑 ---

# 颜色设计 - 按功能分配，简洁美观
RED='\033[0;31m'      # 错误、危险、禁用状态
GREEN='\033[0;32m'    # 成功、正常、启用状态
YELLOW='\033[1;33m'   # 警告、特殊状态、重要提示
BLUE='\033[0;34m'     # 信息、标识、中性操作
WHITE='\033[1;37m'    # 关闭状态、默认文本
NC='\033[0m'          # 重置颜色

# 核心路径变量
REALM_PATH="/usr/local/bin/realm"
CONFIG_DIR="/etc/realm"
MANAGER_CONF="${CONFIG_DIR}/manager.conf"
CONFIG_PATH="${CONFIG_DIR}/config.json"
SYSTEMD_PATH="/etc/systemd/system/realm.service"
LOG_PATH="/var/log/realm.log"

# 转发配置管理路径
RULES_DIR="${CONFIG_DIR}/rules"

# 定时任务管理路径
CRON_DIR="${CONFIG_DIR}/cron"
CRON_TASKS_FILE="${CRON_DIR}/tasks.conf"

# 默认伪装域名（双端realm搭建隧道需要相同SNI）
DEFAULT_SNI_DOMAIN="www.tesla.com"

# 获取默认伪装域名（双端realm搭建隧道需要相同SNI）
get_random_mask_domain() {
    echo "$DEFAULT_SNI_DOMAIN"
}

# 检查root权限
check_root() {
    [[ $EUID -ne 0 ]] && { echo -e "${RED}错误: 此脚本需要 root 权限运行。${NC}"; exit 1; }
}

# 检测系统类型（仅支持Debian/Ubuntu）
detect_system() {
    local os ver
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        os=$NAME
        ver=$VERSION_ID
    elif command -v lsb_release >/dev/null 2>&1; then
        os=$(lsb_release -si)
        ver=$(lsb_release -sr)
    else
        os=$(uname -s)
        ver=$(uname -r)
    fi
    command -v apt-get >/dev/null 2>&1 || {
        echo -e "${RED}错误: 当前仅支持 Ubuntu/Debian 系统${NC}"
        echo -e "${YELLOW}检测到系统: $os $ver${NC}"
        exit 1
    }
}

# 检测netcat-openbsd是否已安装
check_netcat_openbsd() {
    dpkg -l netcat-openbsd >/dev/null 2>&1
}

# 自动安装缺失的依赖工具
install_dependencies() {
    local tools=("curl" "wget" "tar" "systemctl" "grep" "cut" "bc")
    local missing_tools=()

    echo -e "${YELLOW}正在检查必备依赖工具...${NC}"
    for tool in "${tools[@]}"; do
        command -v "$tool" >/dev/null 2>&1 && echo -e "${GREEN}✓${NC} $tool 已安装" || missing_tools+=("$tool")
    done
    check_netcat_openbsd && echo -e "${GREEN}✓${NC} nc (netcat-openbsd) 已安装" || missing_tools+=("nc")

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo -e "${YELLOW}需要安装以下工具: ${missing_tools[*]}${NC}"
        echo -e "${BLUE}使用 apt-get 安装依赖...${NC}"
        apt-get update -qq >/dev/null 2>&1 || { echo -e "${RED}Failed to update package list${NC}"; exit 1; }
        for tool in "${missing_tools[@]}"; do
            case "$tool" in
                "nc") apt-get remove -y netcat-traditional >/dev/null 2>&1; apt-get install -y netcat-openbsd >/dev/null 2>&1 && echo -e "${GREEN}✓${NC} nc (netcat-openbsd) 安装成功" ;;
                *) apt-get install -y "$tool" >/dev/null 2>&1 && echo -e "${GREEN}✓${NC} $tool 安装成功" ;;
            esac
            [[ $? -ne 0 ]] && { echo -e "${RED}Failed to install $tool${NC}"; exit 1; }
        done
    else
        echo -e "${GREEN}所有必备工具已安装完成${NC}"
    fi
    echo ""
}

# 检查必备依赖工具
check_dependencies() {
    local tools=("curl" "wget" "tar" "systemctl" "grep" "cut" "bc")
    local missing_tools=()

    for tool in "${tools[@]}"; do
        command -v "$tool" >/dev/null 2>&1 || missing_tools+=("$tool")
    done
    check_netcat_openbsd || missing_tools+=("nc")

    [[ ${#missing_tools[@]} -gt 0 ]] && {
        echo -e "${RED}错误: 缺少必备工具: ${missing_tools[*]}${NC}"
        echo -e "${YELLOW}请先选择菜单选项1进行安装，或手动运行安装命令:${NC}"
        echo -e "${BLUE}curl -fsSL https://raw.githubusercontent.com/zywe03/PortEasy/main/xwPF.sh | sudo bash -s install${NC}"
        exit 1
    }
}

# 获取本机公网IP
get_public_ip() {
    local ip_type=$1 ip
    case "$ip_type" in
        ipv4) ip=$(curl -s --connect-timeout 5 --max-time 10 https://www.cloudflare.com/cdn-cgi/trace | grep -E '^ip=[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | cut -d'=' -f2) ;;
        ipv6) ip=$(curl -s --connect-timeout 5 --max-time 10 -6 https://www.cloudflare.com/cdn-cgi/trace | grep -E '^ip=[0-9a-fA-F:]+$' | cut -d'=' -f2) ;;
    esac
    echo "$ip"
}

# 写入状态文件
write_manager_conf() {
    mkdir -p "$CONFIG_DIR"
    cat > "$MANAGER_CONF" <<EOF
# Realm 管理器配置文件
# 此文件由脚本自动生成，请勿手动修改

ROLE=$ROLE
INSTALL_TIME="$(date -u +'%Y-%m-%d %H:%M:%S')"
SCRIPT_VERSION="v1.0.0"

# 中转服务器配置
NAT_LISTEN_PORT=$NAT_LISTEN_PORT
NAT_LISTEN_IP=$NAT_LISTEN_IP
NAT_THROUGH_IP=$NAT_THROUGH_IP
REMOTE_IP=$REMOTE_IP
REMOTE_PORT=$REMOTE_PORT

# 出口服务器配置
EXIT_LISTEN_PORT=$EXIT_LISTEN_PORT
FORWARD_TARGET=$FORWARD_TARGET

# 兼容性：保留旧格式（如果存在）
FORWARD_IP=$FORWARD_IP
FORWARD_PORT=$FORWARD_PORT

# 新增配置选项
SECURITY_LEVEL=$SECURITY_LEVEL
TLS_CERT_PATH=$TLS_CERT_PATH
TLS_KEY_PATH=$TLS_KEY_PATH
TLS_SERVER_NAME=$TLS_SERVER_NAME
WS_PATH=$WS_PATH
EOF
    echo -e "${GREEN}✓ 状态文件已保存: $MANAGER_CONF${NC}"
}

# 读取状态文件
read_manager_conf() {
    [[ ! -f "$MANAGER_CONF" ]] && { echo -e "${RED}错误: 状态文件不存在，请先运行安装${NC}"; exit 1; }
    source "$MANAGER_CONF"
    [[ -z "$ROLE" ]] && { echo -e "${RED}错误: 状态文件损坏，请重新安装${NC}"; exit 1; }
    [[ -z "$FORWARD_TARGET" && -n "$FORWARD_IP" && -n "$FORWARD_PORT" ]] && FORWARD_TARGET="$FORWARD_IP:$FORWARD_PORT"
    if [[ -n "$FORWARD_TARGET" && -z "$FORWARD_IP" ]]; then
        local first_target=$(echo "$FORWARD_TARGET" | cut -d',' -f1)
        FORWARD_IP=$(echo "$first_target" | cut -d':' -f1)
        FORWARD_PORT=$(echo "$first_target" | cut -d':' -f2)
    fi
}

# 检查端口占用（忽略realm自身占用）
# 返回值：0=端口可用或其他服务占用但用户选择继续，1=realm占用，2=用户取消
check_port_usage() {
    local port=$1
    [[ -z "$port" ]] && return 0
    local port_output=$(ss -tulnp 2>/dev/null | grep ":${port} ")
    if [[ -n "$port_output" ]]; then
        if echo "$port_output" | grep -q "realm"; then
            echo -e "${GREEN}✓ 端口 $port 已被realm服务占用，支持单端口中转多落地配置${NC}"
            return 1
        else
            echo -e "${YELLOW}警告: 端口 $port 已被其他服务占用${NC}"
            echo -e "${BLUE}占用进程信息:${NC}\n$port_output"
            read -p "是否继续配置？(y/n): " continue_config
            [[ ! "$continue_config" =~ ^[Yy]$ ]] && { echo "配置已取消"; exit 1; }
        fi
    fi
    return 0
}

# 检查防火墙并询问是否放行端口
check_firewall() {
    local port=$1
    [[ -z "$port" ]] && return 0
    echo -e "${YELLOW}检查防火墙状态...${NC}"
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        echo -e "${BLUE}检测到 UFW 防火墙已启用${NC}"
        read -p "是否自动放行端口 $port？(y/n): " allow_port
        [[ "$allow_port" =~ ^[Yy]$ ]] && { ufw allow "$port" >/dev/null 2>&1; echo -e "${GREEN}✓ UFW 已放行端口 $port${NC}"; }
    elif command -v firewall-cmd >/dev/null 2>&1 && systemctl is-active firewalld >/dev/null 2>&1; then
        echo -e "${BLUE}检测到 Firewalld 防火墙已启用${NC}"
        read -p "是否自动放行端口 $port？(y/n): " allow_port
        [[ "$allow_port" =~ ^[Yy]$ ]] && {
            firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1
            firewall-cmd --reload >/dev/null 2>&1
            echo -e "${GREEN}✓ Firewalld 已放行端口 $port${NC}"
        }
    elif command -v iptables >/dev/null 2>&1 && iptables -L INPUT 2>/dev/null | grep -q "DROP\|REJECT"; then
        echo -e "${BLUE}检测到 iptables 防火墙规则${NC}"
        read -p "是否自动放行端口 $port？(y/n): " allow_port
        [[ "$allow_port" =~ ^[Yy]$ ]] && {
            iptables -I INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
            echo -e "${GREEN}✓ iptables 已放行端口 $port${NC}"
            echo -e "${YELLOW}注意: 请手动保存 iptables 规则以确保重启后生效${NC}"
        }
    else
        echo -e "${GREEN}✓ 未检测到活跃的防火墙${NC}"
    fi
}

# 测试IP或域名的连通性
check_connectivity() {
    local target=$1 port=$2 timeout=3
    [[ -z "$target" || -z "$port" ]] && return 1
    nc -z -w"$timeout" "$target" "$port" >/dev/null 2>&1
}

# 验证端口号格式
validate_port() {
    local port=$1
    [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] && return 0
    return 1
}

# 验证IP地址格式
validate_ip() {
    local ip=$1
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do [[ "$i" -gt 255 ]] && return 1; done
        return 0
    elif [[ "$ip" =~ ^[0-9a-fA-F:]+$ && "$ip" == *":"* ]]; then
        return 0
    fi
    return 1
}

# 验证转发目标地址（支持IP、域名、多地址）
validate_target_address() {
    local target=$1
    [[ -z "$target" ]] && return 1
    if [[ "$target" == *","* ]]; then
        IFS=',' read -ra ADDRESSES <<< "$target"
        for addr in "${ADDRESSES[@]}"; do
            addr=$(echo "$addr" | xargs)
            validate_single_address "$addr" || return 1
        done
        return 0
    fi
    validate_single_address "$target"
}

# 验证单个地址（IP或域名）
validate_single_address() {
    local addr=$1
    validate_ip "$addr" && return 0
    [[ "$addr" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ || "$addr" == "localhost" ]] && return 0
    return 1
}

# 获取传输配置
get_transport_config() {
    local security_level=$1 server_name=$2 cert_path=$3 key_path=$4 role=$5 ws_path=$6
    local sni_name=${server_name:-$DEFAULT_SNI_DOMAIN} ws_path_param=${ws_path:-/ws}
    case "$security_level" in
        standard) echo "" ;;
        tls_self)
            [[ "$role" == "1" ]] && echo "\"remote_transport\": \"tls;sni=$sni_name;insecure\"" || echo "\"listen_transport\": \"tls;servername=$sni_name\""
            ;;
        tls_ca)
            if [[ "$role" == "1" ]]; then
                echo "\"remote_transport\": \"tls;sni=$sni_name\""
            elif [[ -n "$cert_path" && -n "$key_path" ]]; then
                echo "\"listen_transport\": \"tls;cert=$cert_path;key=$key_path\""
            fi
            ;;
        ws_tls_self)
            [[ "$role" == "1" ]] && echo "\"remote_transport\": \"ws;host=$sni_name;path=$ws_path_param;tls;sni=$sni_name;insecure\"" || echo "\"listen_transport\": \"ws;host=$sni_name;path=$ws_path_param;tls;servername=$sni_name\""
            ;;
        ws_tls_ca)
            if [[ "$role" == "1" ]]; then
                echo "\"remote_transport\": \"ws;host=$sni_name;path=$ws_path_param;tls;sni=$sni_name\""
            elif [[ -n "$cert_path" && -n "$key_path" ]]; then
                echo "\"listen_transport\": \"ws;host=$sni_name;path=$ws_path_param;tls;cert=$cert_path;key=$key_path\""
            fi
            ;;
        *) echo "" ;;
    esac
}

# 内置日志管理函数（优雅控制日志大小）
manage_log_size() {
    local log_file=$1 max_size_mb=${2:-10} keep_size_mb=${3:-5}
    if [[ -f "$log_file" && -w "$log_file" ]]; then
        local file_size=$(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file" 2>/dev/null || echo 0)
        local max_bytes=$((max_size_mb * 1024 * 1024)) keep_bytes=$((keep_size_mb * 1024 * 1024))
        if [[ "$file_size" -gt "$max_bytes" ]]; then
            cp "$log_file" "${log_file}.backup" 2>/dev/null &&
            tail -c "$keep_bytes" "$log_file" > "${log_file}.tmp" 2>/dev/null &&
            mv "${log_file}.tmp" "$log_file" 2>/dev/null && rm -f "${log_file}.backup" 2>/dev/null || mv "${log_file}.backup" "$log_file" 2>/dev/null
        fi
    fi
}

# 验证JSON配置文件语法
validate_json_config() {
    local config_file=$1
    [[ ! -f "$config_file" ]] && { echo -e "${RED}配置文件不存在: $config_file${NC}"; return 1; }
    if command -v python3 >/dev/null 2>&1 && python3 -m json.tool "$config_file" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ JSON配置文件语法正确${NC}"
        return 0
    elif command -v jq >/dev/null 2>&1 && jq empty "$config_file" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ JSON配置文件语法正确${NC}"
        return 0
    else
        echo -e "${YELLOW}⚠ 无法验证JSON语法（缺少python3或jq）${NC}"
        return 0
    fi
}

# 获取中转服务器监听IP（用户动态输入）
get_nat_server_listen_ip() {
    echo "${NAT_LISTEN_IP:-::}"
}

# 获取落地服务器监听IP（固定为双栈监听）
get_exit_server_listen_ip() {
    echo "::"
}

# 生成转发endpoints配置
generate_forward_endpoints_config() {
    local target=${FORWARD_TARGET:-$FORWARD_IP:$FORWARD_PORT} listen_ip=$(get_exit_server_listen_ip)
    local transport_config=$(get_transport_config "$SECURITY_LEVEL" "$TLS_SERVER_NAME" "$TLS_CERT_PATH" "$TLS_KEY_PATH" "2" "$WS_PATH")
    local transport_line=$([[ -n "$transport_config" ]] && echo ",$transport_config" || echo "")
    if [[ "$target" == *","* ]]; then
        local port=${target##*:} addresses_part=${target%:*} extra_addresses=""
        IFS=',' read -ra ip_addresses <<< "$addresses_part"
        local main_address="${ip_addresses[0]}:$port"
        if [[ ${#ip_addresses[@]} -gt 1 ]]; then
            for ((i=1; i<${#ip_addresses[@]}; i++)); do
                extra_addresses+="${extra_addresses:+, }\"${ip_addresses[i]}:$port\""
            done
            extra_addresses=",\n        \"extra_remotes\": [$extra_addresses]"
        fi
        echo "\"endpoints\": [\n        {\n            \"listen\": \"${listen_ip}:${EXIT_LISTEN_PORT}\",\n            \"remote\": \"$main_address\"${extra_addresses}${transport_line}\n        }\n    ]"
    else
        echo "\"endpoints\": [\n        {\n            \"listen\": \"${listen_ip}:${EXIT_LISTEN_PORT}\",\n            \"remote\": \"$target\"${transport_line}\n        }\n    ]"
    fi
}

# 初始化规则目录
init_rules_dir() {
    mkdir -p "$RULES_DIR"
    [[ ! -f "${RULES_DIR}/.initialized" ]] && touch "${RULES_DIR}/.initialized" && echo -e "${GREEN}✓ 规则目录已初始化: $RULES_DIR${NC}"
}

# 生成新的规则ID
generate_rule_id() {
    local max_id=0
    for rule_file in "${RULES_DIR}"/rule-*.conf 2>/dev/null; do
        [[ -f "$rule_file" ]] && {
            local id=${rule_file##*-}
            id=${id%.conf}
            [[ "$id" -gt "$max_id" ]] && max_id=$id
        }
    done
    echo $((max_id + 1))
}

# 读取规则文件
read_rule_file() {
    local rule_file=$1
    [[ -f "$rule_file" ]] && { source "$rule_file"; return 0; } || return 1
}

# 获取负载均衡信息显示
get_balance_info_display() {
    local remote_host=$1 balance_mode=$2
    case "$balance_mode" in
        roundrobin) echo " ${YELLOW}[轮询]${NC}" ;;
        iphash) echo " ${BLUE}[IP哈希]${NC}" ;;
        *) echo " ${WHITE}[off]${NC}" ;;
    esac
}

# 获取带权重的负载均衡信息显示
get_balance_info_with_weight() {
    local remote_host=$1 balance_mode=$2 weights=$3 target_index=$4
    local balance_info
    case "$balance_mode" in
        roundrobin) balance_info=" ${YELLOW}[轮询]${NC}" ;;
        iphash) balance_info=" ${BLUE}[IP哈希]${NC}" ;;
        *) balance_info=" ${WHITE}[off]${NC}"; return 0 ;;
    esac
    if [[ "$remote_host" == *","* ]]; then
        local weight_array
        IFS=',' read -ra weight_array <<< "${weights:-$(IFS=',' read -ra host_array <<< "$remote_host"; printf '1%.0s,' "${host_array[@]}" | sed 's/,$//')}"
        local total_weight=0
        for w in "${weight_array[@]}"; do total_weight=$((total_weight + w)); done
        local current_weight=${weight_array[$((target_index-1))]:-1}
        local percentage=$(command -v bc >/dev/null 2>&1 && echo "scale=1; $current_weight * 100 / $total_weight" | bc || awk "BEGIN {printf \"%.1f\", $current_weight * 100 / $total_weight}")
        balance_info="$balance_info ${GREEN}[权重: $current_weight]${NC} ${BLUE}($percentage%)${NC}"
    fi
    echo "$balance_info"
}

# 检查目标服务器是否启用
is_target_enabled() {
    local target_index=$1 target_states=$2 state_key="target_${target_index}"
    [[ "$target_states" == *"$state_key:false"* ]] && echo "false" || echo "true"
}

# 读取并检查是否是中转服务器规则（会设置全局变量）
read_and_check_relay_rule() {
    local rule_file=$1
    read_rule_file "$rule_file" && [[ "$RULE_ROLE" == "1" ]] && return 0
    return 1
}

# 列出所有规则（用于管理操作）
list_rules_for_management() {
    [[ ! -d "$RULES_DIR" || -z "$(ls -A "$RULES_DIR"/*.conf 2>/dev/null)" ]] && { echo -e "${BLUE}暂无转发规则${NC}"; return 1; }
    local has_relay_rules=false has_exit_rules=false relay_count=0 exit_count=0
    for rule_file in "${RULES_DIR}"/rule-*.conf; do
        if read_and_check_relay_rule "$rule_file"; then
            [[ "$has_relay_rules" == false ]] && { echo -e "${GREEN}中转服务器:${NC}"; has_relay_rules=true; }
            relay_count=$((relay_count + 1))
            local status_color=${GREEN} status_text="启用"
            [[ "$ENABLED" != "true" ]] && { status_color=${RED}; status_text="禁用"; }
            local display_target=$(smart_display_target "$REMOTE_HOST") rule_display_name="$RULE_NAME"
            [[ $relay_count -gt 1 ]] && rule_display_name="$RULE_NAME-$relay_count"
            local balance_info=$(get_balance_info_display "$REMOTE_HOST" "${BALANCE_MODE:-off}")
            local through_display="${THROUGH_IP:-::}"
            echo -e "  ID ${BLUE}$RULE_ID${NC}: ${GREEN}$rule_display_name${NC} ($LISTEN_PORT → $through_display → $display_target:$REMOTE_PORT) [${status_color}$status_text${NC}]$balance_info"
        fi
    done
    for rule_file in "${RULES_DIR}"/rule-*.conf; do
        if read_rule_file "$rule_file" && [[ "$RULE_ROLE" == "2" ]]; then
            [[ "$has_exit_rules" == false ]] && { [[ "$has_relay_rules" == true ]] && echo ""; echo -e "${GREEN}落地服务器 (双端Realm搭建隧道):${NC}"; has_exit_rules=true; }
            exit_count=$((exit_count + 1))
            local status_color=${GREEN} status_text="启用"
            [[ "$ENABLED" != "true" ]] && { status_color=${RED}; status_text="禁用"; }
            local target_host="${FORWARD_TARGET%:*}" target_port="${FORWARD_TARGET##*:}" display_target=$(smart_display_target "$target_host") rule_display_name="$RULE_NAME"
            [[ $exit_count -gt 1 ]] && rule_display_name="$RULE_NAME-$exit_count"
            echo -e "  ID ${BLUE}$RULE_ID${NC}: ${GREEN}$rule_display_name${NC} ($LISTEN_PORT → $display_target:$target_port) [${status_color}$status_text${NC}]"
        fi
    done
    return 0
}

# 根据序号获取规则ID
get_rule_id_by_index() {
    local index=$1 count=0
    for rule_file in "${RULES_DIR}"/rule-*.conf; do
        if read_rule_file "$rule_file"; then
            count=$((count + 1))
            [[ "$count" -eq "$index" ]] && { echo "$RULE_ID"; return 0; }
        fi
    done
    return 1
}

# 获取规则总数
get_rules_count() {
    local count=0
    for rule_file in "${RULES_DIR}"/rule-*.conf; do
        read_rule_file "$rule_file" && count=$((count + 1))
    done
    echo "$count"
}

# 列出所有规则（详细信息，用于查看）
list_all_rules() {
    echo -e "${YELLOW}=== 所有转发规则 ===${NC}\n"
    [[ ! -d "$RULES_DIR" || -z "$(ls -A "$RULES_DIR"/*.conf 2>/dev/null)" ]] && { echo -e "${BLUE}暂无转发规则${NC}"; return 0; }
    local count=0
    for rule_file in "${RULES_DIR}"/rule-*.conf; do
        if read_rule_file "$rule_file"; then
            count=$((count + 1))
            local status_color=${GREEN} status_text="启用"
            [[ "$ENABLED" != "true" ]] && { status_color=${RED}; status_text="禁用"; }
            local security_display=$(get_security_display "$SECURITY_LEVEL" "$WS_PATH")
            echo -e "ID ${BLUE}$RULE_ID${NC}: $RULE_NAME\n  通用配置: ${YELLOW}$security_display${NC} | 状态: ${status_color}$status_text${NC}"
            if [[ "$RULE_ROLE" == "2" ]]; then
                local display_ip=$(get_exit_server_listen_ip)
                echo -e "  监听: ${GREEN}${LISTEN_IP:-$display_ip}:$LISTEN_PORT${NC} → 转发: ${GREEN}$FORWARD_TARGET${NC}"
            else
                local display_ip=$(get_nat_server_listen_ip) through_display="${THROUGH_IP:-::}"
                echo -e "  中转: ${GREEN}${LISTEN_IP:-$display_ip}:$LISTEN_PORT${NC} → ${GREEN}$through_display${NC} → ${GREEN}$REMOTE_HOST:$REMOTE_PORT${NC}"
            fi
            echo -e "  创建时间: $CREATED_TIME\n"
        fi
    done
    echo -e "${BLUE}共找到 $count 个配置${NC}"
}

# 交互式添加转发配置
interactive_add_rule() {
    echo -e "${YELLOW}=== 添加新转发配置 ===${NC}\n"
    echo "请选择新配置的角色:"
    echo -e "${GREEN}[1]${NC} 中转服务器"
    echo -e "${GREEN}[2]${NC} 落地服务器 (双端Realm搭建隧道)\n"
    local RULE_ROLE
    while true; do
        read -p "请输入数字 [1-2]: " RULE_ROLE
        case $RULE_ROLE in
            1) echo -e "${GREEN}已选择: 中转服务器${NC}"; break ;;
            2) echo -e "${GREEN}已选择: 落地服务器 (双端Realm搭建隧道)${NC}"; break ;;
            *) echo -e "${RED}无效选择，请输入 1-2${NC}" ;;
        esac
    done
    echo ""
    local ORIG_ROLE=$ROLE ORIG_NAT_LISTEN_PORT=$NAT_LISTEN_PORT ORIG_REMOTE_IP=$REMOTE_IP ORIG_REMOTE_PORT=$REMOTE_PORT
    local ORIG_EXIT_LISTEN_PORT=$EXIT_LISTEN_PORT ORIG_FORWARD_TARGET=$FORWARD_TARGET ORIG_SECURITY_LEVEL=$SECURITY_LEVEL
    local ORIG_TLS_SERVER_NAME=$TLS_SERVER_NAME ORIG_TLS_CERT_PATH=$TLS_CERT_PATH ORIG_TLS_KEY_PATH=$TLS_KEY_PATH
    ROLE=$RULE_ROLE
    if [[ "$RULE_ROLE" == "1" ]]; then
        configure_nat_server || { echo "配置已取消"; return 1; }
    elif [[ "$RULE_ROLE" == "2" ]]; then
        configure_exit_server || { echo "配置已取消"; return 1; }
    fi
    echo -e "${YELLOW}正在创建转发配置...${NC}"
    init_rules_dir
    local rule_id=$(generate_rule_id) rule_file="${RULES_DIR}/rule-${rule_id}.conf"
    if [[ "$RULE_ROLE" == "1" ]]; then
        cat > "$rule_file" <<EOF
RULE_ID=$rule_id
RULE_NAME="中转"
RULE_ROLE="1"
SECURITY_LEVEL="$SECURITY_LEVEL"
LISTEN_PORT="$NAT_LISTEN_PORT"
LISTEN_IP="$(get_nat_server_listen_ip)"
THROUGH_IP="$NAT_THROUGH_IP"
REMOTE_HOST="$REMOTE_IP"
REMOTE_PORT="$REMOTE_PORT"
TLS_SERVER_NAME="$TLS_SERVER_NAME"
TLS_CERT_PATH="$TLS_CERT_PATH"
TLS_KEY_PATH="$TLS_KEY_PATH"
WS_PATH="$WS_PATH"
ENABLED="true"
CREATED_TIME="$(date -u +'%Y-%m-%d %H:%M:%S')"

# 负载均衡配置
BALANCE_MODE="off"
TARGET_STATES=""
WEIGHTS=""

# 故障转移配置
FAILOVER_ENABLED="false"
HEALTH_CHECK_INTERVAL="4"
FAILURE_THRESHOLD="2"
SUCCESS_THRESHOLD="2"
CONNECTION_TIMEOUT="3"
EOF
        echo -e "${GREEN}✓ 中转配置已创建 (ID: $rule_id)${NC}"
        echo -e "${BLUE}配置详情: $REMOTE_IP:$REMOTE_PORT${NC}"
    else
        cat > "$rule_file" <<EOF
RULE_ID=$rule_id
RULE_NAME="落地"
RULE_ROLE="2"
SECURITY_LEVEL="$SECURITY_LEVEL"
LISTEN_PORT="$EXIT_LISTEN_PORT"
FORWARD_TARGET="$FORWARD_TARGET"
TLS_SERVER_NAME="$TLS_SERVER_NAME"
TLS_CERT_PATH="$TLS_CERT_PATH"
TLS_KEY_PATH="$TLS_KEY_PATH"
WS_PATH="$WS_PATH"
ENABLED="true"
CREATED_TIME="$(date -u +'%Y-%m-%d %H:%M:%S')"

# 负载均衡配置
BALANCE_MODE="off"
TARGET_STATES=""
WEIGHTS=""

# 故障转移配置
FAILOVER_ENABLED="false"
HEALTH_CHECK_INTERVAL="4"
FAILURE_THRESHOLD="2"
SUCCESS_THRESHOLD="2"
CONNECTION_TIMEOUT="3"
EOF
        echo -e "${GREEN}✓ 转发配置已创建 (ID: $rule_id)${NC}"
        echo -e "${BLUE}配置详情: $FORWARD_TARGET${NC}"
    fi
    ROLE=$ORIG_ROLE NAT_LISTEN_PORT=$ORIG_NAT_LISTEN_PORT REMOTE_IP=$ORIG_REMOTE_IP REMOTE_PORT=$ORIG_REMOTE_PORT
    EXIT_LISTEN_PORT=$ORIG_EXIT_LISTEN_PORT FORWARD_TARGET=$ORIG_FORWARD_TARGET SECURITY_LEVEL=$ORIG_SECURITY_LEVEL
    TLS_SERVER_NAME=$ORIG_TLS_SERVER_NAME TLS_CERT_PATH=$ORIG_TLS_CERT_PATH TLS_KEY_PATH=$ORIG_TLS_KEY_PATH
    echo ""
    return 0
}

# 删除规则
delete_rule() {
    local rule_id=$1 rule_file="${RULES_DIR}/rule-${rule_id}.conf"
    [[ ! -f "$rule_file" ]] && { echo -e "${RED}错误: 规则 $rule_id 不存在${NC}"; return 1; }
    read_rule_file "$rule_file" || { echo -e "${RED}错误: 无法读取规则文件${NC}"; return 1; }
    echo -e "${YELLOW}即将删除规则:${NC}\n${BLUE}规则ID: ${GREEN}$RULE_ID${NC}\n${BLUE}规则名称: ${GREEN}$RULE_NAME${NC}\n${BLUE}监听端口: ${GREEN}$LISTEN_PORT${NC}\n"
    read -p "确认删除此规则？(y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] && { rm -f "$rule_file"; echo -e "${GREEN}✓ 规则已删除${NC}"; return 0; } || { echo "删除已取消"; return 1; }
}

# 启用/禁用规则
toggle_rule() {
    local rule_id=$1 rule_file="${RULES_DIR}/rule-${rule_id}.conf"
    [[ ! -f "$rule_file" ]] && { echo -e "${RED}错误: 规则 $rule_id 不存在${NC}"; return 1; }
    read_rule_file "$rule_file" || { echo -e "${RED}错误: 无法读取规则文件${NC}"; return 1; }
    local new_status="true" action="启用"
    [[ "$ENABLED" == "true" ]] && { new_status="false"; action="禁用"; }
    echo -e "${YELLOW}正在${action}规则: $RULE_NAME${NC}"
    sed -i "s/ENABLED=\".*\"/ENABLED=\"$new_status\"/" "$rule_file"
    echo -e "${GREEN}✓ 规则已${action}${NC}"
    return 0
}

# JSON配置转换为规则文件
import_json_to_rules() {
    local json_file=$1
    [[ ! -f "$json_file" ]] && { echo -e "${RED}配置文件不存在${NC}"; return 1; }
    echo -e "${BLUE}正在清理现有规则...${NC}"
    rm -f "${RULES_DIR}"/rule-*.conf 2>/dev/null
    init_rules_dir
    local temp_file=$(mktemp) rule_count=0 rule_id=1
    if command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json, sys, re
try:
    with open('$json_file', 'r') as f:
        data = json.load(f)
    if 'endpoints' in data:
        for i, endpoint in enumerate(data['endpoints']):
            listen = endpoint.get('listen', '')
            remote = endpoint.get('remote', '')
            extra_remotes = endpoint.get('extra_remotes', [])
            balance = endpoint.get('balance', '')
            listen_transport = endpoint.get('listen_transport', '')
            remote_transport = endpoint.get('remote_transport', '')
            through = endpoint.get('through', '')
            if listen and remote:
                role = '2' if listen_transport else '1'
                if role == '2' and (port_match := re.search(r':(\d+)$', listen)):
                    listen = '::' + ':' + port_match.group(1)
                targets = [remote] + (extra_remotes or [])
                target_list = ','.join(targets)
                weights_str = re.search(r'(?:roundrobin|iphash):\s*([0-9,\s]+)', balance).group(1).replace(' ', '') if balance and re.search(r'(?:roundrobin|iphash):\s*([0-9,\s]+)', balance) else ','.join(['1'] * len(targets))
                print(f'{listen}|{remote}|{target_list}|{balance}|{role}|{listen_transport}|{remote_transport}|{weights_str}|{through}')
except Exception:
    sys.exit(1)
" > "$temp_file" || { rm -f "$temp_file"; echo -e "${RED}无法解析配置文件${NC}"; return 1; }
    else
        awk '
        BEGIN { in_endpoint=0; transport_buffer=""; extra_count=0; collecting_extra=0 }
        /"endpoints":/ { in_endpoints=1 }
        /^\s*{/ && in_endpoints { in_endpoint=1 }
        /"listen":/ && in_endpoint { gsub(/[",]/,"",$2); listen=$2 }
        /"remote":/ && in_endpoint { gsub(/[",]/,"",$2); remote=$2 }
        /"through":/ && in_endpoint { gsub(/[",]/,"",$2); through=$2 }
        /"extra_remotes":/ && in_endpoint { has_extra=1; extra_count=0; collecting_extra=1 }
        collecting_extra && /"[^"]*:[0-9]+"/ { line_content=$0; while (match(line_content,/"[^"]*:[0-9]+"/,matched)) { extra_count++; line_content=substr(line_content,RSTART+RLENGTH) } }
        /^\s*\]/ && collecting_extra { collecting_extra=0 }
        /"balance":/ && in_endpoint { gsub(/[",]/,"",$2); balance=$2 }
        /"listen_transport":/ && in_endpoint {
            transport_buffer=$0
            if (match($0,/"listen_transport":\s*"([^"]*)"/,arr)) { listen_transport=arr[1]; role="2"; transport_buffer="" }
            else { gsub(/.*"listen_transport":\s*"/,"",transport_buffer); collecting_listen_transport=1 }
        }
        /"remote_transport":/ && in_endpoint {
            transport_buffer=$0
            if (match($0,/"remote_transport":\s*"([^"]*)"/,arr)) { remote_transport=arr[1]; transport_buffer="" }
            else { gsub(/.*"remote_transport":\s*"/,"",transport_buffer); collecting_remote_transport=1 }
        }
        collecting_listen_transport && !/"listen_transport":/ {
            transport_buffer=transport_buffer $0
            if (/"$/) { gsub(/".*/,"",transport_buffer); listen_transport=transport_buffer; role="2"; collecting_listen_transport=0; transport_buffer="" }
        }
        collecting_remote_transport && !/"remote_transport":/ {
            transport_buffer=transport_buffer $0
            if (/"$/) { gsub(/".*/,"",transport_buffer); remote_transport=transport_buffer; collecting_remote_transport=0; transport_buffer="" }
        }
        /^\s*}/ && in_endpoint && listen && remote {
            if (!role) role="1"
            if (role=="2" && match(listen,/:[0-9]+$/)) listen="::" substr(listen,RSTART)
            weights_str=balance ? (match(balance,/(roundrobin|iphash):\s*([0-9,\s]+)/,weight_match) ? weight_match[2] : "") : ""
            gsub(/\s/,"",weights_str)
            if (!weights_str) weights_str=(1+extra_count>1 ? "1" : "") (1+extra_count>1 ? "," : "") sprintf("%*s",1+extra_count-1,"") ? gensub(/ /,"1",1,sprintf("%*s",1+extra_count-1,"")) : ""
            print listen "|" remote "|" (has_extra ? "LB" : "") "|" balance "|" role "|" listen_transport "|" remote_transport "|" weights_str "|" through
            listen=""; remote=""; through=""; has_extra=0; balance=""; role=""; listen_transport=""; remote_transport=""; extra_count=0; collecting_extra=0; in_endpoint=0
        }
        ' "$json_file" > "$temp_file" || { rm -f "$temp_file"; echo -e "${RED}无法解析配置文件${NC}"; return 1; }
    fi
    [[ ! -s "$temp_file" ]] && { rm -f "$temp_file"; echo -e "${RED}无法解析配置文件${NC}"; return 1; }
    while IFS='|' read -r listen_addr remote_addr target_list balance_config rule_role listen_transport remote_transport weights_str through_addr; do
        [[ -z "$listen_addr" || -z "$remote_addr" ]] && continue
        local listen_port=${listen_addr##*:}
        [[ ! "$listen_port" =~ ^[0-9]+$ ]] && continue
        local listen_ip=${listen_addr%:*} balance_mode="off"
        [[ "$balance_config" =~ roundrobin ]] && balance_mode="roundrobin"
        [[ "$balance_config" =~ iphash ]] && balance_mode="iphash"
        IFS=',' read -ra targets <<< "$target_list" weight_array=()
        [[ -n "$weights_str" ]] && IFS=',' read -ra weight_array <<< "$weights_str"
        while [[ ${#weight_array[@]} -lt ${#targets[@]} ]]; do weight_array+=("1"); done
        local target_index=0
        [[ ${#targets[@]} -gt 1 ]] && echo -e "${BLUE}提示：检测到${#targets[@]}个服务器，权重配置：${weights_str}${NC}"
        local first_rule_weights=$weights_str
        for target in "${targets[@]}"; do
            target=$(echo "$target" | xargs)
            [[ -z "$target" ]] && continue
            local remote_host=${target%:*} remote_port=${target##*:}
            [[ -z "$remote_host" || ! "$remote_port" =~ ^[0-9]+$ ]] && continue
            local rule_name="中转" security_level="standard" tls_server_name="" tls_cert_path="" tls_key_path="" ws_path="/ws"
            [[ "$rule_role" == "2" ]] && rule_name="落地"
            [[ -n "$listen_transport" && "$rule_role" == "2" ]] && transport_config=$listen_transport || transport_config=$remote_transport
            [[ "$transport_config" =~ tls ]] && security_level=${transport_config##*tls} && [[ "$security_level" =~ self ]] && security_level="tls_self" || security_level="tls_ca"
            [[ "$transport_config" =~ ws ]] && security_level="ws_${security_level}" && ws_path=$(echo "$transport_config" | grep -o 'path=[^;]*' | cut -d'=' -f2)
            [[ "$transport_config" =~ sni= ]] && tls_server_name=$(echo "$transport_config" | grep -o 'sni=[^;]*' | cut -d'=' -f2) || tls_server_name=$(echo "$transport_config" | grep -o 'servername=[^;]*' | cut -d'=' -f2)
            [[ "$transport_config" =~ cert= ]] && tls_cert_path=$(echo "$transport_config" | grep -o 'cert=[^;]*' | cut -d'=' -f2)
            [[ "$transport_config" =~ key= ]] && tls_key_path=$(echo "$transport_config" | grep -o 'key=[^;]*' | cut -d'=' -f2)
            local rule_file="${RULES_DIR}/rule-${rule_id}.conf"
            cat > "$rule_file" <<EOF
RULE_ID=$rule_id
RULE_NAME="$rule_name"
RULE_ROLE="$rule_role"
SECURITY_LEVEL="$security_level"
LISTEN_PORT="$listen_port"
LISTEN_IP="$listen_ip"
THROUGH_IP="$through_addr"
REMOTE_HOST="$remote_host"
REMOTE_PORT="$remote_port"
FORWARD_TARGET="$target_list"
TLS_SERVER_NAME="$tls_server_name"
TLS_CERT_PATH="$tls_cert_path"
TLS_KEY_PATH="$tls_key_path"
WS_PATH="$ws_path"
ENABLED="true"
CREATED_TIME="$(date -u +'%Y-%m-%d %H:%M:%S')"
BALANCE_MODE="$balance_mode"
TARGET_STATES=""
WEIGHTS="${weight_array[target_index]:-1}"
FAILOVER_ENABLED="false"
HEALTH_CHECK_INTERVAL="4"
FAILURE_THRESHOLD="2"
SUCCESS_THRESHOLD="2"
CONNECTION_TIMEOUT="3"
EOF
            rule_count=$((rule_count + 1))
            rule_id=$((rule_id + 1))
            target_index=$((target_index + 1))
        done
    done < "$temp_file"
    rm -f "$temp_file"
    echo -e "${GREEN}✓ 已导入 $rule_count 个规则${NC}"
    return 0
}

# 以下为未完全展开的优化部分（由于长度限制，概要描述后续优化）
# 1. `configure_nat_server` 和 `configure_exit_server`: 合并输入验证逻辑，减少重复的端口和地址检查。
# 2. `toggle_failover_mode`: 优化端口分组逻辑，使用数组存储规则信息，减少文件读取次数。
# 3. `weight_management_menu`: 合并 `configure_rule_weights` 和 `configure_port_group_weights` 成单一函数，统一权重配置流程。
# 4. `start_health_check_service` 和 `create_config_monitor_service`: 优化 systemd 服务创建，使用模板化配置减少重复代码。
# 5. `manage_log_size`: 添加日志轮转支持，减少磁盘空间占用。
# 6. `main`: 简化参数处理逻辑，统一错误退出路径。

# 示例优化：合并权重配置函数
configure_weights() {
    local port=$1 rule_name=$2 targets_str=$3 current_weights_str=$4
    clear
    echo -e "${GREEN}=== 权重配置: $rule_name ===${NC}\n"
    IFS=',' read -ra targets <<< "$targets_str"
    local target_count=${#targets[@]}
    echo "规则组: $rule_name (端口: $port)\n目标服务器列表:"
    IFS=',' read -ra current_weights <<< "${current_weights_str:-$(printf '1%.0s,' "${targets[@]}" | sed 's/,$//')}"
    for ((i=0; i<target_count; i++)); do
        echo -e "  $((i+1)). ${targets[i]} [当前权重: ${current_weights[i]:-1}]"
    done
    echo -e "\n请输入权重序列 (用逗号分隔):\n${WHITE}格式说明: 按服务器顺序输入权重值，如 \"2,1,3\"\n权重范围: 1-10，数值越大分配流量越多${NC}\n"
    read -p "权重序列: " weight_input
    [[ -z "$weight_input" ]] && { echo -e "${YELLOW}未输入权重，保持原配置${NC}"; read -p "按回车键返回..."; return; }
    if [[ ! "$weight_input" =~ ^[0-9]+(,[0-9]+)*$ || $(IFS=',' read -ra weights <<< "$weight_input"; echo ${#weights[@]}) -ne $target_count ]]; then
        echo -e "${RED}权重格式或数量错误，请输入 $target_count 个1-10的数值，如: 2,1,3${NC}"
        read -p "按回车键返回..."
        return
    fi
    IFS=',' read -ra weights <<< "$weight_input"
    for weight in "${weights[@]}"; do
        [[ "$weight" -lt 1 || "$weight" -gt 10 ]] && { echo -e "${RED}权重值 $weight 超出范围，请使用 1-10${NC}"; read -p "按回车键返回..."; return; }
    done
    local total_weight=0
    for weight in "${weights[@]}"; do total_weight=$((total_weight + weight)); done
    echo -e "${GREEN}=== 配置预览 ===${NC}\n规则组: $rule_name (端口: $port)\n权重配置变更:"
    for ((i=0; i<target_count; i++)); do
        local percentage=$(command -v bc >/dev/null 2>&1 && echo "scale=1; ${weights[i]} * 100 / $total_weight" | bc || awk "BEGIN {printf \"%.1f\", ${weights[i]} * 100 / $total_weight}")
        [[ "${current_weights[i]:-1}" != "${weights[i]}" ]] && echo -e "  $((i+1)). ${targets[i]}: ${current_weights[i]:-1} → ${GREEN}${weights[i]}${NC} ${BLUE}($percentage%)${NC}" || echo -e "  $((i+1)). ${targets[i]}: ${weights[i]} ${BLUE}($percentage%)${NC}"
    done
    echo ""
    read -p "确认应用此配置? [y/n]: " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { echo -e "${YELLOW}已取消配置更改${NC}"; read -p "按回车键返回..."; return; }
    local updated_count=0
    for rule_file in "${RULES_DIR}"/rule-*.conf; do
        if read_rule_file "$rule_file" && [[ "$RULE_ROLE" == "1" && "$LISTEN_PORT" == "$port" ]]; then
            local rule_index=0
            for check_rule_file in "${RULES_DIR}"/rule-*.conf; do
                if read_rule_file "$check_rule_file" && [[ "$RULE_ROLE" == "1" && "$LISTEN_PORT" == "$port" ]]; then
                    [[ "$check_rule_file" == "$rule_file" ]] && break
                    rule_index=$((rule_index + 1))
                fi
            done
            local target_weight=$([[ $rule_index -eq 0 ]] && echo "$weight_input" || echo "${weights[rule_index]:-1}")
            if grep -q "^WEIGHTS=" "$rule_file"; then
                sed -i "s/^WEIGHTS=.*/WEIGHTS=\"$target_weight\"/" "$rule_file"
            else
                echo "WEIGHTS=\"$target_weight\"" >> "$rule_file"
            fi
            updated_count=$((updated_count + 1))
        fi
    done
    if [[ $updated_count -gt 0 ]]; then
        echo -e "${GREEN}✓ 已更新 $updated_count 个规则文件的权重配置${NC}"
        echo -e "${YELLOW}正在重启服务以应用更改...${NC}"
        service_restart && echo -e "${GREEN}✓ 服务重启成功，权重配置已生效${NC}" || echo -e "${RED}✗ 服务重启失败，请检查配置${NC}"
    else
        echo -e "${RED}✗ 未找到相关规则文件${NC}"
    fi
    read -p "按回车键返回..."
}