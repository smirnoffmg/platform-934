#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_FILE="$SCRIPT_DIR/vpn-test.log"
CONFIG="$SCRIPT_DIR/client-config.json"
SOCKS_PORT=1080
SERVER_IP=$(jq -r '.outbounds[0].settings.vnext[0].address' "$CONFIG")
SERVER_PORT=$(jq -r '.outbounds[0].settings.vnext[0].port' "$CONFIG")
FINGERPRINT=$(jq -r '.outbounds[0].streamSettings.realitySettings.fingerprint' "$CONFIG")

exec > >(tee "$LOG_FILE") 2>&1

echo "=== VPN test $(date) ==="
echo "fingerprint: $FINGERPRINT  server: $SERVER_IP:$SERVER_PORT"
echo ""

# 1. TCP probe (raw, no REALITY) — distinguishes IP-block from protocol-block
echo "--- TCP probe ---"
CURL_CODE=0
curl -sv --connect-timeout 5 --max-time 5 \
  "https://$SERVER_IP:$SERVER_PORT" -o /dev/null 2>&1 || CURL_CODE=$?
if   [[ $CURL_CODE -eq 35 || $CURL_CODE -eq 60 ]]; then
  echo "TCP: OPEN (TLS error — port reachable, server responded)"
elif [[ $CURL_CODE -eq 28 ]]; then
  echo "TCP: TIMEOUT (no response — likely blocked)"
elif [[ $CURL_CODE -eq  7 ]]; then
  echo "TCP: REFUSED"
else
  echo "TCP: curl exit=$CURL_CODE"
fi
echo ""

# 2. REALITY tunnel test
echo "--- REALITY tunnel (fingerprint=$FINGERPRINT) ---"

XRAY_LOG="/tmp/xray-test-$$.log"

cat > /tmp/xray-test-client.json <<EOF
{
  "log": { "loglevel": "debug", "access": "$XRAY_LOG", "error": "$XRAY_LOG" },
  "inbounds": [{ "port": $SOCKS_PORT, "protocol": "socks",
                  "settings": { "auth": "noauth", "udp": true } }],
  "outbounds": $(jq '.outbounds' "$CONFIG")
}
EOF

xray run -c /tmp/xray-test-client.json &
XPID=$!
trap 'kill $XPID 2>/dev/null; echo ""; echo "--- xray log ---"; cat '"$XRAY_LOG"' 2>/dev/null' EXIT

sleep 2

RESULT="FAILED"
curl -s -x "socks5://127.0.0.1:$SOCKS_PORT" \
  --max-time 10 https://ifconfig.me > /tmp/vpn-exit-ip.txt 2>/dev/null \
  && RESULT=$(cat /tmp/vpn-exit-ip.txt)

echo ""
echo "exit_ip : $RESULT"
echo "expected: $SERVER_IP"
echo ""
if [[ "$RESULT" == "$SERVER_IP" ]]; then
  echo "STATUS: SUCCESS — VPN is working"
else
  echo "STATUS: FAILED"
fi
