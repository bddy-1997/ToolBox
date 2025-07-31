#!/bin/bash

# 检查是否以root权限运行（安装Java需要）
if [ "$EUID" -ne 0 ]; then
    echo "This script needs to be run with sudo to install Java if it's not present."
    exit 1
fi

# 检查Java是否安装
if ! command -v java &> /dev/null; then
    echo "Java not found. Installing OpenJDK 17..."
    # 更新包列表并安装OpenJDK 17
    apt-get update
    apt-get install -y openjdk-17-jdk
    if [ $? -eq 0 ]; then
        echo "OpenJDK 17 installed successfully."
    else
        echo "Failed to install OpenJDK 17. Please install it manually and rerun the script."
        exit 1
    fi
else
    # 检查Java版本
    JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}' | cut -d. -f1)
    if [ "$JAVA_VERSION" -lt 17 ]; then
        echo "Java version is less than 17. Installing OpenJDK 17..."
        apt-get update
        apt-get install -y openjdk-17-jdk
        if [ $? -eq 0 ]; then
            echo "OpenJDK 17 installed successfully."
        else
            echo "Failed to install OpenJDK 17. Please install it manually and rerun the script."
            exit 1
        fi
    else
        echo "Java 17 or higher is already installed."
    fi
fi

# 设置输出配置文件路径
CONFIG_FILE="$HOME/keystore_credentials.env"

# 生成随机密码和别名
KEYSTORE_PASSWORD=$(openssl rand -base64 12)
KEY_ALIAS="alias_$(openssl rand -hex 4)"
KEY_PASSWORD=$(openssl rand -base64 12)

# 创建或覆盖配置文件
cat << EOF > "$CONFIG_FILE"
# Keystore Credentials
export KEYSTORE_PASSWORD="$KEYSTORE_PASSWORD"
export KEY_ALIAS="$KEY_ALIAS"
export KEY_PASSWORD="$KEY_PASSWORD"
EOF

# 设置文件权限，只有所有者可读写
chmod 600 "$CONFIG_FILE"

# 更改文件所有者为当前用户（因为脚本以sudo运行）
chown "$SUDO_USER:$SUDO_USER" "$CONFIG_FILE"

echo "Keystore credentials have been generated and saved to $CONFIG_FILE"
echo "You can source the file to use these variables:"
echo "source $CONFIG_FILE"
echo
echo "Generated credentials:"
echo "KEYSTORE_PASSWORD: $KEYSTORE_PASSWORD"
echo "KEY_ALIAS: $KEY_ALIAS"
echo "KEY_PASSWORD: $KEY_PASSWORD"
