#!/bin/bash

# FileBrowser 一键部署脚本
# 显示根目录: /home
# 随机生成账号和密码

set -e

echo "======================================"
echo "FileBrowser 一键部署脚本"
echo "======================================"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行此脚本${NC}"
    exit 1
fi

# 检查是否已安装 FileBrowser
echo -e "${YELLOW}检查是否已安装 FileBrowser...${NC}"
ALREADY_INSTALLED=false

if [ -f "/etc/systemd/system/filebrowser.service" ] || [ -d "/opt/filebrowser" ] || pgrep -x "filebrowser" > /dev/null; then
    ALREADY_INSTALLED=true
    echo -e "${YELLOW}检测到系统已安装 FileBrowser${NC}"
fi

# 如果已安装，进行清理
if [ "$ALREADY_INSTALLED" = true ]; then
    echo -e "${RED}正在移除旧的 FileBrowser 安装...${NC}"

    # 停止服务
    if systemctl is-active --quiet filebrowser 2>/dev/null; then
        echo -e "${YELLOW}停止 FileBrowser 服务...${NC}"
        systemctl stop filebrowser
    fi

    # 禁用服务
    if systemctl is-enabled --quiet filebrowser 2>/dev/null; then
        echo -e "${YELLOW}禁用 FileBrowser 服务...${NC}"
        systemctl disable filebrowser
    fi

    # 删除 systemd 服务文件
    if [ -f "/etc/systemd/system/filebrowser.service" ]; then
        echo -e "${YELLOW}删除 systemd 服务文件...${NC}"
        rm -f /etc/systemd/system/filebrowser.service
        systemctl daemon-reload
    fi

    # 杀死残留进程
    if pgrep -x "filebrowser" > /dev/null; then
        echo -e "${YELLOW}终止 FileBrowser 进程...${NC}"
        pkill -9 filebrowser || true
    fi

    # 删除安装目录（包括配置和数据库）
    if [ -d "/opt/filebrowser" ]; then
        echo -e "${YELLOW}删除安装目录 /opt/filebrowser...${NC}"
        rm -rf /opt/filebrowser
    fi

    # 清理可能存在的其他位置的 filebrowser 二进制文件
    if [ -f "/usr/local/bin/filebrowser" ]; then
        echo -e "${YELLOW}删除 /usr/local/bin/filebrowser...${NC}"
        rm -f /usr/local/bin/filebrowser
    fi

    if [ -f "/usr/bin/filebrowser" ]; then
        echo -e "${YELLOW}删除 /usr/bin/filebrowser...${NC}"
        rm -f /usr/bin/filebrowser
    fi

    echo -e "${GREEN}旧的 FileBrowser 安装已完全移除${NC}"
    echo -e "${YELLOW}注意: /home/screenshot 目录中的数据已保留${NC}"
    echo ""
fi

# 生成随机字符串函数
generate_random_string() {
    local length=$1
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w $length | head -n 1
}

# 生成随机用户名和密码
USERNAME="admin_$(generate_random_string 6)"
PASSWORD=$(generate_random_string 16)

echo -e "${YELLOW}正在生成随机凭证...${NC}"
echo "用户名: $USERNAME"
echo "密码: $PASSWORD"
echo ""

# 检测系统架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        FB_ARCH="amd64"
        ;;
    aarch64|arm64)
        FB_ARCH="arm64"
        ;;
    armv7l)
        FB_ARCH="armv7"
        ;;
    *)
        echo -e "${RED}不支持的架构: $ARCH${NC}"
        exit 1
        ;;
esac

echo -e "${YELLOW}检测到系统架构: $ARCH (FileBrowser: $FB_ARCH)${NC}"

# 创建工作目录
INSTALL_DIR="/opt/filebrowser"
DATA_DIR="/home/screenshot"
CONFIG_FILE="$INSTALL_DIR/filebrowser.json"
DB_FILE="$INSTALL_DIR/filebrowser.db"

echo -e "${YELLOW}创建目录结构...${NC}"
mkdir -p $INSTALL_DIR
mkdir -p $DATA_DIR

# 下载 FileBrowser
echo -e "${YELLOW}下载 FileBrowser...${NC}"
cd $INSTALL_DIR

