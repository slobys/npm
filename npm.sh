#!/usr/bin/env bash
set -euo pipefail

echo "🚀 检查 Docker 是否安装..."
if ! command -v docker &>/dev/null; then
  echo "🔹 未检测到 Docker，开始安装(修正 APT 源代号)..."

  # 识别发行版代号（修复 get.docker.com 写错代号的问题）
  source /etc/os-release || { echo "无法读取 /etc/os-release"; exit 1; }
  ID=${ID:-ubuntu}
  VERSION_CODENAME=${VERSION_CODENAME:-}
  VERSION_ID=${VERSION_ID:-}

  if [ "$ID" != "ubuntu" ]; then
    echo "仅适配 Ubuntu，当前检测到：$ID" >&2
    exit 1
  fi

  # 代号兜底映射
  if [ -z "${VERSION_CODENAME}" ] || [[ "$VERSION_CODENAME" =~ ^(n/a|unknown|questing)$ ]]; then
    case "$VERSION_ID" in
      24.04*) VERSION_CODENAME=noble ;;
      22.04*) VERSION_CODENAME=jammy ;;
      20.04*) VERSION_CODENAME=focal ;;
      18.04*) VERSION_CODENAME=bionic ;;
      *) VERSION_CODENAME="$(lsb_release -cs 2>/dev/null || true)";;
    esac
  fi
  [ -n "$VERSION_CODENAME" ] || { echo "无法确定 Ubuntu 代号"; exit 1; }
  echo "👉 使用 Ubuntu 代号：$VERSION_CODENAME"

  # 准备依赖 & Docker 源
  apt-get -qq update
  apt-get install -y -qq ca-certificates curl gnupg lsb-release >/dev/null
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  cat >/etc/apt/sources.list.d/docker.list <<EOF
deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable
EOF

  apt-get update
  # 官方包：docker-ce + compose 插件
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
fi

echo "🚀 检查 Docker Compose 是否安装..."
if ! command -v docker-compose &>/dev/null; then
  if docker compose version &>/dev/null; then
    echo "🔹 未发现 docker-compose 二进制，但已安装 compose 插件 —— 创建兼容 wrapper..."
    cat >/usr/local/bin/docker-compose <<'EOF'
#!/usr/bin/env bash
exec docker compose "$@"
EOF
    chmod +x /usr/local/bin/docker-compose
  else
    echo "❌ 未检测到 Compose，请检查 Docker 安装。" >&2
    exit 1
  fi
fi

# ====== 交互端口（保持你原脚本的语义）======
read -rp "请输入 HTTP 端口 [默认 80]: " PORT_HTTP;   PORT_HTTP=${PORT_HTTP:-80}
read -rp "请输入 HTTPS 端口 [默认 443]: " PORT_HTTPS; PORT_HTTPS=${PORT_HTTPS:-443}
read -rp "请输入 管理面端口 [默认 81]: " PORT_PANEL;  PORT_PANEL=${PORT_PANEL:-81}

mkdir -p nginx-proxy-manager
cd nginx-proxy-manager

cat >docker-compose.yml <<EOF
version: "3.8"
services:
  app:
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
docker-compose up -d

echo "✅ 安装完成！"
IPV4=$(hostname -I | awk '{print $1}')
echo "🔹 访问管理面板： http://${IPV4}:${PORT_PANEL}"
echo "🔹 默认账号： admin@example.com / changeme"
