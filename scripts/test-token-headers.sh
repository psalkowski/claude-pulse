#!/bin/bash
# Definitive test: does a 1-token /v1/messages call with a `claude setup-token`
# return the subscription usage windows as response headers? Token is read from
# stdin (never argv/history) and never printed. The rate-limit headers shown are
# NOT secret. This call costs ~1 token and starts/refreshes the 5h window.
#
#   claude setup-token        # copy the printed token
#   bash scripts/test-token-headers.sh   # paste when prompted
#
set -euo pipefail
UA="claude-cli/2.1.173 (external, cli)"

printf "Paste setup-token, then Enter: "
read -r TOKEN
[ -z "$TOKEN" ] && { echo "no token"; exit 1; }

body='{"model":"claude-haiku-4-5-20251001","max_tokens":1,"system":"You are Claude Code, Anthropic'"'"'s official CLI for Claude.","messages":[{"role":"user","content":"ping"}]}'

echo "--- request ---"
status=$(curl -sS -D /tmp/cp_hdrs -o /tmp/cp_body -w '%{http_code}' --max-time 25 \
  -X POST "https://api.anthropic.com/v1/messages" \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: oauth-2025-04-20,claude-code-20250219" \
  -H "x-app: cli" \
  -H "content-type: application/json" \
  -A "$UA" \
  --data "$body" || echo ERR)

echo "HTTP $status"
echo "--- unified rate-limit headers ---"
grep -i "anthropic-ratelimit-unified" /tmp/cp_hdrs || echo "(none found)"
echo "--- body (first 200 chars, in case of error) ---"
head -c 200 /tmp/cp_body; echo
rm -f /tmp/cp_hdrs /tmp/cp_body
echo
echo "If you see 5h-utilization + 7d-utilization above, the keychain-free design works."
