#!/bin/bash
# multi-db-wrapper.sh - 多数据库支持包装器
# 修复版本：支持跨平台路径检测

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 动态检测 WORKSPACE
if [ -n "$OPENCLAW_WORKSPACE" ]; then
    WORKSPACE="$OPENCLAW_WORKSPACE"
elif [ -n "$HOME" ] && [ -d "$HOME/.openclaw/workspace" ]; then
    WORKSPACE="$HOME/.openclaw/workspace"
else
    WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

SKILL_DIR="$SCRIPT_DIR"

# 加载主脚本
exec "$SKILL_DIR/automation.sh" "$@"
