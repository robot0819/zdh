#!/bin/bash

###############################################################################
# Filebrowser 自动化部署脚本
# 使用方法: bash filebrowser-deploy.sh
###############################################################################

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

filebrowser config init

# 配置变量（可根据需要修改）
FB_PORT=${FB_PORT:-8080}
FB_ROOT=${FB_ROOT:-/home/screenshot}
FB_USER=${FB_USER:-yuyehd}
FB_PASS=${FB_PASS:-yuyehdyuyehd}
FB_ADDRESS=${FB_ADDRESS:-0.0.0.0}

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Filebrowser 自动化部署脚本${NC}"
echo -e "${GREEN}======================================${NC}"

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户或 sudo 运行此脚本${NC}"
    exit 1
fi

# 1. 停止旧的filebrowser服务
echo -e "${YELLOW}[1/7] 停止旧的filebrowser服务...${NC}"
if systemctl is-active --quiet filebrowser 2>/dev/null; then
    systemctl stop filebrowser
    echo "已停止 systemd 服务"
fi
if pgrep -x "filebrowser" > /dev/null; then
    pkill -9 filebrowser
    echo "已杀死进程"
fi

# 2. 移除旧的安装文件
echo -e "${YELLOW}[2/7] 清理旧的安装文件...${NC}"
rm -f /usr/local/bin/filebrowser
rm -f /etc/systemd/system/filebrowser.service
echo "清理完成"

# 3. 下载并安装最新版本
echo -e "${YELLOW}[3/7] 下载并安装 Filebrowser...${NC}"
curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
echo -e "${GREEN}安装完成${NC}"

# 4. 初始化配置
echo -e "${YELLOW}[4/7] 初始化配置...${NC}"
rm -f ${FB_ROOT}/filebrowser.db  # 删除旧数据库
filebrowser config init \
    --address ${FB_ADDRESS} \
    --port ${FB_PORT} \
    --root ${FB_ROOT} \
    --database ${FB_ROOT}/filebrowser.db
echo "配置初始化完成"

# 5. 创建管理员用户
echo -e "${YELLOW}[5/7] 创建管理员用户...${NC}"
filebrowser users add ${FB_USER} ${FB_PASS} --perm.admin
filebrowser users update ${FB_USER} --perm.admin=true
echo -e "${GREEN}用户创建完成 - 用户名: ${FB_USER}, 密码: ${FB_PASS}${NC}"

# 6. 创建 systemd 服务
echo -e "${YELLOW}[6/7] 创建 systemd 服务...${NC}"
cat > /etc/systemd/system/filebrowser.service <<EOF
[Unit]
Description=File Browser
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${FB_ROOT}
ExecStart=/usr/local/bin/filebrowser -d ${FB_ROOT}/filebrowser.db
Restart=on-failure
RestartSec=5s
StandardOutput=append:/var/log/filebrowser.log
StandardError=append:/var/log/filebrowser.log

[Install]
WantedBy=multi-user.target
EOF

# 7. 启动服务
echo -e "${YELLOW}[7/7] 启动服务...${NC}"
systemctl daemon-reload
systemctl enable filebrowser
systemctl start filebrowser

# 等待服务启动
sleep 2

# 检查服务状态
if systemctl is-active --quiet filebrowser; then
    echo -e "${GREEN}======================================${NC}"
    echo -e "${GREEN}部署成功！${NC}"
    echo -e "${GREEN}======================================${NC}"
    echo -e "访问地址: ${GREEN}http://$(hostname -I | awk '{print $1}'):${FB_PORT}${NC}"
    echo -e "用户名: ${GREEN}${FB_USER}${NC}"
    echo -e "密码: ${GREEN}${FB_PASS}${NC}"
    echo -e "根目录: ${GREEN}${FB_ROOT}${NC}"
    echo -e "数据库: ${GREEN}${FB_ROOT}/filebrowser.db${NC}"
    echo -e "日志文件: ${GREEN}/var/log/filebrowser.log${NC}"
    echo ""
    echo -e "服务管理命令:"
    echo -e "  启动: ${YELLOW}systemctl start filebrowser${NC}"
    echo -e "  停止: ${YELLOW}systemctl stop filebrowser${NC}"
    echo -e "  重启: ${YELLOW}systemctl restart filebrowser${NC}"
    echo -e "  状态: ${YELLOW}systemctl status filebrowser${NC}"
    echo -e "  查看日志: ${YELLOW}tail -f /var/log/filebrowser.log${NC}"
    echo -e "${GREEN}======================================${NC}"
else
    echo -e "${RED}部署失败，请检查日志: tail -f /var/log/filebrowser.log${NC}"
    exit 1
fi
