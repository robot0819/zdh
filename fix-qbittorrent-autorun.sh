#!/bin/bash
#
# qBittorrent AutoRun 修复脚本
# 修复相对路径导致的外部程序无法执行问题
#

set -e

echo "========================================"
echo "qBittorrent AutoRun 修复脚本"
echo "========================================"
echo ""

# 检查是否以root权限运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 请使用root权限运行此脚本"
    echo "   使用: sudo bash $0"
    exit 1
fi

# 1. 查找qBittorrent配置文件
echo "[1/5] 查找qBittorrent配置文件..."
CONFIG_FILE=""
QB_USER=""

# 查找所有用户的qBittorrent配置
for user_home in /home/*; do
    if [ -d "$user_home" ]; then
        config_path="$user_home/.config/qBittorrent/qBittorrent.conf"
        if [ -f "$config_path" ]; then
            CONFIG_FILE="$config_path"
            QB_USER=$(basename "$user_home")
            echo "✅ 找到配置文件: $CONFIG_FILE"
            echo "   用户: $QB_USER"
            break
        fi
    fi
done

if [ -z "$CONFIG_FILE" ]; then
    echo "❌ 未找到qBittorrent配置文件"
    exit 1
fi

# 2. 备份配置文件
echo ""
echo "[2/5] 备份配置文件..."
BACKUP_FILE="${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo "✅ 备份完成: $BACKUP_FILE"

# 3. 检查并修复AutoRun配置
echo ""
echo "[3/5] 检查AutoRun配置..."
if grep -q "program=\./" "$CONFIG_FILE"; then
    echo "⚠️  发现相对路径配置，正在修复..."

    # 查找screenshot.sh的位置
    SCREENSHOT_PATH=""
    if [ -f "/usr/local/bin/screenshot.sh" ]; then
        SCREENSHOT_PATH="/usr/local/bin/screenshot.sh"
    elif [ -f "/usr/local/bin/screenshot" ]; then
        SCREENSHOT_PATH="/usr/local/bin/screenshot"
    else
        echo "❌ 未找到screenshot.sh，请手动指定路径"
        echo "   当前配置: $(grep 'program=' "$CONFIG_FILE")"
        exit 1
    fi

    echo "   找到程序: $SCREENSHOT_PATH"

    # 修改配置文件
    sed -i "s|program=\./screenshot\.sh|program=$SCREENSHOT_PATH|g" "$CONFIG_FILE"
    sed -i "s|program=\./screenshot|program=$SCREENSHOT_PATH|g" "$CONFIG_FILE"

    echo "✅ 配置已更新为绝对路径"
    grep "program=" "$CONFIG_FILE" | head -3
else
    echo "✅ 配置路径正确，无需修改"
    grep "program=" "$CONFIG_FILE" | head -3
fi

# 4. 创建screenshot输出目录
echo ""
echo "[4/5] 创建screenshot输出目录..."
if [ ! -d "/home/screenshot" ]; then
    mkdir -p /home/screenshot
    chown $QB_USER:$QB_USER /home/screenshot
    echo "✅ 已创建目录: /home/screenshot"
else
    chown $QB_USER:$QB_USER /home/screenshot
    echo "✅ 目录已存在，权限已更新"
fi

# 5. 重启qBittorrent服务
echo ""
echo "[5/5] 重启qBittorrent服务..."

# 检查是否有systemd服务
if systemctl list-units --full -all | grep -q "qbittorrent-nox@$QB_USER.service"; then
    echo "   检测到systemd服务，正在重启..."

    # 先停止旧进程
    OLD_PID=$(pgrep -u $QB_USER qbittorrent-nox || echo "")
    if [ -n "$OLD_PID" ]; then
        echo "   停止旧进程 (PID: $OLD_PID)..."
        kill $OLD_PID
        sleep 2
    fi

    # 重启服务
    systemctl restart qbittorrent-nox@$QB_USER.service
    sleep 3

    # 检查状态
    if systemctl is-active --quiet qbittorrent-nox@$QB_USER.service; then
        NEW_PID=$(pgrep -u $QB_USER qbittorrent-nox)
        echo "✅ 服务已重启 (PID: $NEW_PID)"
    else
        echo "⚠️  服务启动失败，请手动检查"
        systemctl status qbittorrent-nox@$QB_USER.service --no-pager -n 10
    fi
else
    echo "   未检测到systemd服务"
    OLD_PID=$(pgrep -u $QB_USER qbittorrent-nox || echo "")
    if [ -n "$OLD_PID" ]; then
        echo "   停止旧进程 (PID: $OLD_PID)..."
        kill $OLD_PID
        echo "✅ 已停止，请手动重启qBittorrent"
    else
        echo "✅ 无运行中的进程"
    fi
fi

echo ""
echo "========================================"
echo "✅ 修复完成！"
echo "========================================"
echo ""
echo "修改内容："
echo "  - 配置文件: $CONFIG_FILE"
echo "  - 备份文件: $BACKUP_FILE"
echo "  - 输出目录: /home/screenshot (所有者: $QB_USER)"
echo ""
echo "如需恢复，运行："
echo "  cp $BACKUP_FILE $CONFIG_FILE"
echo ""