# 获取最新版本
LATEST_VERSION=$(curl -s https://api.github.com/repos/filebrowser/filebrowser/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

if [ -z "$LATEST_VERSION" ]; then
    echo -e "${RED}无法获取最新版本，使用默认版本 2.27.0${NC}"
    LATEST_VERSION="2.27.0"
fi

echo -e "${GREEN}最新版本: v$LATEST_VERSION${NC}"

# 下载 FileBrowser
DOWNLOAD_URL="https://github.com/filebrowser/filebrowser/releases/download/v${LATEST_VERSION}/linux-${FB_ARCH}-filebrowser.tar.gz"
echo -e "${YELLOW}下载地址: $DOWNLOAD_URL${NC}"

curl -L -o filebrowser.tar.gz "$DOWNLOAD_URL"

# 解压
echo -e "${YELLOW}解压文件...${NC}"
tar -xzf filebrowser.tar.gz
chmod +x filebrowser
rm filebrowser.tar.gz

# 创建配置文件
echo -e "${YELLOW}创建配置文件...${NC}"
cat > $CONFIG_FILE <<EOF
{
  "port": 8080,
  "baseURL": "",
  "address": "0.0.0.0",
  "log": "stdout",
  "database": "$DB_FILE",
  "root": "$DATA_DIR"
}
EOF

# 初始化数据库并创建用户
echo -e "${YELLOW}初始化数据库...${NC}"
cd $INSTALL_DIR
./filebrowser config init --config $CONFIG_FILE
./filebrowser config set --address 0.0.0.0 --port 8080 --config $CONFIG_FILE
./filebrowser config set --root $DATA_DIR --config $CONFIG_FILE

# 创建用户
echo -e "${YELLOW}创建管理员用户...${NC}"
./filebrowser users add $USERNAME $PASSWORD --perm.admin --config $CONFIG_FILE

# 创建 systemd 服务
echo -e "${YELLOW}创建 systemd 服务...${NC}"
cat > /etc/systemd/system/filebrowser.service <<EOF
[Unit]
Description=FileBrowser Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/filebrowser -c $CONFIG_FILE
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 重新加载 systemd
systemctl daemon-reload

# 启动服务
echo -e "${YELLOW}启动 FileBrowser 服务...${NC}"
systemctl start filebrowser
systemctl enable filebrowser

# 检查服务状态
sleep 2
if systemctl is-active --quiet filebrowser; then
    echo -e "${GREEN}FileBrowser 服务启动成功！${NC}"
else
    echo -e "${RED}FileBrowser 服务启动失败，请检查日志: journalctl -u filebrowser -f${NC}"
    exit 1
fi

# 获取服务器IP
SERVER_IP=$(curl -s ifconfig.me || curl -s icanhazip.com || hostname -I | awk '{print $1}')

# 输出信息
echo ""
echo "======================================"
echo -e "${GREEN}FileBrowser 部署完成！${NC}"
echo "======================================"
echo ""
echo -e "${GREEN}访问信息：${NC}"
echo "----------------------------"
echo -e "访问地址: ${YELLOW}http://$SERVER_IP:8080${NC}"
echo -e "用户名: ${YELLOW}$USERNAME${NC}"
echo -e "密码: ${YELLOW}$PASSWORD${NC}"
echo -e "根目录: ${YELLOW}$DATA_DIR${NC}"
echo ""
echo -e "${GREEN}服务管理命令：${NC}"
echo "----------------------------"
echo "启动服务: systemctl start filebrowser"
echo "停止服务: systemctl stop filebrowser"
echo "重启服务: systemctl restart filebrowser"
echo "查看状态: systemctl status filebrowser"
echo "查看日志: journalctl -u filebrowser -f"
echo ""
echo -e "${RED}重要提示：请务必保存好上述登录凭证！${NC}"
echo ""

# 保存凭证到文件
CREDENTIALS_FILE="$INSTALL_DIR/credentials.txt"
cat > $CREDENTIALS_FILE <<EOF
FileBrowser 登录凭证
=====================
访问地址: http://$SERVER_IP:8080
用户名: $USERNAME
密码: $PASSWORD
根目录: $DATA_DIR

部署时间: $(date '+%Y-%m-%d %H:%M:%S')
EOF

chmod 600 $CREDENTIALS_FILE
echo -e "${GREEN}登录凭证已保存到: $CREDENTIALS_FILE${NC}"
echo ""
