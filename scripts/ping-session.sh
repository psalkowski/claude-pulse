#!/bin/bash
# Pings Claude with a 1-token request to start/refresh the 5-hour session window
# for the subscription that the token belongs to. Intended for a cron job.
#
# Get a long-lived (~1 year) token once with:  claude setup-token
# Then provide it via the CLAUDE_TOKEN env var.
#
#   CLAUDE_TOKEN=sk-ant-oat... bash ping-session.sh
#
# Use Haiku (the default) to keep a 5-hour session warm: it returns 200 reliably.
# Sonnet is burst-throttled for these pings and will 429 even with quota left, so
# it is NOT a dependable session-trigger — only override MODEL if you know why.
#
set -euo pipefail
: "${CLAUDE_TOKEN:?set CLAUDE_TOKEN to a 'claude setup-token' value}"
MODEL="${MODEL:-claude-haiku-4-5-20251001}"

curl -sS -X POST https://api.anthropic.com/v1/messages \
  -H "Authorization: Bearer ${CLAUDE_TOKEN}" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: oauth-2025-04-20,claude-code-20250219" \
  -H "x-app: cli" \
  -H "content-type: application/json" \
  -A "claude-cli/2.1.173 (external, cli)" \
  -d "{\"model\":\"${MODEL}\",\"max_tokens\":1,\"system\":\"You are Claude Code, Anthropic's official CLI for Claude.\",\"messages\":[{\"role\":\"user\",\"content\":\"ping\"}]}" \
  -D - -o /dev/null -w '\nHTTP %{http_code}\n' | grep -iE 'HTTP|anthropic-ratelimit-unified-(5h|7d|7d_sonnet)-(utilization|reset)'
