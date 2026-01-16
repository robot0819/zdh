# Filebrowser 完整部署指南

## 📚 目录

1. [快速开始](#快速开始)
2. [部署场景](#部署场景)
3. [独立组件部署](#独立组件部署)
4. [配置说明](#配置说明)
5. [常见问题](#常见问题)
6. [安全建议](#安全建议)

---

## 🚀 快速开始

### 准备工作

确保以下脚本已上传到服务器的 `/root` 目录：

```bash
filebrowser-deploy.sh       # Filebrowser 部署脚本
nginx-setup.sh              # Nginx 配置脚本
frps-setup.sh               # FRP 服务端脚本
frpc-setup.sh               # FRP 客户端脚本
filebrowser-all-in-one.sh   # 一键部署脚本
deploy-config.env           # 配置文件模板（可选）
```

### 一键部署

```bash
chmod +x /root/*.sh
bash /root/filebrowser-all-in-one.sh
```

脚本会引导你完成配置。

---

## 📋 部署场景

### 场景1: 公网服务器 - 完整部署（推荐）

**适用于：** 有公网IP的服务器，想通过域名+SSL访问

**部署内容：** Filebrowser + Nginx 反向代理

```bash
bash filebrowser-all-in-one.sh
# 选择: 1) 公网服务器 - 完整部署
```

**访问方式：** `https://files.yourdomain.com`

---

### 场景2: 公网服务器 - 简单部署

**适用于：** 有公网IP，不需要域名，直接端口访问

**部署内容：** 仅 Filebrowser

```bash
bash filebrowser-all-in-one.sh
# 选择: 2) 公网服务器 - 仅Filebrowser
```

**访问方式：** `http://服务器IP:8080`

---

### 场景3: 内网服务器 - FRP穿透

**适用于：** 内网服务器，通过公网FRP服务器暴露服务

**前提条件：** 已在公网服务器部署 FRP 服务端（场景4）

**部署步骤：**

1. **在公网VPS上部署 FRP 服务端：**
```bash
bash frps-setup.sh
# 记录 Token 和服务器信息
```

2. **在内网服务器上部署：**
```bash
bash filebrowser-all-in-one.sh
# 选择: 3) 内网服务器 - FRP穿透
# 输入公网服务器的地址和 Token
```

**访问方式：**
- HTTP模式：`http://files.yourdomain.com`
- TCP模式：`http://公网IP:映射端口`

---

### 场景4: 仅搭建 FRP 服务端

**适用于：** 在公网服务器搭建 FRP 转发服务器

**部署内容：** 仅 FRP 服务端

```bash
bash frps-setup.sh
```

配置信息会保存到 `/root/frps-info.txt`

---

## 🔧 独立组件部署

### 1. 单独部署 Filebrowser

```bash
# 使用默认配置
bash filebrowser-deploy.sh

# 或使用自定义配置
export FB_PORT=8888
export FB_ROOT=/data
export FB_USER=myadmin
export FB_PASS=mypassword123456
bash filebrowser-deploy.sh
```

### 2. 单独配置 Nginx

```bash
# 交互式配置
bash nginx-setup.sh

# 或使用环境变量
export NGINX_DOMAIN=files.example.com
export FB_PORT=8080
export ENABLE_SSL=true
export SSL_EMAIL=admin@example.com
bash nginx-setup.sh
```

### 3. 单独部署 FRP 服务端

```bash
bash frps-setup.sh
```

### 4. 单独部署 FRP 客户端

```bash
# 交互式配置
bash frpc-setup.sh

# 或使用环境变量
export FRPS_SERVER_ADDR=your-server.com
export FRPS_SERVER_PORT=7000
export FRPS_TOKEN=your-token
export FRPC_LOCAL_PORT=8080
export FRPC_PROXY_TYPE=http
export FRPC_CUSTOM_DOMAIN=files.example.com
bash frpc-setup.sh
```

---

## ⚙️ 配置说明

### 使用配置文件

1. 复制配置模板：
```bash
cp deploy-config.env my-config.env
```

2. 编辑配置文件：
```bash
nano my-config.env
```

3. 加载配置并部署：
```bash
source my-config.env && bash filebrowser-deploy.sh
```

### 配置参数说明

#### Filebrowser 配置
- `FB_PORT`: 监听端口（默认：8080）
- `FB_ROOT`: 文件根目录（默认：/root）
- `FB_USER`: 管理员用户名（默认：admin）
- `FB_PASS`: 管理员密码（至少12位）

#### Nginx 配置
- `NGINX_DOMAIN`: 域名或IP
- `NGINX_PORT`: Nginx监听端口（默认：80）
- `ENABLE_SSL`: 启用SSL（true/false）
- `SSL_EMAIL`: Let's Encrypt 邮箱

#### FRP 服务端配置
- `FRPS_BIND_PORT`: 客户端连接端口（默认：7000）
- `FRPS_VHOST_HTTP_PORT`: HTTP代理端口（默认：8080）
- `FRPS_DASHBOARD_PORT`: 管理面板端口（默认：7500）
- `FRPS_TOKEN`: 认证Token（留空自动生成）

#### FRP 客户端配置
- `FRPS_SERVER_ADDR`: 服务端地址
- `FRPS_TOKEN`: 服务端Token
- `FRPC_PROXY_TYPE`: 代理类型（http/tcp）
- `FRPC_CUSTOM_DOMAIN`: 自定义域名（HTTP模式）
- `FRPC_REMOTE_PORT`: 远程端口（TCP模式）

---

## 🛠️ 服务管理

### Filebrowser
```bash
systemctl start filebrowser     # 启动
systemctl stop filebrowser      # 停止
systemctl restart filebrowser   # 重启
systemctl status filebrowser    # 状态
tail -f /var/log/filebrowser.log  # 日志
```

### Nginx
```bash
systemctl restart nginx         # 重启
nginx -t                        # 测试配置
tail -f /var/log/nginx/filebrowser_access.log  # 访问日志
tail -f /var/log/nginx/filebrowser_error.log   # 错误日志
```

### FRP 服务端
```bash
systemctl start frps           # 启动
systemctl status frps          # 状态
tail -f /var/log/frps.log      # 日志
```

### FRP 客户端
```bash
systemctl start frpc           # 启动
systemctl status frpc          # 状态
tail -f /var/log/frpc.log      # 日志
```

---

## ❓ 常见问题

### 1. 端口被占用
**问题：** 提示端口已被占用

**解决：**
```bash
# 查看端口占用
netstat -tlnp | grep 8080

# 修改配置文件中的端口
export FB_PORT=8888
```

### 2. 无法访问服务
**检查清单：**
- [ ] 服务是否正常运行：`systemctl status filebrowser`
- [ ] 防火墙是否开放端口：`ufw allow 8080` 或 `firewall-cmd --add-port=8080/tcp`
- [ ] 云服务器安全组是否放行
- [ ] Nginx配置是否正确：`nginx -t`

### 3. FRP 连接失败
**排查步骤：**
```bash
# 客户端检查连接
tail -f /var/log/frpc.log

# 服务端检查
tail -f /var/log/frps.log

# 确认Token是否一致
grep token /etc/frp/frps.toml
grep token /etc/frp/frpc.toml
```

### 4. SSL证书获取失败
**可能原因：**
- 域名未解析到服务器
- 80端口被占用
- 域名不正确

**解决：**
```bash
# 确认域名解析
dig yourdomain.com

# 手动获取证书
certbot --nginx -d yourdomain.com
```

### 5. 上传文件失败
**检查：**
```bash
# Nginx 上传大小限制
grep client_max_body_size /etc/nginx/sites-available/filebrowser

# 修改为更大的值（如10G）
client_max_body_size 10G;
systemctl reload nginx
```

---

## 🔒 安全建议

### 1. 修改默认密码
首次部署后立即修改密码：
```bash
filebrowser users update admin --password new-strong-password
systemctl restart filebrowser
```

### 2. 使用强密码
- 至少12位
- 包含大小写字母、数字、特殊字符

### 3. 启用 HTTPS
```bash
export ENABLE_SSL=true
export SSL_EMAIL=your-email@example.com
bash nginx-setup.sh
```

### 4. 限制访问IP（可选）
编辑 Nginx 配置：
```nginx
location / {
    allow 1.2.3.4;      # 允许的IP
    deny all;           # 拒绝其他
    proxy_pass http://filebrowser_backend;
    ...
}
```

### 5. 定期备份
```bash
# 备份数据库
cp /root/filebrowser.db /backup/filebrowser-$(date +%Y%m%d).db

# 设置定时备份
crontab -e
# 添加: 0 2 * * * cp /root/filebrowser.db /backup/filebrowser-$(date +\%Y\%m\%d).db
```

### 6. FRP Token 安全
- 使用强随机Token
- 不要在公开场合泄露
- 定期更换

---

## 📦 完整部署示例

### 示例1: 带域名和SSL的完整部署

```bash
# 1. 部署 Filebrowser
export FB_PORT=8080
export FB_USER=admin
export FB_PASS=MySecurePass123
bash filebrowser-deploy.sh

# 2. 配置 Nginx + SSL
export NGINX_DOMAIN=files.example.com
export ENABLE_SSL=true
export SSL_EMAIL=admin@example.com
bash nginx-setup.sh

# 访问: https://files.example.com
```

### 示例2: 内网穿透完整流程

**公网服务器（1.2.3.4）：**
```bash
# 部署 FRP 服务端
bash frps-setup.sh
# 记录生成的 Token: abc123def456
```

**内网服务器：**
```bash
# 1. 部署 Filebrowser
bash filebrowser-deploy.sh

# 2. 配置 FRP 客户端
export FRPS_SERVER_ADDR=1.2.3.4
export FRPS_TOKEN=abc123def456
export FRPC_PROXY_TYPE=http
export FRPC_CUSTOM_DOMAIN=files.example.com
bash frpc-setup.sh

# 访问: http://files.example.com（需要域名解析到1.2.3.4）
```

---

## 📞 技术支持

- Filebrowser: https://filebrowser.org/
- FRP: https://github.com/fatedier/frp
- Nginx: https://nginx.org/

## 📄 许可证

本部署脚本采用 MIT 许可证。
