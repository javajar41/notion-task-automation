#!/bin/bash
# Notion Task Automation - 报告生成器 (P2-3)
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
REPORTS_DIR="$SKILL_DIR/reports"

# 确保报告目录存在
mkdir -p "$REPORTS_DIR"

# 生成每日报告
generate_daily_report() {
    local date_str=$(date '+%Y-%m-%d')
    local report_file="$REPORTS_DIR/daily-${date_str}.md"
    
    cat > "$report_file" << EOF
# Notion 任务日报 - ${date_str}

生成时间: $(date '+%Y-%m-%d %H:%M:%S')

## 统计概览

$(generate_stats)

## 详细任务

$(generate_task_list)

---
*自动生成 by Notion Task Automation*
EOF

    echo "$report_file"
}

# 生成统计信息
generate_stats() {
    # 从 state.json 读取统计数据
    if [ -f "$SKILL_DIR/state.json" ]; then
        local last_check=$(jq -r '.last_check_time // "未知"' "$SKILL_DIR/state.json")
        local last_total=$(jq -r '.last_total // "0"' "$SKILL_DIR/state.json")
        
        echo "- 最后检查: $last_check"
        echo "- 任务总数: $last_total"
    else
        echo "暂无统计数据"
    fi
}

# 生成任务列表
generate_task_list() {
    # 这里可以调用 Notion API 获取任务列表
    echo "任务列表功能待实现"
}

# 如果直接运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    report_file=$(generate_daily_report)
    echo "报告已生成: $report_file"
fi
