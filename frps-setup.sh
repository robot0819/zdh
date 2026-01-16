#!/bin/bash

###############################################################################
# FRP 服务端自动部署脚本
# 使用方法: bash frps-setup.sh
###############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置变量
FRP_VERSION=${FRP_VERSION:-"0.58.1"}
BIND_PORT=${FRPS_BIND_PORT:-7000}
VHOST_HTTP_PORT=${FRPS_VHOST_HTTP_PORT:-8080}
VHOST_HTTPS_PORT=${FRPS_VHOST_HTTPS_PORT:-8443}
DASHBOARD_PORT=${FRPS_DASHBOARD_PORT:-7500}
DASHBOARD_USER=${FRPS_DASHBOARD_USER:-"admin"}
DASHBOARD_PWD=${FRPS_DASHBOARD_PWD:-"admin123456"}
TOKEN=${FRPS_TOKEN:-}

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}FRP 服务端自动部署脚本${NC}"
echo -e "${GREEN}======================================${NC}"

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户或 sudo 运行此脚本${NC}"
    exit 1
fi

# 生成随机 Token（如果未设置）
if [ -z "$TOKEN" ]; then
    TOKEN=$(openssl rand -hex 16)
    echo -e "${YELLOW}已生成随机 Token: ${TOKEN}${NC}"
fi

# 1. 下载 FRP
echo -e "${YELLOW}[1/6] 下载 FRP v${FRP_VERSION}...${NC}"
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
echo -e "${YELLOW}[2/6] 解压并安装...${NC}"
tar -zxf "${FRP_FILE}.tar.gz"
cd "${FRP_FILE}"

# 复制文件到系统目录
mkdir -p /etc/frp
cp frps /usr/local/bin/
chmod +x /usr/local/bin/frps

echo "FRP 服务端已安装到 /usr/local/bin/frps"

# 3. 创建配置文件
echo -e "${YELLOW}[3/6] 创建配置文件...${NC}"
cat > /etc/frp/frps.toml <<EOF
# FRP 服务端配置
# 生成时间: $(date)

# 服务端绑定地址和端口
bindAddr = "0.0.0.0"
bindPort = ${BIND_PORT}

# 虚拟主机端口
vhostHTTPPort = ${VHOST_HTTP_PORT}
vhostHTTPSPort = ${VHOST_HTTPS_PORT}

# 认证 Token（客户端必须使用相同的 Token）
auth.method = "token"
auth.token = "${TOKEN}"

# 控制面板配置
webServer.addr = "0.0.0.0"
webServer.port = ${DASHBOARD_PORT}
webServer.user = "${DASHBOARD_USER}"
webServer.password = "${DASHBOARD_PWD}"

# 日志配置
log.to = "/var/log/frps.log"
log.level = "info"
log.maxDays = 7

# 允许的端口范围
# allowPorts = [
#   { start = 10000, end = 10100 }
# ]

# 子域名配置（如果需要）
# subDomainHost = "example.com"

# 最大连接数
transport.maxPoolCount = 50

# TCP 多路复用
transport.tcpMux = true
transport.tcpMuxKeepaliveInterval = 60
EOF

echo "配置文件已创建: /etc/frp/frps.toml"

# 4. 创建 systemd 服务
echo -e "${YELLOW}[4/6] 创建 systemd 服务...${NC}"
cat > /etc/systemd/system/frps.service <<EOF
[Unit]
Description=FRP Server Service
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.toml
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

echo "systemd 服务已创建"

# 5. 配置防火墙
echo -e "${YELLOW}[5/6] 配置防火墙...${NC}"
if command -v ufw &> /dev/null; then
    echo "检测到 UFW 防火墙，正在配置..."
    ufw allow ${BIND_PORT}/tcp comment 'FRP Server'
    ufw allow ${VHOST_HTTP_PORT}/tcp comment 'FRP HTTP'
    ufw allow ${VHOST_HTTPS_PORT}/tcp comment 'FRP HTTPS'
    ufw allow ${DASHBOARD_PORT}/tcp comment 'FRP Dashboard'
    echo "UFW 规则已添加"
elif command -v firewall-cmd &> /dev/null; then
    echo "检测到 firewalld，正在配置..."
    firewall-cmd --permanent --add-port=${BIND_PORT}/tcp
    firewall-cmd --permanent --add-port=${VHOST_HTTP_PORT}/tcp
    firewall-cmd --permanent --add-port=${VHOST_HTTPS_PORT}/tcp
    firewall-cmd --permanent --add-port=${DASHBOARD_PORT}/tcp
    firewall-cmd --reload
    echo "firewalld 规则已添加"
else
    echo -e "${YELLOW}未检测到防火墙，请手动开放端口${NC}"
fi

# 6. 启动服务
echo -e "${YELLOW}[6/6] 启动服务...${NC}"
systemctl daemon-reload
systemctl enable frps
systemctl start frps

sleep 2

# 检查服务状态
if systemctl is-active --quiet frps; then
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}FRP 服务端部署成功！${NC}"
    echo -e "${GREEN}======================================${NC}"

    SERVER_IP=$(hostname -I | awk '{print $1}')

    echo -e "服务器信息:"
    echo -e "  IP地址: ${GREEN}${SERVER_IP}${NC}"
    echo -e "  服务端口: ${GREEN}${BIND_PORT}${NC}"
    echo -e "  HTTP端口: ${GREEN}${VHOST_HTTP_PORT}${NC}"
    echo -e "  HTTPS端口: ${GREEN}${VHOST_HTTPS_PORT}${NC}"
    echo -e "  认证Token: ${GREEN}${TOKEN}${NC}"
    echo ""
    echo -e "管理面板:"
    echo -e "  地址: ${GREEN}http://${SERVER_IP}:${DASHBOARD_PORT}${NC}"
    echo -e "  用户名: ${GREEN}${DASHBOARD_USER}${NC}"
    echo -e "  密码: ${GREEN}${DASHBOARD_PWD}${NC}"
    echo ""
    echo -e "配置文件: ${GREEN}/etc/frp/frps.toml${NC}"
    echo -e "日志文件: ${GREEN}/var/log/frps.log${NC}"
    echo ""
    echo -e "服务管理命令:"
    echo -e "  启动: ${YELLOW}systemctl start frps${NC}"
    echo -e "  停止: ${YELLOW}systemctl stop frps${NC}"
    echo -e "  重启: ${YELLOW}systemctl restart frps${NC}"
    echo -e "  状态: ${YELLOW}systemctl status frps${NC}"
    echo -e "  查看日志: ${YELLOW}tail -f /var/log/frps.log${NC}"
    echo ""
    echo -e "${YELLOW}重要提示：请保存 Token，客户端连接时需要使用！${NC}"
    echo -e "${GREEN}======================================${NC}"

    # 保存配置信息
    cat > /root/frps-info.txt <<EOF
FRP 服务端配置信息
生成时间: $(date)

服务器IP: ${SERVER_IP}
服务端口: ${BIND_PORT}
HTTP端口: ${VHOST_HTTP_PORT}
HTTPS端口: ${VHOST_HTTPS_PORT}
认证Token: ${TOKEN}

管理面板: http://${SERVER_IP}:${DASHBOARD_PORT}
用户名: ${DASHBOARD_USER}
密码: ${DASHBOARD_PWD}

配置文件: /etc/frp/frps.toml
日志文件: /var/log/frps.log
EOF

    echo -e "${GREEN}配置信息已保存到: /root/frps-info.txt${NC}"
else
    echo -e "${RED}服务启动失败，请查看日志: tail -f /var/log/frps.log${NC}"
    exit 1
fi
