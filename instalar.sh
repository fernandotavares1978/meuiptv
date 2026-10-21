#!/usr/bin/env bash
# Meu IPTV — instalação em servidor Ubuntu/Debian
# Uso: curl -fsSL https://raw.githubusercontent.com/SEU_USUARIO/meuiptv/main/instalar.sh | sudo bash -s SEU_USUARIO/meuiptv
set -e

REPO="${1:-$MEUIPTV_REPO}"
if [ -z "$REPO" ]; then
  echo "Informe o repositório. Exemplo: ... | sudo bash -s fernando/meuiptv"; exit 1
fi
if [ "$(id -u)" != "0" ]; then echo "Rode como administrador (sudo)."; exit 1; fi

DIR=/opt/meuiptv
ZIP_URL="https://raw.githubusercontent.com/$REPO/main/meuiptv-web.zip"

echo "==> Instalando programas necessários"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl unzip ca-certificates >/dev/null
if ! command -v node >/dev/null || [ "$(node -e 'console.log(process.versions.node.split(".")[0])')" -lt 16 ]; then
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash - >/dev/null
  apt-get install -y -qq nodejs >/dev/null
fi

echo "==> Baixando o app"
mkdir -p "$DIR"
echo "$ZIP_URL" > "$DIR/.origem"

cat > /usr/local/bin/meuiptv-atualizar <<'EOF'
#!/usr/bin/env bash
# Baixa a versão mais recente do GitHub e reinicia, só se algo mudou
set -e
DIR=/opt/meuiptv
URL=$(cat "$DIR/.origem")
TMP=$(mktemp -d)
curl -fsSL "$URL" -o "$TMP/app.zip"
NEW=$(sha256sum "$TMP/app.zip" | cut -d' ' -f1)
OLD=$(cat "$DIR/.versao" 2>/dev/null || true)
if [ "$NEW" != "$OLD" ]; then
  unzip -qo "$TMP/app.zip" -d "$TMP/x"
  SRC="$TMP/x"; [ -f "$SRC/server.js" ] || SRC=$(dirname "$(find "$TMP/x" -name server.js | head -1)")
  rm -rf "$DIR/public"
  cp -r "$SRC/public" "$DIR/public"
  cp "$SRC/server.js" "$DIR/server.js"
  echo "$NEW" > "$DIR/.versao"
  systemctl restart meuiptv 2>/dev/null || true
  echo "Meu IPTV atualizado."
else
  echo "Já está na versão mais recente."
fi
rm -rf "$TMP"
EOF
chmod +x /usr/local/bin/meuiptv-atualizar
/usr/local/bin/meuiptv-atualizar

echo "==> Configurando para iniciar sozinho"
cat > /etc/systemd/system/meuiptv.service <<EOF
[Unit]
Description=Meu IPTV
After=network-online.target

[Service]
WorkingDirectory=$DIR
ExecStart=$(command -v node) $DIR/server.js
Environment=PORT=80
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now meuiptv >/dev/null 2>&1
systemctl restart meuiptv

# Verifica atualizações no GitHub a cada 10 minutos
echo "*/10 * * * * root /usr/local/bin/meuiptv-atualizar >/dev/null 2>&1" > /etc/cron.d/meuiptv

if command -v ufw >/dev/null && ufw status | grep -q "Status: active"; then ufw allow 80/tcp >/dev/null; fi

sleep 2
KEY=$(node -e "console.log(require('$DIR/config.json').accessKey)" 2>/dev/null || echo "?")
IP=$(curl -fsS4 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}')
echo ""
echo "=============================================="
echo "  Meu IPTV instalado!"
echo ""
echo "  Abra no Safari do iPhone/iPad:"
echo "  http://$IP/?k=$KEY"
echo ""
echo "  Código de acesso: $KEY"
echo "=============================================="
