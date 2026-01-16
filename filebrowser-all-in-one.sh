#!/bin/bash

###############################################################################
# Filebrowser 完整自动化部署脚本
# 集成: Filebrowser + Nginx + FRP
# 使用方法: bash filebrowser-all-in-one.sh
###############################################################################

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}  Filebrowser 完整自动化部署脚本${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""
echo "此脚本将帮助您配置以下组件："
echo "1. Filebrowser 文件管理器"
echo "2. Nginx 反向代理（可选）"
echo "3. FRP 内网穿透（可选）"
echo ""

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户或 sudo 运行此脚本${NC}"
    exit 1
fi

# ============================================
# 步骤1: 选择部署模式
# ============================================
echo -e "${GREEN}步骤1: 选择部署模式${NC}"
echo "请选择您的部署场景："
echo ""
echo "1) 【公网服务器】完整部署（Filebrowser + Nginx）"
echo "   - 适用于有公网IP的服务器"
echo "   - 可配置域名和SSL证书"
echo "   - 通过Nginx反向代理访问"
echo ""
echo "2) 【公网服务器】仅部署 Filebrowser"
echo "   - 直接通过端口访问"
echo "   - 不使用Nginx"
echo ""
echo "3) 【内网服务器】使用 FRP 穿透"
echo "   - 内网服务器通过FRP暴露到公网"
echo "   - 需要先在公网服务器部署FRP服务端"
echo ""
echo "4) 【FRP服务器】仅部署 FRP 服务端"
echo "   - 在公网服务器搭建FRP服务端"
echo "   - 供内网客户端连接使用"
echo ""

read -p "请选择 [1-4]: " DEPLOY_MODE

case $DEPLOY_MODE in
    1)
        echo -e "${YELLOW}选择: 公网服务器 - 完整部署${NC}"
        INSTALL_FILEBROWSER=true
        INSTALL_NGINX=true
        INSTALL_FRP_CLIENT=false
        INSTALL_FRP_SERVER=false
        ;;
    2)
        echo -e "${YELLOW}选择: 公网服务器 - 仅Filebrowser${NC}"
        INSTALL_FILEBROWSER=true
        INSTALL_NGINX=false
        INSTALL_FRP_CLIENT=false
        INSTALL_FRP_SERVER=false
        ;;
    3)
        echo -e "${YELLOW}选择: 内网服务器 - FRP穿透${NC}"
        INSTALL_FILEBROWSER=true
        INSTALL_NGINX=false
        INSTALL_FRP_CLIENT=true
        INSTALL_FRP_SERVER=false
        ;;
    4)
        echo -e "${YELLOW}选择: 仅部署FRP服务端${NC}"
        INSTALL_FILEBROWSER=false
        INSTALL_NGINX=false
        INSTALL_FRP_CLIENT=false
        INSTALL_FRP_SERVER=true
        ;;
    *)
        echo -e "${RED}无效选择${NC}"
        exit 1
        ;;
esac

echo ""

# ============================================
# 步骤2: 部署 Filebrowser
# ============================================
if [ "$INSTALL_FILEBROWSER" = true ]; then
    echo -e "${GREEN}步骤2: 部署 Filebrowser${NC}"

    # 设置配置
    read -p "Filebrowser 端口 [默认: 8080]: " FB_PORT
    FB_PORT=${FB_PORT:-8080}

    read -p "根目录路径 [默认: /root]: " FB_ROOT
    FB_ROOT=${FB_ROOT:-/root}

    read -p "管理员用户名 [默认: admin]: " FB_USER
    FB_USER=${FB_USER:-admin}

    read -sp "管理员密码 (至少12位) [默认: adminadmin123]: " FB_PASS
    echo ""
    FB_PASS=${FB_PASS:-adminadmin123}

    # 检查脚本是否存在
    if [ ! -f "/root/filebrowser-deploy.sh" ]; then
        echo -e "${RED}错误: 找不到 filebrowser-deploy.sh${NC}"
        echo "请确保该脚本在 /root 目录下"
        exit 1
    fi

    # 导出配置并运行
    export FB_PORT FB_ROOT FB_USER FB_PASS
    bash /root/filebrowser-deploy.sh

    echo ""
fi

