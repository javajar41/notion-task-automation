#!/bin/bash
# Notion Task Automation - Notion 变更检测器 (P2-3)
# 修复版本：支持跨平台路径检测

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 动态检测 WORKSPACE
if [ -n "$OPENCLAW_WORKSPACE" ]; then
    WORKSPACE="$OPENCLAW_WORKSPACE"
elif [ -n "$HOME" ] && [ -d "$HOME/.openclaw/workspace" ]; then
    WORKSPACE="$HOME/.openclaw/workspace"
else
    WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

SKILL_DIR="$SCRIPT_DIR/.."
STATE_FILE="$SKILL_DIR/state.json"
LAST_CHECK_FILE="$SKILL_DIR/.last_change_check"

# 检查任务变化
check_task_changes() {
    local current_time=$(date +%s)
    local last_check=0
    
    if [ -f "$LAST_CHECK_FILE" ]; then
        last_check=$(cat "$LAST_CHECK_FILE")
    fi
    
    # 最小检查间隔（默认5分钟）
    local min_interval="${CHECK_INTERVAL:-300}"
    local time_diff=$((current_time - last_check))
    
    if [ $time_diff -lt $min_interval ]; then
        return 0  # 间隔太短，跳过
    fi
    
    # 保存本次检查时间
    echo "$current_time" > "$LAST_CHECK_FILE"
    
    # 调用 API 获取当前任务状态
    local current_data=$(curl -s -X POST \
        "https://api.notion.com/v1/databases/${NOTION_DATABASE_ID}/query" \
        -H "Authorization: Bearer ${NOTION_TOKEN}" \
        -H "Notion-Version: 2022-06-28" \
        -H "Content-Type: application/json" \
        -d '{}')
    
    # 保存当前状态供下次比较
    echo "$current_data" > "$SKILL_DIR/.last_tasks_state.json"
    
    # 对比上次状态（如果有）
    if [ -f "$SKILL_DIR/.last_tasks_state.json.prev" ]; then
        local changes=$(diff <(echo "$current_data" | jq -S '.results[].id') \
                            <(cat "$SKILL_DIR/.last_tasks_state.json.prev" | jq -S '.results[].id') 2>/dev/null)
        if [ -n "$changes" ]; then
            echo "检测到任务变化"
            return 1  # 有变化
        fi
    fi
    
    # 保存备份供下次比较
    cp "$SKILL_DIR/.last_tasks_state.json" "$SKILL_DIR/.last_tasks_state.json.prev"
    
    return 0  # 无变化
}

# 如果直接运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_task_changes
fi
