#!/bin/bash
# Does a Sonnet inference call expose a Sonnet-specific weekly window in the
# rate-limit headers? Pings twice (Haiku, then Sonnet; 1 token each) and dumps
# ALL anthropic-ratelimit-* headers for comparison. Token read from stdin,
# never printed.
set -euo pipefail
UA="claude-cli/2.1.173 (external, cli)"

printf "Paste setup-token, then Enter: "
read -r TOKEN
[ -z "$TOKEN" ] && { echo "no token"; exit 1; }

for model in "claude-haiku-4-5-20251001" "claude-sonnet-4-6"; do
  body='{"model":"'"$model"'","max_tokens":1,"system":"You are Claude Code, Anthropic'"'"'s official CLI for Claude.","messages":[{"role":"user","content":"ping"}]}'
  status=$(curl -sS -D /tmp/cp_hdrs -o /dev/null -w '%{http_code}' --max-time 25 \
    -X POST "https://api.anthropic.com/v1/messages" \
    -H "Authorization: Bearer $TOKEN" \
    -H "anthropic-version: 2023-06-01" \
    -H "anthropic-beta: oauth-2025-04-20,claude-code-20250219" \
    -H "x-app: cli" \
    -H "content-type: application/json" \
    -A "$UA" \
    --data "$body" || echo ERR)
  echo "=== $model -> HTTP $status ==="
  grep -i "anthropic-ratelimit" /tmp/cp_hdrs | sort || echo "(no rate-limit headers)"
  echo
done
rm -f /tmp/cp_hdrs