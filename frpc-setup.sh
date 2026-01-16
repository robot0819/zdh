#!/bin/bash

###############################################################################
# FRP 客户端自动部署脚本 - 用于内网服务器
# 使用方法: bash frpc-setup.sh
###############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置变量
FRP_VERSION=${FRP_VERSION:-"0.58.1"}
SERVER_ADDR=${FRPS_SERVER_ADDR:-}
SERVER_PORT=${FRPS_SERVER_PORT:-7000}
TOKEN=${FRPS_TOKEN:-}
LOCAL_PORT=${FRPC_LOCAL_PORT:-8080}
REMOTE_PORT=${FRPC_REMOTE_PORT:-}
PROXY_NAME=${FRPC_PROXY_NAME:-"filebrowser"}
PROXY_TYPE=${FRPC_PROXY_TYPE:-"http"}
CUSTOM_DOMAIN=${FRPC_CUSTOM_DOMAIN:-}

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}FRP 客户端自动部署脚本${NC}"
echo -e "${GREEN}======================================${NC}"

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户或 sudo 运行此脚本${NC}"
    exit 1
fi

# 询问配置信息
if [ -z "$SERVER_ADDR" ]; then
    read -p "请输入 FRP 服务器地址（IP或域名）: " SERVER_ADDR
fi

if [ -z "$TOKEN" ]; then
    read -p "请输入服务端 Token: " TOKEN
fi

echo -e "${YELLOW}请选择代理类型：${NC}"
echo "1) HTTP/HTTPS（通过域名访问，推荐）"
echo "2) TCP（直接端口映射）"
read -p "请选择 [1-2]: " proxy_choice

case $proxy_choice in
    1)
        PROXY_TYPE="http"
        if [ -z "$CUSTOM_DOMAIN" ]; then
            read -p "请输入自定义域名（如：files.example.com）: " CUSTOM_DOMAIN
        fi
        ;;
    2)
        PROXY_TYPE="tcp"
        if [ -z "$REMOTE_PORT" ]; then
            read -p "请输入远程端口（服务器端口）: " REMOTE_PORT
        fi
        ;;
    *)
        echo -e "${RED}无效选择${NC}"
        exit 1
        ;;
esac

# 1. 下载 FRP
echo -e "${YELLOW}[1/5] 下载 FRP v${FRP_VERSION}...${NC}"
ARCH=$(uname -m)
case $ARCH in
    x86_64)
        FRP_ARCH="amd64"
        ;;
    aarch64)
        FRP_ARCH="arm64"
        ;;
    armv7l)
        FRP_ARCH="arm"
        ;;
    *)
        echo -e "${RED}不支持的架构: $ARCH${NC}"
        exit 1
        ;;
esac

FRP_FILE="frp_${FRP_VERSION}_linux_${FRP_ARCH}"
DOWNLOAD_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${FRP_FILE}.tar.gz"

cd /tmp
if [ -f "${FRP_FILE}.tar.gz" ]; then
    rm -f "${FRP_FILE}.tar.gz"
fi

echo "下载地址: $DOWNLOAD_URL"
wget -O "${FRP_FILE}.tar.gz" "$DOWNLOAD_URL" || {
    echo -e "${RED}下载失败，请检查网络或版本号${NC}"
    exit 1
}

# 2. 解压安装
echo -e "${YELLOW}[2/5] 解压并安装...${NC}"
tar -zxf "${FRP_FILE}.tar.gz"
cd "${FRP_FILE}"

# 复制文件到系统目录
mkdir -p /etc/frp
cp frpc /usr/local/bin/
chmod +x /usr/local/bin/frpc

echo "FRP 客户端已安装到 /usr/local/bin/frpc"

# 3. 创建配置文件
echo -e "${YELLOW}[3/5] 创建配置文件...${NC}"

if [ "$PROXY_TYPE" = "http" ]; then
    # HTTP 代理配置
    cat > /etc/frp/frpc.toml <<EOF
# FRP 客户端配置 - HTTP 模式
# 生成时间: $(date)

# 服务器连接配置
serverAddr = "${SERVER_ADDR}"
serverPort = ${SERVER_PORT}

# 认证配置
auth.method = "token"
auth.token = "${TOKEN}"

# 日志配置
log.to = "/var/log/frpc.log"
log.level = "info"
log.maxDays = 7

# 连接池
transport.poolCount = 5

