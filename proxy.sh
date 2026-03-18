#!/bin/bash

# 1. 更新系统并安装必要组件
apt update && apt install -y curl wget tar

# 2. 安装 GOST (用于 HTTP 和 SOCKS5)
wget https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz
gunzip gost-linux-amd64-2.11.5.gz
mv gost-linux-amd64-2.11.5 /usr/local/bin/gost
chmod +x /usr/local/bin/gost

# 3. 创建 GOST 服务 (后台运行 HTTP 和 SOCKS5)
cat <<EOF > /etc/systemd/system/gost.service
[Unit]
Description=Gost Proxy
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/gost -L http://jeffry:PK8XY8cA@:8080 -L socks5://jeffry:PK8XY8cA@:1080
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 4. 安装 Shadowsocks-rust
SS_VER="v1.18.4"
wget https://github.com/shadowsocks/shadowsocks-rust/releases/download/${SS_VER}/shadowsocks-${SS_VER}.x86_64-unknown-linux-gnu.tar.xz
tar -xvf shadowsocks-${SS_VER}.x86_64-unknown-linux-gnu.tar.xz
mv ssserver /usr/local/bin/ssserver
chmod +x /usr/local/bin/ssserver

# 5. 创建 Shadowsocks 配置
mkdir -p /etc/shadowsocks-rust
cat <<EOF > /etc/shadowsocks-rust/config.json
{
    "server": "0.0.0.0",
    "server_port": 8388,
    "password": "PK8XY8cA",
    "method": "aes-256-gcm",
    "timeout": 300
}
EOF

# 6. 创建 Shadowsocks 服务
cat <<EOF > /etc/systemd/system/ssserver.service
[Unit]
Description=Shadowsocks-rust Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/ssserver -c /etc/shadowsocks-rust/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# 7. 启动所有服务
systemctl daemon-reload
systemctl enable --now gost
systemctl enable --now ssserver

echo "-------------------------------------------------------"
echo "部署完成！"
echo "HTTP 代理: 8080 (jeffry/PK8XY8cA)"
echo "SOCKS5 代理: 1080 (jeffry/PK8XY8cA)"
echo "Shadowsocks: 8388 (aes-256-gcm/PK8XY8cA)"
echo "-------------------------------------------------------"