# ============================================
# 步骤3: 部署 Nginx
# ============================================
if [ "$INSTALL_NGINX" = true ]; then
    echo -e "${GREEN}步骤3: 配置 Nginx 反向代理${NC}"

    read -p "是否配置 Nginx？[y/N]: " configure_nginx
    if [[ $configure_nginx =~ ^[Yy]$ ]]; then
        # 检查脚本是否存在
        if [ ! -f "/root/nginx-setup.sh" ]; then
            echo -e "${RED}错误: 找不到 nginx-setup.sh${NC}"
            echo "请确保该脚本在 /root 目录下"
            exit 1
        fi

        # 设置配置
        read -p "域名或IP [默认: $(hostname -I | awk '{print $1}')]: " NGINX_DOMAIN
        NGINX_DOMAIN=${NGINX_DOMAIN:-$(hostname -I | awk '{print $1}')}

        read -p "是否启用 SSL？[y/N]: " enable_ssl
        if [[ $enable_ssl =~ ^[Yy]$ ]]; then
            ENABLE_SSL=true
            read -p "邮箱（用于Let's Encrypt）: " SSL_EMAIL
            export SSL_EMAIL
        else
            ENABLE_SSL=false
        fi

        # 导出配置并运行
        export NGINX_DOMAIN ENABLE_SSL FB_PORT
        bash /root/nginx-setup.sh
    fi

    echo ""
fi

# ============================================
# 步骤4: 部署 FRP 客户端
# ============================================
if [ "$INSTALL_FRP_CLIENT" = true ]; then
    echo -e "${GREEN}步骤4: 配置 FRP 客户端${NC}"

    # 检查脚本是否存在
    if [ ! -f "/root/frpc-setup.sh" ]; then
        echo -e "${RED}错误: 找不到 frpc-setup.sh${NC}"
        echo "请确保该脚本在 /root 目录下"
        exit 1
    fi

    # 设置配置
    read -p "FRP 服务器地址（IP或域名）: " FRPS_SERVER_ADDR
    read -p "FRP 服务器端口 [默认: 7000]: " FRPS_SERVER_PORT
    FRPS_SERVER_PORT=${FRPS_SERVER_PORT:-7000}

    read -p "服务端 Token: " FRPS_TOKEN

    # 导出配置并运行
    export FRPS_SERVER_ADDR FRPS_SERVER_PORT FRPS_TOKEN
    export FRPC_LOCAL_PORT=$FB_PORT
    bash /root/frpc-setup.sh

    echo ""
fi

# ============================================
# 步骤5: 部署 FRP 服务端
# ============================================
if [ "$INSTALL_FRP_SERVER" = true ]; then
    echo -e "${GREEN}步骤5: 部署 FRP 服务端${NC}"

    # 检查脚本是否存在
    if [ ! -f "/root/frps-setup.sh" ]; then
        echo -e "${RED}错误: 找不到 frps-setup.sh${NC}"
        echo "请确保该脚本在 /root 目录下"
        exit 1
    fi

    # 设置配置
    read -p "服务端口 [默认: 7000]: " FRPS_BIND_PORT
    FRPS_BIND_PORT=${FRPS_BIND_PORT:-7000}

    read -p "HTTP端口 [默认: 8080]: " FRPS_VHOST_HTTP_PORT
    FRPS_VHOST_HTTP_PORT=${FRPS_VHOST_HTTP_PORT:-8080}

    read -p "管理面板端口 [默认: 7500]: " FRPS_DASHBOARD_PORT
    FRPS_DASHBOARD_PORT=${FRPS_DASHBOARD_PORT:-7500}

    # 导出配置并运行
    export FRPS_BIND_PORT FRPS_VHOST_HTTP_PORT FRPS_DASHBOARD_PORT
    bash /root/frps-setup.sh

    echo ""
fi

# ============================================
# 完成
# ============================================
echo -e "${BLUE}================================================${NC}"
echo -e "${GREEN}          部署完成！          ${NC}"
echo -e "${BLUE}================================================${NC}"

if [ "$INSTALL_FILEBROWSER" = true ]; then
    echo -e "${YELLOW}Filebrowser 信息:${NC}"
    if [ "$INSTALL_NGINX" = true ]; then
        echo -e "  访问地址: http://${NGINX_DOMAIN}"
    else
        echo -e "  访问地址: http://$(hostname -I | awk '{print $1}'):${FB_PORT}"
    fi
    echo -e "  用户名: ${FB_USER}"
    echo -e "  密码: ${FB_PASS}"
    echo ""
fi

if [ "$INSTALL_FRP_SERVER" = true ]; then
    echo -e "${YELLOW}FRP 服务端信息已保存到: /root/frps-info.txt${NC}"
    echo ""
fi

if [ "$INSTALL_FRP_CLIENT" = true ]; then
    echo -e "${YELLOW}FRP 客户端信息已保存到: /root/frpc-info.txt${NC}"
    echo ""
fi

echo -e "详细信息请查看各组件的日志和配置文件"
echo -e "${BLUE}================================================${NC}"
