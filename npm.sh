#!/bin/bash
set -e

echo "🚀 检查 Docker 是否安装..."
if ! command -v docker &>/dev/null; then
  echo "🔹 未检测到 Docker，开始安装..."
  # 按你要求：使用官方一键脚本
  curl -fsSL https://get.docker.com -o get-docker.sh
  sh get-docker.sh || true

  # 如果官方脚本把源写成了无效的 questing，修正为 jammy 后补装一次
  if [ -f /etc/apt/sources.list.d/docker.list ] && grep -q "ubuntu questing" /etc/apt/sources.list.d/docker.list; then
    echo "⚙️ 修正 docker 源代号：questing → jammy"
    sudo sed -i 's/ubuntu questing/ubuntu jammy/' /etc/apt/sources.list.d/docker.list
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  sudo systemctl enable --now docker
fi

echo "🚀 检查 Docker Compose 是否可用..."
if ! command -v docker-compose &>/dev/null; then
  if docker compose version &>/dev/null; then
    echo "🔧 未找到 docker-compose 二进制，创建兼容 wrapper..."
    sudo tee /usr/local/bin/docker-compose >/dev/null <<'EOF'
#!/usr/bin/env bash
exec docker compose "$@"
EOF
    sudo chmod +x /usr/local/bin/docker-compose
  else
    echo "🔸 尝试安装 docker-compose-plugin ..."
    sudo apt-get update
    sudo apt-get install -y docker-compose-plugin || true
  fi
fi

echo "🚀 创建 Nginx Proxy Manager 目录..."
sudo mkdir -p /etc/docker/npm
cd /etc/docker/npm

# 交互端口（默认 80 / 81 / 443）
read -rp "请输入 HTTP 端口（默认80）: " PORT_HTTP
PORT_HTTP=${PORT_HTTP:-80}
read -rp "请输入 管理面板端口（默认81）: " PORT_PANEL
PORT_PANEL=${PORT_PANEL:-81}
read -rp "请输入 HTTPS 端口（默认443）: " PORT_HTTPS
PORT_HTTPS=${PORT_HTTPS:-443}

echo "🔹 端口映射：HTTP=$PORT_HTTP  面板=$PORT_PANEL  HTTPS=$PORT_HTTPS"

echo "🚀 生成 docker-compose.yml..."
cat > docker-compose.yml <<EOF
services:
  npm:
    image: jc21/nginx-proxy-manager:latest
    restart: unless-stopped
    ports:
      - '${PORT_HTTP}:80'
      - '${PORT_PANEL}:81'
      - '${PORT_HTTPS}:443'
    volumes:
      - ./data:/data
      - ./letsencrypt:/etc/letsencrypt
EOF

echo "🚀 启动 Nginx Proxy Manager..."
# 使用 docker compose（若安装了 wrapper，docker-compose 也可）
docker compose up -d 2>/dev/null || docker-compose up -d

echo "✅ 安装完成！"
IPV4=$(hostname -I | awk '{print $1}')
echo "🔹 访问面板： http://${IPV4}:${PORT_PANEL}"
echo "🔹 默认账号： admin@example.com / changeme"