# HTTP 代理配置
[[proxies]]
name = "${PROXY_NAME}"
type = "http"
localIP = "127.0.0.1"
localPort = ${LOCAL_PORT}
customDomains = ["${CUSTOM_DOMAIN}"]

# HTTPS 代理配置（可选）
# [[proxies]]
# name = "${PROXY_NAME}-https"
# type = "https"
# localIP = "127.0.0.1"
# localPort = ${LOCAL_PORT}
# customDomains = ["${CUSTOM_DOMAIN}"]
EOF

    ACCESS_INFO="访问地址: http://${CUSTOM_DOMAIN}"
else
    # TCP 代理配置
    cat > /etc/frp/frpc.toml <<EOF
# FRP 客户端配置 - TCP 模式
# 生成时间: $(date)

# 服务器连接配置
serverAddr = "${SERVER_ADDR}"
serverPort = ${SERVER_PORT}

# 认证配置
auth.method = "token"
auth.token = "${TOKEN}"

# 日志配置
log.to = "/var/log/frpc.log"
log.level = "info"
log.maxDays = 7

# 连接池
transport.poolCount = 5

# TCP 代理配置
[[proxies]]
name = "${PROXY_NAME}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${LOCAL_PORT}
remotePort = ${REMOTE_PORT}
EOF

    ACCESS_INFO="访问地址: http://${SERVER_ADDR}:${REMOTE_PORT}"
fi

echo "配置文件已创建: /etc/frp/frpc.toml"

# 4. 创建 systemd 服务
echo -e "${YELLOW}[4/5] 创建 systemd 服务...${NC}"
cat > /etc/systemd/system/frpc.service <<EOF
[Unit]
Description=FRP Client Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/frpc -c /etc/frp/frpc.toml
ExecReload=/bin/kill -s HUP \$MAINPID
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

echo "systemd 服务已创建"

# 5. 启动服务
echo -e "${YELLOW}[5/5] 启动服务...${NC}"
systemctl daemon-reload
systemctl enable frpc
systemctl start frpc

sleep 2

# 检查服务状态
if systemctl is-active --quiet frpc; then
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}FRP 客户端部署成功！${NC}"
    echo -e "${GREEN}======================================${NC}"

    echo -e "连接信息:"
    echo -e "  服务器地址: ${GREEN}${SERVER_ADDR}:${SERVER_PORT}${NC}"
    echo -e "  代理类型: ${GREEN}${PROXY_TYPE}${NC}"
    echo -e "  本地端口: ${GREEN}${LOCAL_PORT}${NC}"

    if [ "$PROXY_TYPE" = "http" ]; then
        echo -e "  自定义域名: ${GREEN}${CUSTOM_DOMAIN}${NC}"
    else
        echo -e "  远程端口: ${GREEN}${REMOTE_PORT}${NC}"
    fi

    echo ""
    echo -e "${ACCESS_INFO}"
    echo ""
    echo -e "配置文件: ${GREEN}/etc/frp/frpc.toml${NC}"
    echo -e "日志文件: ${GREEN}/var/log/frpc.log${NC}"
    echo ""
    echo -e "服务管理命令:"
    echo -e "  启动: ${YELLOW}systemctl start frpc${NC}"
    echo -e "  停止: ${YELLOW}systemctl stop frpc${NC}"
    echo -e "  重启: ${YELLOW}systemctl restart frpc${NC}"
    echo -e "  状态: ${YELLOW}systemctl status frpc${NC}"
    echo -e "  查看日志: ${YELLOW}tail -f /var/log/frpc.log${NC}"
    echo -e "${GREEN}======================================${NC}"

    # 保存配置信息
    cat > /root/frpc-info.txt <<EOF
FRP 客户端配置信息
生成时间: $(date)

服务器地址: ${SERVER_ADDR}:${SERVER_PORT}
代理类型: ${PROXY_TYPE}
本地端口: ${LOCAL_PORT}
$([ "$PROXY_TYPE" = "http" ] && echo "自定义域名: ${CUSTOM_DOMAIN}" || echo "远程端口: ${REMOTE_PORT}")

${ACCESS_INFO}

配置文件: /etc/frp/frpc.toml
日志文件: /var/log/frpc.log
EOF

    echo -e "${GREEN}配置信息已保存到: /root/frpc-info.txt${NC}"
else
    echo -e "${RED}服务启动失败，请查看日志: tail -f /var/log/frpc.log${NC}"
    exit 1
fi
