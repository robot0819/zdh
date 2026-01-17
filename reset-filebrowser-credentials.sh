#!/bin/bash
#
# FileBrowser 用户名密码随机重置脚本
# 自动生成随机用户名和密码并更新FileBrowser
#

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "========================================"
echo "FileBrowser 凭据随机重置脚本"
echo "========================================"
echo ""

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ 请使用root权限运行此脚本${NC}"
    echo "   使用: sudo bash $0"
    exit 1
fi

# 配置参数
FILEBROWSER_BIN="/usr/local/bin/filebrowser"
FILEBROWSER_DB="/opt/filebrowser/filebrowser.db"
CREDENTIALS_FILE="/root/filebrowser-credentials.txt"

# 检查filebrowser是否存在
if [ ! -f "$FILEBROWSER_BIN" ]; then
    echo -e "${RED}❌ FileBrowser程序未找到: $FILEBROWSER_BIN${NC}"
    exit 1
fi

# 检查数据库是否存在
if [ ! -f "$FILEBROWSER_DB" ]; then
    echo -e "${RED}❌ FileBrowser数据库未找到: $FILEBROWSER_DB${NC}"
    exit 1
fi

# 1. 停止FileBrowser服务（避免数据库锁定）
echo -e "${BLUE}[1/6] 停止FileBrowser服务...${NC}"

NEED_RESTART=false

# 检查是否有systemd服务
if systemctl list-units --full -all | grep -q "filebrowser.service"; then
    if systemctl is-active --quiet filebrowser.service; then
        systemctl stop filebrowser.service
        NEED_RESTART=true
        echo -e "${GREEN}✅ FileBrowser服务已停止${NC}"
    fi
else
    # 查找并停止进程
    FB_PID=$(pgrep -f "filebrowser.*filebrowser.json" | head -1)
    if [ -n "$FB_PID" ]; then
        echo -e "${YELLOW}   停止FileBrowser进程 (PID: $FB_PID)${NC}"
        kill "$FB_PID"
        sleep 2
        NEED_RESTART=true
        echo -e "${GREEN}✅ FileBrowser进程已停止${NC}"
    else
        echo -e "${YELLOW}⚠️  未检测到运行中的FileBrowser${NC}"
    fi
fi

# 2. 获取当前用户列表
echo ""
echo -e "${BLUE}[2/6] 获取当前用户列表...${NC}"
CURRENT_USER=$($FILEBROWSER_BIN users ls -d "$FILEBROWSER_DB" 2>&1 | grep -v "^ID\|^2026\|^Error" | awk 'NF>0 {print $2}' | head -1)

if [ -z "$CURRENT_USER" ]; then
    echo -e "${RED}❌ 未找到现有用户${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 当前用户: $CURRENT_USER${NC}"

# 3. 生成随机用户名（8位字母数字）
echo ""
echo -e "${BLUE}[3/6] 生成随机凭据...${NC}"

# 生成随机用户名：字母开头 + 7位字母数字
NEW_USERNAME=$(cat /dev/urandom | tr -dc 'a-z' | fold -w 1 | head -n 1)$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 7 | head -n 1)

# 生成随机密码：16位包含大小写字母、数字和特殊字符
NEW_PASSWORD=$(cat /dev/urandom | tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' | fold -w 16 | head -n 1)

echo -e "${GREEN}✅ 新用户名: ${YELLOW}$NEW_USERNAME${NC}"
echo -e "${GREEN}✅ 新密码: ${YELLOW}$NEW_PASSWORD${NC}"

# 4. 更新用户名和密码
echo ""
echo -e "${BLUE}[4/6] 更新FileBrowser凭据...${NC}"

# 更新用户名
$FILEBROWSER_BIN users update "$CURRENT_USER" \
    --username "$NEW_USERNAME" \
    -d "$FILEBROWSER_DB" 2>&1 > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ 用户名已更新${NC}"
else
    echo -e "${RED}❌ 用户名更新失败${NC}"
    exit 1
fi

# 更新密码
$FILEBROWSER_BIN users update "$NEW_USERNAME" \
    --password "$NEW_PASSWORD" \
    -d "$FILEBROWSER_DB" 2>&1 > /dev/null

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ 密码已更新${NC}"
else
    echo -e "${RED}❌ 密码更新失败${NC}"
    exit 1
fi

# 5. 保存凭据到文件
echo ""
echo -e "${BLUE}[5/6] 保存凭据到文件...${NC}"

cat > "$CREDENTIALS_FILE" << EOF
========================================
FileBrowser 登录凭据
========================================
生成时间: $(date '+%Y-%m-%d %H:%M:%S')
数据库: $FILEBROWSER_DB

用户名: $NEW_USERNAME
密码: $NEW_PASSWORD

原用户名: $CURRENT_USER
========================================

请妥善保管此文件！
建议立即将凭据保存到密码管理器中。

EOF

chmod 600 "$CREDENTIALS_FILE"
echo -e "${GREEN}✅ 凭据已保存到: ${YELLOW}$CREDENTIALS_FILE${NC}"

# 6. 重启FileBrowser服务
echo ""
echo -e "${BLUE}[6/6] 重启FileBrowser服务...${NC}"

if [ "$NEED_RESTART" = true ]; then
    # 检查是否有systemd服务
    if systemctl list-units --full -all | grep -q "filebrowser.service"; then
        systemctl start filebrowser.service
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}✅ FileBrowser服务已重启${NC}"
        else
            echo -e "${YELLOW}⚠️  服务启动失败，请手动启动${NC}"
        fi
    else
        # 重新启动进程（根据原来的命令）
        nohup /opt/filebrowser/filebrowser -c /opt/filebrowser/filebrowser.json > /dev/null 2>&1 &
        sleep 1
        NEW_PID=$(pgrep -f "filebrowser.*filebrowser.json" | head -1)
        if [ -n "$NEW_PID" ]; then
            echo -e "${GREEN}✅ FileBrowser进程已重启 (PID: $NEW_PID)${NC}"
        else
            echo -e "${YELLOW}⚠️  进程启动失败，请手动启动${NC}"
        fi
    fi
else
    echo -e "${YELLOW}⚠️  FileBrowser未在运行，跳过重启${NC}"
fi

# 完成
echo ""
echo "========================================"
echo -e "${GREEN}✅ 凭据重置完成！${NC}"
echo "========================================"
echo ""
echo -e "${YELLOW}重要信息：${NC}"
echo -e "  新用户名: ${GREEN}$NEW_USERNAME${NC}"
echo -e "  新密码:   ${GREEN}$NEW_PASSWORD${NC}"
echo ""
echo -e "  凭据文件: ${BLUE}$CREDENTIALS_FILE${NC}"
echo ""
echo -e "${RED}⚠️  请立即保存凭据到安全位置！${NC}"
echo ""
echo "查看完整信息："
echo "  cat $CREDENTIALS_FILE"
echo ""
