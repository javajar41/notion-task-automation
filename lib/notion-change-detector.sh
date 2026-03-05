#!/bin/bash
# notion-change-detector.sh - Notion状态变更监听器
# 检测最近30分钟内有状态变更的任务，立即执行相应操作

WORKSPACE="/home/shiyongwang/.openclaw/workspace"
ENV_FILE="$WORKSPACE/.env"
SKILL_DIR="$WORKSPACE/skills/notion-task-automation"
LOG_FILE="/tmp/notion-change-detector.log"
LAST_CHECK_FILE="$SKILL_DIR/.last_change_check"

# 加载环境变量
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# 获取上次检查时间
get_last_check_time() {
    if [ -f "$LAST_CHECK_FILE" ]; then
        cat "$LAST_CHECK_FILE"
    else
        # 默认30分钟前
        date -d '30 minutes ago' -Iseconds
    fi
}

# 保存本次检查时间
save_check_time() {
    date -Iseconds > "$LAST_CHECK_FILE"
}

# 检查Notion中最近有变更的任务
check_recent_changes() {
    local last_check=$(get_last_check_time)
    log "检查自 $last_check 以来的变更..."
    
    # 查询所有任务
    local all_tasks=$(curl -s -X POST \
      "https://api.notion.com/v1/databases/$NOTION_DATABASE_ID/query" \
      -H "Authorization: Bearer $NOTION_TOKEN" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{
        "sorts": [
          {
            "timestamp": "last_edited_time",
            "direction": "descending"
          }
        ]
      }')
    
    # 检查最近编辑的任务
    local recent_changes=$(echo "$all_tasks" | jq -r --arg last_check "$last_check" '
        [.results[] | select(.last_edited_time > $last_check)]
    ')
    
    local change_count=$(echo "$recent_changes" | jq 'length')
    
    if [ "$change_count" -gt 0 ]; then
        log "发现 $change_count 个任务有变更"
        
        # 检查是否有状态变更的任务
        echo "$recent_changes" | jq -c '.[]' | while read -r task; do
            local task_name=$(echo "$task" | jq -r '.properties."项目名称".title[0].plain_text // "未命名"')
            local status=$(echo "$task" | jq -r '.properties."完成状态".status.name // "未知"')
            local last_edited=$(echo "$task" | jq -r '.last_edited_time')
            
            log "  - $task_name: $status (编辑于 $last_edited)"
        done
        
        # 触发自动化检查
        log "触发自动化检查..."
        "$SKILL_DIR/automation.sh" check > /dev/null 2>&1
        
        return 0
    else
        log "没有发现新变更"
        return 1
    fi
}

# 主逻辑
main() {
    log "=============================================="
    log "🔍 Notion状态变更检测启动"
    log "=============================================="
    
    check_recent_changes
    save_check_time
    
    log "检测完成，下次检测将在30分钟后"
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
