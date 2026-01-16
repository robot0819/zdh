#!/bin/bash

###############################################################################
# Nginx 自动配置脚本 - 为 Filebrowser 配置反向代理
# 使用方法: bash nginx-setup.sh
###############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 配置变量
DOMAIN=${NGINX_DOMAIN:-}
FB_PORT=${FB_PORT:-8080}
NGINX_PORT=${NGINX_PORT:-80}
ENABLE_SSL=${ENABLE_SSL:-false}
EMAIL=${SSL_EMAIL:-}

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Nginx 自动配置脚本${NC}"
echo -e "${GREEN}======================================${NC}"

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户或 sudo 运行此脚本${NC}"
    exit 1
fi

# 检测系统类型
if [ -f /etc/debian_version ]; then
    OS="debian"
    PKG_MANAGER="apt-get"
elif [ -f /etc/redhat-release ]; then
    OS="redhat"
    PKG_MANAGER="yum"
else
    echo -e "${RED}不支持的操作系统${NC}"
    exit 1
fi

# 1. 安装 Nginx
echo -e "${YELLOW}[1/5] 检查并安装 Nginx...${NC}"
if ! command -v nginx &> /dev/null; then
    echo "正在安装 Nginx..."
    $PKG_MANAGER update -y
    $PKG_MANAGER install -y nginx
    systemctl enable nginx
    echo -e "${GREEN}Nginx 安装完成${NC}"
else
    echo "Nginx 已安装"
fi

# 2. 询问域名（如果未设置）
if [ -z "$DOMAIN" ]; then
    echo -e "${YELLOW}[2/5] 配置域名...${NC}"
    echo -e "${YELLOW}请选择配置方式：${NC}"
    echo "1) 使用域名（推荐，支持SSL）"
    echo "2) 使用IP地址（不支持SSL）"
    echo "3) 仅本地代理（127.0.0.1）"
    read -p "请选择 [1-3]: " choice

    case $choice in
        1)
            read -p "请输入域名（如：files.example.com）: " DOMAIN
            read -p "是否启用SSL证书？[y/N]: " ssl_choice
            if [[ $ssl_choice =~ ^[Yy]$ ]]; then
                ENABLE_SSL=true
                read -p "请输入邮箱（用于Let's Encrypt）: " EMAIL
            fi
            ;;
        2)
            DOMAIN=$(hostname -I | awk '{print $1}')
            echo "使用IP地址: $DOMAIN"
            ;;
        3)
            DOMAIN="localhost"
            echo "配置为本地代理"
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            exit 1
            ;;
    esac
else
    echo -e "${YELLOW}[2/5] 使用配置的域名: $DOMAIN${NC}"
fi

# 3. 创建 Nginx 配置
echo -e "${YELLOW}[3/5] 创建 Nginx 配置文件...${NC}"

CONFIG_FILE="/etc/nginx/sites-available/filebrowser"
ENABLED_FILE="/etc/nginx/sites-enabled/filebrowser"

# 如果是 RedHat 系列，配置文件路径不同
if [ "$OS" = "redhat" ]; then
    CONFIG_FILE="/etc/nginx/conf.d/filebrowser.conf"
    ENABLED_FILE=""
fi

cat > $CONFIG_FILE <<EOF
# Filebrowser 反向代理配置
# 生成时间: $(date)

upstream filebrowser_backend {
    server 127.0.0.1:${FB_PORT};
    keepalive 32;
}

server {
    listen ${NGINX_PORT};
    listen [::]:${NGINX_PORT};
    server_name ${DOMAIN};

    # 日志
    access_log /var/log/nginx/filebrowser_access.log;
    error_log /var/log/nginx/filebrowser_error.log;

    # 客户端最大上传大小
    client_max_body_size 10G;
    client_body_buffer_size 128k;

    # 超时设置
    proxy_connect_timeout 600;
    proxy_send_timeout 600;
    proxy_read_timeout 600;
    send_timeout 600;

    location / {
        proxy_pass http://filebrowser_backend;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";

        # 缓冲设置
        proxy_buffering off;
        proxy_request_buffering off;
    }

    # 健康检查
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF

# 创建软链接（仅 Debian 系列）
if [ "$OS" = "debian" ] && [ -n "$ENABLED_FILE" ]; then
    ln -sf $CONFIG_FILE $ENABLED_FILE
    # 删除默认配置
    rm -f /etc/nginx/sites-enabled/default
fi

echo "配置文件已创建: $CONFIG_FILE"

# 4. 测试配置
echo -e "${YELLOW}[4/5] 测试 Nginx 配置...${NC}"
if nginx -t; then
    echo -e "${GREEN}配置文件语法正确${NC}"
else
    echo -e "${RED}配置文件有错误，请检查${NC}"
    exit 1
fi

# 5. 启动/重载 Nginx
echo -e "${YELLOW}[5/5] 启动 Nginx...${NC}"
systemctl restart nginx
systemctl status nginx --no-pager | head -10

# 配置 SSL（如果启用）
if [ "$ENABLE_SSL" = true ]; then
    echo -e "${YELLOW}正在配置 SSL 证书...${NC}"

    # 安装 Certbot
    if ! command -v certbot &> /dev/null; then
        echo "安装 Certbot..."
        if [ "$OS" = "debian" ]; then
            $PKG_MANAGER install -y certbot python3-certbot-nginx
        else
            $PKG_MANAGER install -y certbot python3-certbot-nginx
        fi
    fi

    # 获取证书
    certbot --nginx -d $DOMAIN --email $EMAIL --agree-tos --non-interactive --redirect

    # 设置自动续期
    (crontab -l 2>/dev/null; echo "0 3 * * * certbot renew --quiet") | crontab -

    echo -e "${GREEN}SSL 证书配置完成${NC}"
fi

# 完成
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Nginx 配置完成！${NC}"
echo -e "${GREEN}======================================${NC}"

if [ "$ENABLE_SSL" = true ]; then
    echo -e "访问地址: ${GREEN}https://${DOMAIN}${NC}"
else
    echo -e "访问地址: ${GREEN}http://${DOMAIN}:${NGINX_PORT}${NC}"
fi

echo -e "Nginx 配置文件: ${GREEN}${CONFIG_FILE}${NC}"
echo -e "访问日志: ${GREEN}/var/log/nginx/filebrowser_access.log${NC}"
echo -e "错误日志: ${GREEN}/var/log/nginx/filebrowser_error.log${NC}"
echo ""
echo -e "管理命令:"
echo -e "  重启: ${YELLOW}systemctl restart nginx${NC}"
echo -e "  状态: ${YELLOW}systemctl status nginx${NC}"
echo -e "  测试配置: ${YELLOW}nginx -t${NC}"
echo -e "  查看日志: ${YELLOW}tail -f /var/log/nginx/filebrowser_access.log${NC}"
echo -e "${GREEN}======================================${NC}"
