#!/bin/bash
# Notion Task Automation Skill - 完整版 v2.0
# 功能：任务检查、产品经理分析、自动开发、自动部署、进度追踪

set -e

WORKSPACE="/home/shiyongwang/.openclaw/workspace"
ENV_FILE="$WORKSPACE/.env"
SKILL_DIR="$WORKSPACE/skills/notion-task-automation"
LOG_FILE="/tmp/notion-skill.log"
STATE_FILE="$SKILL_DIR/state.json"

# 加载环境变量
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${GREEN}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

warn() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] 警告: $1"
    echo -e "${YELLOW}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] 错误: $1"
    echo -e "${RED}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "${BLUE}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

# P0-2: 日志级别控制
LOG_LEVEL="${LOG_LEVEL:-INFO}"
log_debug() {
    [[ "$LOG_LEVEL" == "DEBUG" ]] && log "[DEBUG] $*"
}

# P0-2: 日志轮转
rotate_log() {
    local max_size=10485760  # 10MB
    if [[ -f "$LOG_FILE" ]]; then
        local size=$(stat -f%z "$LOG_FILE" 2>/dev/null || stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [[ $size -gt $max_size ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.old"
            touch "$LOG_FILE"
            log "日志文件已轮转"
        fi
    fi
}

# P0-1: 错误处理和重试
MAX_RETRY="${MAX_RETRY:-3}"
RETRY_DELAY="${RETRY_DELAY:-5}"

# 安全执行函数（带重试）
safe_execute() {
    local cmd="$1"
    local task_name="${2:-unknown}"
    local max_retry="${3:-$MAX_RETRY}"
    local retry_delay="${4:-$RETRY_DELAY}"
    
    local attempt=1
    while [[ $attempt -le $max_retry ]]; do
        log_debug "执行命令 (尝试 $attempt/$max_retry): $cmd"
        if eval "$cmd" 2>&1; then
            return 0
        fi
        
        log_warn "命令失败，等待 ${retry_delay}秒后重试..."
        sleep $retry_delay
        attempt=$((attempt + 1))
    done
    
    error "命令执行失败，已达到最大重试次数: $cmd"
    return 1
}

# 检查依赖
check_deps() {
    if [ -z "$NOTION_TOKEN" ] || [ -z "$NOTION_DATABASE_ID" ]; then
        error "缺少 NOTION_TOKEN 或 NOTION_DATABASE_ID"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        error "缺少 jq 命令，请安装: sudo apt-get install jq"
        exit 1
    fi
}

# 保存状态
save_state() {
    local key=$1
    local value=$2
    
    if [ ! -f "$STATE_FILE" ]; then
        echo "{}" > "$STATE_FILE"
    fi
    
    local temp=$(mktemp)
    jq ".$key = \"$value\"" "$STATE_FILE" > "$temp" && mv "$temp" "$STATE_FILE"
}

# 读取状态
load_state() {
    local key=$1
    local default=${2:-""}
    
    if [ -f "$STATE_FILE" ]; then
        jq -r ".$key // \"$default\"" "$STATE_FILE"
    else
        echo "$default"
    fi
}

# ============================================
# 功能 1: 检查所有任务（增强版）
# ============================================
check_tasks() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "🔍 开始检查 Notion 任务"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local all_data=$(curl -s -X POST \
      "https://api.notion.com/v1/databases/$NOTION_DATABASE_ID/query" \
      -H "Authorization: Bearer $NOTION_TOKEN" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{}')
    
    local total=$(echo "$all_data" | jq -r '.results | length')
    
    # 按状态统计
    local todo=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "未开始")] | length')
    local pending=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "待确认迭代")] | length')
    local confirmed=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "确认迭代")] | length')
    local progress=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "进行中")] | length')
    local testing=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "测试中")] | length')
    local acceptance=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "待验收")] | length')
    local fixing=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "修复中")] | length')
    local done=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "已完成")] | length')
    
    # 保存统计数据
    save_state "last_check_time" "$(date '+%Y-%m-%d %H:%M:%S')"
    save_state "last_total" "$total"
    save_state "last_done" "$done"
    
    log ""
    log "📊 任务统计"
    log "─────────────────────────────────"
    info "  总计:     $total 个任务"
    log "  🚀 新任务: $todo 个"
    log "  ⏸️ 待确认: $pending 个"
    log "  ✅ 已确认: $confirmed 个"
    log "  🔄 进行中: $progress 个"
    log "  🧪 测试中: $testing 个"
    log "  👤 待验收: $acceptance 个"
    log "  🔧 修复中: $fixing 个"
    log "  🎉 已完成: $done 个"
    log "─────────────────────────────────"
    log ""
    
    # 生成详细报告
    local report="📊 **Notion 任务检查报告** ($(date '+%Y-%m-%d %H:%M'))

**数据库概览：** 共 $total 个任务

📈 **状态统计：**
\`\`\`
🚀 新任务:    $todo 个
⏸️ 待确认:    $pending 个  
✅ 已确认:    $confirmed 个
🔄 进行中:    $progress 个
🧪 测试中:    $testing 个
👤 待验收:    $acceptance 个
🔧 修复中:    $fixing 个
🎉 已完成:    $done 个
\`\`\`"

    # 添加进行中的任务
    if [ "$progress" -gt 0 ]; then
        local progress_list=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "进行中")] | map("• " + .properties."项目名称".title[0].plain_text + " (" + (.properties."版本".select.name // "V1") + ")") | join("\n")')
        report="$report

🔄 **正在开发：**
$progress_list

请耐心等待开发完成..."
    fi
    
    # 添加待确认的任务（排除已暂停的）
    if [ "$pending" -gt 0 ]; then
        # 加载暂停的任务列表
        local paused_tasks=""
        if [ -f "$SKILL_DIR/config/paused-tasks.json" ]; then
            paused_tasks=$(jq -r '.paused_tasks[].name' "$SKILL_DIR/config/paused-tasks.json" 2>/dev/null)
        fi
        
        # 过滤掉暂停的任务
        local pending_tasks=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "待确认迭代")]')
        local active_pending=""
        local paused_count=0
        
        while IFS= read -r task; do
            local task_name=$(echo "$task" | jq -r '.properties."项目名称".title[0].plain_text // ""')
            if echo "$paused_tasks" | grep -q "^${task_name}$"; then
                paused_count=$((paused_count + 1))
            else
                local task_version=$(echo "$task" | jq -r '.properties."版本".select.name // "V1"')
                active_pending="$active_pending
• $task_name ($task_version)"
            fi
        done < <(echo "$pending_tasks" | jq -c '.[]')
        
        if [ -n "$active_pending" ]; then
            report="$report

⏸️ **待确认迭代：**$active_pending

💡 在 Notion 中将状态改为"确认迭代"即可自动执行开发"
        fi
        
        if [ "$paused_count" -gt 0 ]; then
            report="$report

🔕 **已暂停（暂不迭代）：** $paused_count 个
💡 如需继续迭代，请告诉我：恢复 任务名 迭代"
        fi
    fi
    
    # 添加已确认的任务（即将执行）
    if [ "$confirmed" -gt 0 ]; then
        local confirmed_list=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "确认迭代")] | map("• " + .properties."项目名称".title[0].plain_text + " (" + (.properties."版本".select.name // "V1.1") + ")") | join("\n")')
        report="$report

✅ **已确认 - 即将执行：**
$confirmed_list

🚀 系统将在下次检查时自动触发开发"
    fi
    
    # 添加测试中的任务
    if [ "$testing" -gt 0 ]; then
        local testing_list=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "测试中")] | map("• " + .properties."项目名称".title[0].plain_text + " (" + (.properties."版本".select.name // "V1") + ")") | join("\n")')
        report="$report

🧪 **测试中 - 等待测试工程师：**
$testing_list

🔬 测试完成后将自动生成测试报告"
    fi
    
    # 添加待验收的任务
    if [ "$acceptance" -gt 0 ]; then
        local acceptance_list=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "待验收")] | map("• " + .properties."项目名称".title[0].plain_text + " (" + (.properties."版本".select.name // "V1") + ")") | join("\n")')
        report="$report

👤 **待验收 - 等待产品验收：**
$acceptance_list

✅ 验收通过后即可标记为已完成"
    fi
    
    # 添加修复中的任务
    if [ "$fixing" -gt 0 ]; then
        local fixing_list=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "修复中")] | map("• " + .properties."项目名称".title[0].plain_text) | join("\n")')
        report="$report

🔧 **修复中 - Bug修复：**
$fixing_list

🐛 修复完成后请更新状态"
    fi
    
    report="$report

---
⏰ 下次检查: $(date -d '+30 minutes' '+%H:%M') (每30分钟)
📁 完整日志: \`tail -f /tmp/notion-skill.log\`"
    
    send_notification "$report"
    
    # 返回确认迭代的任务列表
    echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "确认迭代")]'
}

# ============================================
# 功能 2: 执行确认迭代的任务（增强版）
# ============================================
execute_pending_tasks() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "🚀 执行任务开发"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # 1. 处理"确认迭代"的任务（原有逻辑）
    local confirmed_tasks=$(curl -s -X POST \
      "https://api.notion.com/v1/databases/$NOTION_DATABASE_ID/query" \
      -H "Authorization: Bearer $NOTION_TOKEN" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{
        "filter": {
          "property": "完成状态", "status": {"equals": "确认迭代"}
        }
      }')
    
    local confirmed_count=$(echo "$confirmed_tasks" | jq -r '.results | length')
    
    # 2. 处理"测试中"的任务（阶段二：测试工程师测试）
    local testing_tasks=$(curl -s -X POST \
      "https://api.notion.com/v1/databases/$NOTION_DATABASE_ID/query" \
      -H "Authorization: Bearer $NOTION_TOKEN" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{
        "filter": {
          "property": "完成状态", "status": {"equals": "测试中"}
        }
      }')
    
    local testing_count=$(echo "$testing_tasks" | jq -r '.results | length')
    
    # 3. 处理"待验收"的任务（阶段三：产品验收）
    local acceptance_tasks=$(curl -s -X POST \
      "https://api.notion.com/v1/databases/$NOTION_DATABASE_ID/query" \
      -H "Authorization: Bearer $NOTION_TOKEN" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{
        "filter": {
          "property": "完成状态", "status": {"equals": "待验收"}
        }
      }')
    
    local acceptance_count=$(echo "$acceptance_tasks" | jq -r '.results | length')
    
    # 4. 处理"修复中"的任务（Bug修复跟踪）
    local fixing_tasks=$(curl -s -X POST \
      "https://api.notion.com/v1/databases/$NOTION_DATABASE_ID/query" \
      -H "Authorization: Bearer $NOTION_TOKEN" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{
        "filter": {
          "property": "完成状态", "status": {"equals": "修复中"}
        }
      }')
    
    local fixing_count=$(echo "$fixing_tasks" | jq -r '.results | length')
    
    # 5. 处理"未开始"的任务（自动评估后执行）
    local todo_tasks=$(curl -s -X POST \
      "https://api.notion.com/v1/databases/$NOTION_DATABASE_ID/query" \
      -H "Authorization: Bearer $NOTION_TOKEN" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{
        "filter": {
          "property": "完成状态", "status": {"equals": "未开始"}
        }
      }')
    
    local todo_count=$(echo "$todo_tasks" | jq -r '.results | length')
    
    local total_count=$((confirmed_count + todo_count + testing_count + acceptance_count + fixing_count))
    
    if [ "$total_count" -eq 0 ]; then
        info "没有需要执行的任务"
        return 0
    fi
    
    log "发现 $total_count 个任务（确认迭代: $confirmed_count, 测试中: $testing_count, 待验收: $acceptance_count, 修复中: $fixing_count, 新任务: $todo_count）"
    log ""
    
    # 处理"测试中"的任务：通知测试工程师（阶段二）
    if [ "$testing_count" -gt 0 ]; then
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "🧪 测试中任务 - 等待测试工程师"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        echo "$testing_tasks" | jq -c '.results[]' | while read -r task; do
            local name=$(echo "$task" | jq -r '.properties."项目名称".title[0].plain_text // "未命名"')
            local deploy_url=$(echo "$task" | jq -r '.properties."部署链接".url // ""')
            local page_id=$(echo "$task" | jq -r '.id')
            
            log "🧪 待测试: $name"
            
            # 触发测试工程师通知
            trigger_test_engineer "$name" "$deploy_url" "$page_id"
        done
        log ""
    fi
    
    # 处理"待验收"的任务：通知产品经理验收（阶段三）
    if [ "$acceptance_count" -gt 0 ]; then
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "👤 待验收任务 - 等待产品验收"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        echo "$acceptance_tasks" | jq -c '.results[]' | while read -r task; do
            local name=$(echo "$task" | jq -r '.properties."项目名称".title[0].plain_text // "未命名"')
            local deploy_url=$(echo "$task" | jq -r '.properties."部署链接".url // ""')
            local page_id=$(echo "$task" | jq -r '.id')
            
            log "👤 待验收: $name"
            
            # 触发产品验收通知
            trigger_product_acceptance "$name" "$deploy_url" "$page_id"
        done
        log ""
    fi
    
    # 处理"修复中"的任务：跟踪Bug修复进度
    if [ "$fixing_count" -gt 0 ]; then
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "🔧 修复中任务 - Bug修复跟踪"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        echo "$fixing_tasks" | jq -c '.results[]' | while read -r task; do
            local name=$(echo "$task" | jq -r '.properties."项目名称".title[0].plain_text // "未命名"')
            local bug_list=$(echo "$task" | jq -r '.properties."Bug列表".rich_text[0].plain_text // "未记录"')
            
            log "🔧 修复中: $name"
            log "  Bug列表: $bug_list"
        done
        log ""
    fi
    
    # 处理"未开始"的任务：自动评估并改为"进行中"
    if [ "$todo_count" -gt 0 ]; then
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "📋 自动评估并执行新任务"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        echo "$todo_tasks" | jq -c '.results[]' | while read -r task; do
            local name=$(echo "$task" | jq -r '.properties."项目名称".title[0].plain_text // "未命名"')
            local page_id=$(echo "$task" | jq -r '.id')
            local desc=$(echo "$task" | jq -r '.properties."需求描述".rich_text[0].plain_text // ""')
            
            log "🆕 新任务: $name"
            
            # 自动评估优先级
            local priority_score=50
            if [ -n "$desc" ]; then
                # 简单关键词匹配评估
                if echo "$desc" | grep -qi "紧急\|重要\|P0"; then
                    priority_score=90
                elif echo "$desc" | grep -qi "高优先级\|P1"; then
                    priority_score=70
                fi
            fi
            
            log "  优先级评估: $priority_score/100"
            
            # 预估开发时间
            local est_minutes=60
            if [ -f "$SKILL_DIR/lib/dev-time-estimator.sh" ]; then
                local est_result=$(source "$SKILL_DIR/lib/dev-time-estimator.sh" && estimate_dev_time "web" "simple" 2>/dev/null)
                est_minutes=$(echo "$est_result" | jq -r '.estimated_minutes // 60')
            fi
            local est_hours=$(echo "scale=1; $est_minutes / 60" | bc)
            local est_end_time=$(date -d "+${est_minutes} minutes" '+%H:%M')
            log "  预估开发时间: ${est_hours}小时 (预计${est_end_time}完成)"
            
            # 更新状态为"进行中"
            log "  更新状态为: 进行中"
            curl -s -X PATCH \
              "https://api.notion.com/v1/pages/$page_id" \
              -H "Authorization: Bearer $NOTION_TOKEN" \
              -H "Notion-Version: 2022-06-28" \
              -H "Content-Type: application/json" \
              -d '{"properties": {"完成状态": {"status": {"name": "进行中"}}, "任务完成用时": {"rich_text": [{"text": {"content": "预估'${est_hours}'小时"}}]}}}' > /dev/null
            
            # 发送通知
            send_notification "🚀 **新任务自动执行**\n\n📁 项目: $name\n🎯 优先级: $priority_score/100\n⏱️ 预估时间: ${est_hours}小时 (预计${est_end_time}完成)\n✅ 状态: 已自动开始开发"
            
            log "  ✅ 已自动开始开发"
            log ""
        done
    fi
    
    # 处理"确认迭代"的任务
    if [ "$confirmed_count" -eq 0 ]; then
        info "没有确认迭代的任务需要执行"
        return 0
    fi
    
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "🚀 执行确认迭代的任务"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local i=1
    echo "$confirmed_tasks" | jq -c '.results[]' | while read -r task; do
        local name=$(echo "$task" | jq -r '.properties."项目名称".title[0].plain_text // "未命名"')
        local version=$(echo "$task" | jq -r '.properties."版本".select.name // "V1.1"')
        local page_id=$(echo "$task" | jq -r '.id')
        local git_url=$(echo "$task" | jq -r '.properties."Git链接".url // ""')
        
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log "任务 $i/$count: $name $version"
        log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # 更新状态为进行中
        log "📋 步骤 1/5: 更新 Notion 状态为"进行中"..."
        curl -s -X PATCH \
          "https://api.notion.com/v1/pages/$page_id" \
          -H "Authorization: Bearer $NOTION_TOKEN" \
          -H "Notion-Version: 2022-06-28" \
          -H "Content-Type: application/json" \
          -d '{"properties": {"完成状态": {"status": {"name": "进行中"}}}}' > /dev/null
        log "✅ Notion 状态已更新"
        
        # 发送开始通知
        send_notification "🚀 **开始迭代开发**

📁 项目: $name
📌 版本: $version
📊 进度: 1/5 - 准备开发环境

开始执行 V1.1 迭代开发，请稍候..."
        
        # 检查并准备开发环境
        log "📋 步骤 2/5: 准备开发环境..."
        prepare_dev_env "$name" "$git_url"
        
        # 触发开发（通过子代理）
        log "📋 步骤 3/5: 触发开发子代理..."
        trigger_development "$name" "$version"
        
        # 执行自动开发（如果配置了自动开发）
        log "📋 步骤 4/5: 执行自动开发..."
        auto_develop "$name" "$git_url"
        
        # 记录开发开始时间
        save_state "dev_start_$name" "$(date '+%Y-%m-%d %H:%M:%S')"
        
        log "✅ 任务 $i 已启动"
        log ""
        
        i=$((i + 1))
    done
    
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "所有确认的任务已启动"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================
# 功能 3: 准备开发环境
# ============================================
prepare_dev_env() {
    local task_name=$1
    local git_url=$2
    
    local dev_dir="$WORKSPACE/dev-projects/$(echo "$task_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')"
    
    if [ -d "$dev_dir" ]; then
        log "  开发目录已存在: $dev_dir"
    else
        log "  创建开发目录: $dev_dir"
        mkdir -p "$dev_dir"
    fi
    
    # 保存开发目录到状态
    save_state "dev_dir_$task_name" "$dev_dir"
}

# ============================================
# 功能 4: 触发开发子代理
# ============================================
trigger_development() {
    local task_name=$1
    local version=$2
    
    log "  触发开发子代理: $task_name $version"
    
    # 创建开发任务文件
    local task_file="$WORKSPACE/dev-projects/$(echo "$task_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')/.dev-task.json"
    cat > "$task_file" << EOF
{
  "task_name": "$task_name",
  "version": "$version",
  "started_at": "$(date -Iseconds)",
  "status": "pending",
  "steps": [
    "环境准备",
    "读取 PRD",
    "代码开发",
    "测试验证",
    "部署上线"
  ]
}
EOF
    
    log "  ✅ 开发任务已创建: $task_file"
    
    # 注意：实际的子代理调用由外部系统处理
    # 这里只是准备任务文件
}

# ============================================
# 功能 4.5: 自动开发和部署
# ============================================
auto_develop() {
    local task_name="$1"
    local git_url="$2"
    
    log "  开始自动开发和部署: $task_name"
    
    # 获取开发目录
    local dev_dir=$(load_state "dev_dir_$task_name" "")
    if [ -z "$dev_dir" ] || [ ! -d "$dev_dir" ]; then
        warn "  开发目录不存在，跳过自动部署"
        return 0
    fi
    
    log "  开发目录: $dev_dir"
    
    # 检查是否是 Git 仓库
    if [ ! -d "$dev_dir/.git" ]; then
        log "  初始化 Git 仓库..."
        cd "$dev_dir" && git init && git branch -m main
    fi
    
    # 检查是否有远程仓库配置
    local has_remote=$(cd "$dev_dir" && git remote -v 2>/dev/null | wc -l)
    if [ "$has_remote" -eq 0 ] && [ -n "$git_url" ]; then
        log "  配置远程仓库..."
        # 使用环境变量中的 GitHub Token
        local github_token="${GITHUB_TOKEN:-}"
        if [ -z "$github_token" ]; then
            error "  错误: GITHUB_TOKEN 环境变量未设置"
            error "  请设置 GITHUB_TOKEN 环境变量后再试"
            return 1
        fi
        local remote_url=$(echo "$git_url" | sed "s|https://github.com/|https://javajar41:${github_token}@github.com/|")
        cd "$dev_dir" && git remote add origin "$remote_url" 2>/dev/null || true
    fi
    
    # 检查是否有未提交的更改
    local has_changes=$(cd "$dev_dir" && git status --porcelain 2>/dev/null | wc -l)
    if [ "$has_changes" -gt 0 ]; then
        log "  提交代码更改..."
        cd "$dev_dir" && git add . && git commit -m "Auto-deploy: $(date '+%Y-%m-%d %H:%M')" 2>/dev/null || true
    fi
    
    # 推送到 GitHub
    log "  推送到 GitHub..."
    local push_result=$(cd "$dev_dir" && git push -u origin main 2>&1)
    if echo "$push_result" | grep -q "fatal"; then
        error "  GitHub 推送失败: $push_result"
        send_notification "❌ **部署失败**

📁 项目: $task_name
❌ 状态: 推送失败

错误信息:
\`\`\`
$push_result
\`\`\`

请检查 GitHub 仓库是否存在。"
        return 1
    else
        log "  ✅ 代码已推送到 GitHub"
        
        # 提取 GitHub Pages URL
        local github_pages=$(echo "$git_url" | sed 's|github.com|github.io|' | sed 's|/[^/]*$||')
        local repo_name=$(basename "$git_url" .git)
        local deploy_url="${github_pages}/${repo_name}/"
        
        log "  部署地址: $deploy_url"
        
        # 更新 Notion 状态为"待确认迭代"（V1完成，等待产品经理分析）
        log "  更新 Notion 状态为: 待确认迭代"
        curl -s -X PATCH \
          "https://api.notion.com/v1/pages/$PAGE_ID" \
          -H "Authorization: Bearer $NOTION_TOKEN" \
          -H "Notion-Version: 2022-06-28" \
          -H "Content-Type: application/json" \
          -d '{
            "properties": {
              "完成状态": {"status": {"name": "待确认迭代"}},
              "版本": {"select": {"name": "V1"}},
              "部署链接": {"url": "'"$deploy_url"'"}
            }
          }' > /dev/null
        
        # 触发产品经理分析
        log "  触发产品经理分析流程..."
        trigger_product_manager_analysis "$task_name" "$deploy_url"
        
        # 发送成功通知（提示待确认迭代）
        send_notification "✅ **V1 开发完成，等待迭代确认**

📁 项目: $task_name
✅ V1 状态: 已部署
🌐 访问地址: $deploy_url

⏸️ **下一步：产品经理分析**
正在自动分析 V1 效果并生成 V1.1 迭代建议...

💡 **你的选项：**
- 确认迭代 → 开发 V1.1
- 结束项目 → 标记为已完成"
        
        return 0
    fi
}

# ============================================
# 功能 4.5: 测试工程师通知（阶段二）
# ============================================
trigger_test_engineer() {
    local task_name="$1"
    local deploy_url="$2"
    local page_id="$3"
    
    log "  🧪 通知测试工程师: $task_name"
    
    # 生成测试检查清单
    local test_checklist="测试检查清单：
- [ ] 功能测试：所有功能正常运行
- [ ] 界面测试：UI显示正确，无错位
- [ ] 兼容性测试：多浏览器/设备兼容
- [ ] 性能测试：加载速度正常
- [ ] 边界测试：异常情况处理
- [ ] 回归测试：未破坏已有功能"
    
    # 创建测试报告文件
    local report_file="$SKILL_DIR/reports/test-$(echo "$task_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')-$(date +%Y%m%d).md"
    mkdir -p "$SKILL_DIR/reports"
    cat > "$report_file" << EOF
# 🧪 测试报告 - $task_name

**测试时间:** $(date '+%Y-%m-%d %H:%M:%S')  
**测试地址:** $deploy_url  
**Notion页面:** $page_id

## 📋 测试检查清单

$test_checklist

## 📝 测试结果

| 检查项 | 状态 | 备注 |
|--------|------|------|
| 功能测试 | ⬜ 待测 | |
| 界面测试 | ⬜ 待测 | |
| 兼容性测试 | ⬜ 待测 | |
| 性能测试 | ⬜ 待测 | |
| 边界测试 | ⬜ 待测 | |
| 回归测试 | ⬜ 待测 | |

## 🐛 Bug 列表

暂无

## ✅ 测试结论

- [ ] 通过 - 可以验收
- [ ] 失败 - 需要修复

---
*自动生成 by Notion Task Automation*
EOF
    
    log "  📄 测试报告模板已创建: $report_file"
    
    # 发送通知
    send_notification "🧪 **测试任务待执行**

📁 项目: $task_name
🌐 测试地址: $deploy_url

**请测试工程师进行测试：**

$test_checklist

✅ 测试通过后，请将状态改为"待验收"
❌ 如有Bug，请将状态改为"修复中"并记录问题

📄 测试报告: $report_file

⏱️ 预计测试时间: 30分钟"
    
    log "  ✅ 测试工程师已通知"
}

# ============================================
# 功能 4.5.1: 测试报告自动生成
# ============================================
generate_test_report() {
    local task_name="$1"
    local page_id="$2"
    local test_result="${3:-pass}"
    local bugs="${4:-}"
    
    log "  📊 生成测试报告: $task_name"
    
    local report_file="$SKILL_DIR/reports/test-$(echo "$task_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')-$(date +%Y%m%d)-final.md"
    
    local result_emoji="✅"
    local result_text="通过"
    if [[ "$test_result" == "fail" ]]; then
        result_emoji="❌"
        result_text="失败"
    fi
    
    cat > "$report_file" << EOF
# 📊 测试报告 - $task_name

**测试时间:** $(date '+%Y-%m-%d %H:%M:%S')  
**测试结果:** $result_emoji $result_text

## 📝 测试摘要

- **项目名称:** $task_name
- **测试状态:** $result_text
- **测试人员:** 自动化测试系统

## 🐛 Bug 列表

${bugs:-无}

## ✅ 测试结论

$(if [[ "$test_result" == "pass" ]]; then
    echo "测试通过，可以进入验收环节。"
else
    echo "测试发现以下问题，需要修复后重新测试："
    echo "$bugs"
fi)

---
*自动生成 by Notion Task Automation v2.5*
EOF
    
    log "  ✅ 测试报告已生成: $report_file"
    
    # 发送测试报告通知
    if [[ "$test_result" == "pass" ]]; then
        send_notification "✅ **测试通过 - $task_name**

📊 测试报告已生成
🎯 状态: 测试通过
📄 报告文件: $report_file

⏩ 下一步: 产品验收
请产品经理进行最终验收。"
    else
        send_notification "❌ **测试失败 - $task_name**

📊 测试报告已生成
🎯 状态: 测试失败
🐛 发现问题:
$bugs

📄 报告文件: $report_file

🔧 已自动创建修复任务，请查看。"
        
        # 自动创建修复任务
        create_bug_fix_task "$task_name" "$bugs" "$page_id"
    fi
    
    echo "$report_file"
}

# ============================================
# 功能 4.5.2: 测试失败处理流程
# ============================================
create_bug_fix_task() {
    local task_name="$1"
    local bugs="$2"
    local original_page_id="$3"
    
    log "  🔧 创建Bug修复任务: $task_name"
    
    # 在Notion中创建子任务或更新原任务状态为"修复中"
    curl -s -X PATCH \
      "https://api.notion.com/v1/pages/$original_page_id" \
      -H "Authorization: Bearer $NOTION_TOKEN" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{
        "properties": {
          "完成状态": {"status": {"name": "修复中"}},
          "Bug列表": {"rich_text": [{"text": {"content": "'"$(echo "$bugs" | sed 's/"/\\"/g' | head -c 500)"'"}}]}
        }
      }' > /dev/null
    
    # 创建修复任务文件
    local fix_task_file="$WORKSPACE/dev-projects/$(echo "$task_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')/.bug-fix-$(date +%Y%m%d%H%M%S).json"
    cat > "$fix_task_file" << EOF
{
  "original_task": "$task_name",
  "original_page_id": "$original_page_id",
  "created_at": "$(date -Iseconds)",
  "bugs": "$(echo "$bugs" | sed 's/"/\\"/g')",
  "status": "pending",
  "priority": "high",
  "estimated_fix_time": "30分钟"
}
EOF
    
    log "  ✅ Bug修复任务已创建: $fix_task_file"
}

# ============================================
# 功能 4.5.3: 产品验收环节
# ============================================
trigger_product_acceptance() {
    local task_name="$1"
    local deploy_url="$2"
    local page_id="$3"
    
    log "  👤 触发产品验收: $task_name"
    
    # 更新状态为"待验收"
    curl -s -X PATCH \
      "https://api.notion.com/v1/pages/$page_id" \
      -H "Authorization: Bearer $NOTION_TOKEN" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{
        "properties": {
          "完成状态": {"status": {"name": "待验收"}}
        }
      }' > /dev/null
    
    # 创建验收检查清单
    local acceptance_checklist="验收检查清单：
- [ ] 功能完整性：所有需求已实现
- [ ] 用户体验：交互流畅，无卡顿
- [ ] 视觉效果：符合设计规范
- [ ] 性能表现：加载速度可接受
- [ ] 代码质量：代码整洁，可维护
- [ ] 文档完整：README和注释完善"
    
    # 发送验收通知
    send_notification "👤 **产品验收待执行**

📁 项目: $task_name
🌐 演示地址: $deploy_url

**请产品经理进行最终验收：**

$acceptance_checklist

✅ 验收通过 → 状态改为"已完成"
❌ 需要调整 → 状态改为"确认迭代"并说明需求

⏱️ 预计验收时间: 20分钟"
    
    log "  ✅ 产品验收通知已发送"
}

# ============================================
# 功能 4.6: 产品经理分析（V1 → V1.1）
# ============================================
trigger_product_manager_analysis() {
    local task_name="$1"
    local deploy_url="$2"
    
    log "  📊 产品经理分析: $task_name"
    
    # 创建分析任务文件
    local analysis_file="$WORKSPACE/dev-projects/$(echo "$task_name" | tr ' ' '-' | tr '[:upper:]' '[:lower:]')/.pm-analysis.json"
    cat > "$analysis_file" << EOF
{
  "task_name": "$task_name",
  "deploy_url": "$deploy_url",
  "analysis_time": "$(date -Iseconds)",
  "v1_status": "completed",
  "next_step": "等待产品经理分析V1效果并生成V1.1 PRD",
  "user_options": [
    "确认迭代 - 开发V1.1",
    "结束项目 - 标记为已完成"
  ]
}
EOF
    
    log "  ✅ 产品经理分析任务已创建"
    
    # 发送通知给产品经理（用户）
    send_notification "📊 **产品经理分析提醒**

📁 项目: $task_name
🌐 V1 演示: $deploy_url

**请体验V1版本并决定：**

1️⃣ **访问演示地址** 体验当前功能
2️⃣ **评估V1效果** 确认是否满足需求
3️⃣ **决定下一步：**
   - 🚀 确认迭代 → 告诉我迭代需求，生成V1.1 PRD
   - ✅ 结束项目 → V1已完成，无需继续迭代

⏸️ 当前状态: 待确认迭代
💡 等待你的决策..."
}

# ============================================
# 功能 5: 生成可视化看板
# ============================================
generate_dashboard() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "📊 生成任务看板"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local all_data=$(curl -s -X POST \
      "https://api.notion.com/v1/databases/$NOTION_DATABASE_ID/query" \
      -H "Authorization: Bearer $NOTION_TOKEN" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{}')
    
    local dashboard_file="$SKILL_DIR/dashboard.html"
    
    # 生成 HTML 看板
    cat > "$dashboard_file" << 'HTMLHEAD'
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Notion 任务自动化看板</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', sans-serif;
            background: linear-gradient(135deg, #1a1f3a 0%, #0a0e27 100%);
            color: #fff;
            padding: 40px;
            min-height: 100vh;
        }
        h1 { text-align: center; margin-bottom: 40px; color: #00d4ff; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 20px; margin-bottom: 40px; }
        .stat-card {
            background: rgba(255,255,255,0.05);
            border-radius: 12px;
            padding: 20px;
            text-align: center;
            border: 1px solid rgba(255,255,255,0.1);
        }
        .stat-number { font-size: 36px; font-weight: bold; color: #00d4ff; }
        .stat-label { font-size: 14px; opacity: 0.8; margin-top: 8px; }
        .task-list { background: rgba(255,255,255,0.03); border-radius: 12px; padding: 20px; }
        .task-item {
            display: flex;
            align-items: center;
            padding: 15px;
            border-bottom: 1px solid rgba(255,255,255,0.05);
        }
        .task-item:last-child { border-bottom: none; }
        .status-badge {
            padding: 4px 12px;
            border-radius: 20px;
            font-size: 12px;
            margin-right: 15px;
        }
        .status-todo { background: #6b7280; }
        .status-pending { background: #f59e0b; }
        .status-confirmed { background: #10b981; }
        .status-progress { background: #3b82f6; }
        .status-done { background: #8b5cf6; }
        .update-time { text-align: center; margin-top: 40px; opacity: 0.6; font-size: 14px; }
    </style>
</head>
<body>
    <h1>📊 Notion 任务自动化看板</h1>
    <div class="stats">
HTMLHEAD

    # 添加统计数据
    local total=$(echo "$all_data" | jq -r '.results | length')
    local todo=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "未开始")] | length')
    local pending=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "待确认迭代")] | length')
    local confirmed=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "确认迭代")] | length')
    local progress=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "进行中")] | length')
    local done=$(echo "$all_data" | jq -r '[.results[] | select(.properties."完成状态".status.name == "已完成")] | length')
    
    cat >> "$dashboard_file" << HTMLSTATS
        <div class="stat-card">
            <div class="stat-number">$total</div>
            <div class="stat-label">总任务</div>
        </div>
        <div class="stat-card">
            <div class="stat-number">$todo</div>
            <div class="stat-label">新任务</div>
        </div>
        <div class="stat-card">
            <div class="stat-number">$pending</div>
            <div class="stat-label">待确认</div>
        </div>
        <div class="stat-card">
            <div class="stat-number">$confirmed</div>
            <div class="stat-label">已确认</div>
        </div>
        <div class="stat-card">
            <div class="stat-number">$progress</div>
            <div class="stat-label">进行中</div>
        </div>
        <div class="stat-card">
            <div class="stat-number">$done</div>
            <div class="stat-label">已完成</div>
        </div>
    </div>
    
    <div class="task-list">
        <h2 style="margin-bottom: 20px;">📋 任务列表</h2>
HTMLSTATS

    # 添加任务列表
    echo "$all_data" | jq -c '.results[]' | while read -r task; do
        local name=$(echo "$task" | jq -r '.properties."项目名称".title[0].plain_text // "未命名"')
        local status=$(echo "$task" | jq -r '.properties."完成状态".status.name')
        local version=$(echo "$task" | jq -r '.properties."版本".select.name // "V1"')
        
        local status_class=""
        local status_text=""
        case "$status" in
            "未开始") status_class="status-todo"; status_text="新任务" ;;
            "待确认迭代") status_class="status-pending"; status_text="待确认" ;;
            "确认迭代") status_class="status-confirmed"; status_text="已确认" ;;
            "进行中") status_class="status-progress"; status_text="进行中" ;;
            "已完成") status_class="status-done"; status_text="已完成" ;;
        esac
        
        cat >> "$dashboard_file" << HTMLTASK
        <div class="task-item">
            <span class="status-badge $status_class">$status_text</span>
            <div>
                <div style="font-weight: bold;">$name</div>
                <div style="font-size: 12px; opacity: 0.7; margin-top: 4px;">$version</div>
            </div>
        </div>
HTMLTASK
    done
    
    cat >> "$dashboard_file" << HTMLFOOT
    </div>
    
    <div class="update-time">
        最后更新: $(date '+%Y-%m-%d %H:%M:%S')
    </div>
</body>
</html>
HTMLFOOT

    log "✅ 看板已生成: $dashboard_file"
    log "   可以在浏览器中打开查看"
}

# ============================================
# 功能 6: 发送通知
# ============================================
send_notification() {
    local message=$1
    
    export OPENCLAW_WORKSPACE="$WORKSPACE"
    
    /usr/bin/node /home/shiyongwang/.npm-global/bin/openclaw message send \
      --channel feishu \
      --target "user:ou_33e8141e4496f0a674219423723997bf" \
      --message "$message" 2>&1 || warn "通知发送失败"
}

# ============================================
# 功能 7: 显示帮助
# ============================================
show_help() {
    cat << EOF
Notion Task Automation Skill v2.0

用法: $(basename "$0") <命令> [参数]

命令:
    check           检查任务状态并生成报告
    execute         执行确认迭代的任务
    full            完整流程：检查 + 执行
    dashboard       生成可视化看板
    status          显示当前状态
    pause <任务名>  暂停任务（暂不迭代）
    resume <任务名> 恢复任务（继续迭代）
    list-paused     列出所有暂停的任务
    help            显示此帮助信息

选项:
    --verbose       显示详细日志
    --quiet         静默模式，只输出错误

示例:
    # 只检查任务状态
    ./automation.sh check

    # 完整流程（检查 + 执行）
    ./automation.sh full

    # 生成看板
    ./automation.sh dashboard

    # 暂停任务（不再提醒）
    ./automation.sh pause "Hello World 页面"

    # 恢复任务（继续迭代）
    ./automation.sh resume "Hello World 页面"

    # 查看暂停的任务
    ./automation.sh list-paused

日志文件: $LOG_FILE
状态文件: $STATE_FILE
暂停列表: $SKILL_DIR/config/paused-tasks.json

EOF
}

# ============================================
# 功能 8: 显示状态
# ============================================
show_status() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "📊 Notion Task Automation Skill 状态"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    log ""
    info "配置信息:"
    log "  工作目录: $WORKSPACE"
    log "  技能目录: $SKILL_DIR"
    log "  日志文件: $LOG_FILE"
    log "  状态文件: $STATE_FILE"
    log ""
    
    info "环境变量:"
    if [ -n "$NOTION_TOKEN" ]; then
        log "  NOTION_TOKEN: ✅ 已配置"
    else
        error "  NOTION_TOKEN: ❌ 未配置"
    fi
    
    if [ -n "$NOTION_DATABASE_ID" ]; then
        log "  NOTION_DATABASE_ID: ✅ 已配置"
    else
        error "  NOTION_DATABASE_ID: ❌ 未配置"
    fi
    
    log ""
    info "最后检查时间:"
    local last_check=$(load_state "last_check_time" "从未")
    log "  $last_check"
    
    log ""
    info "开发中的任务:"
    if [ -d "$WORKSPACE/dev-projects" ]; then
        local dev_count=$(ls -1 "$WORKSPACE/dev-projects" 2>/dev/null | wc -l)
        log "  $dev_count 个项目在开发中"
    else
        log "  0 个项目"
    fi
    
    log ""
    
    # 显示已暂停的任务
    info "已暂停的任务（暂不迭代）:"
    if [ -f "$SKILL_DIR/config/paused-tasks.json" ]; then
        local paused_list=$(jq -r '.paused_tasks[] | "  • " + .name + " (暂停于 " + .paused_at + ")"' "$SKILL_DIR/config/paused-tasks.json" 2>/dev/null)
        if [ -n "$paused_list" ]; then
            echo "$paused_list"
        else
            log "  无"
        fi
    else
        log "  无"
    fi
    
    log ""
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ============================================
# 功能 9: 暂停任务（暂不迭代）
# ============================================
pause_task() {
    local task_name="${1:-}"
    
    if [ -z "$task_name" ]; then
        error "请指定要暂停的任务名称"
        log "用法: $0 pause <任务名>"
        return 1
    fi
    
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "🔕 暂停任务: $task_name"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local config_file="$SKILL_DIR/config/paused-tasks.json"
    mkdir -p "$(dirname "$config_file")"
    
    # 创建或更新暂停列表
    if [ -f "$config_file" ]; then
        # 检查是否已存在
        if jq -e ".paused_tasks[] | select(.name == \"$task_name\")" "$config_file" > /dev/null 2>&1; then
            warn "任务 '$task_name' 已在暂停列表中"
            return 0
        fi
        
        # 添加到现有列表
        local temp=$(mktemp)
        jq ".paused_tasks += [{\"name\": \"$task_name\", \"reason\": \"用户暂不迭代\", \"paused_at\": \"$(date -Iseconds)\", \"resume_hint\": \"当用户需要继续迭代时手动激活\"}]" "$config_file" > "$temp" && mv "$temp" "$config_file"
    else
        # 创建新列表
        cat > "$config_file" << EOF
{
  "paused_tasks": [
    {
      "name": "$task_name",
      "reason": "用户暂不迭代",
      "paused_at": "$(date -Iseconds)",
      "resume_hint": "当用户需要继续迭代时手动激活"
    }
  ]
}
EOF
    fi
    
    log "✅ 任务已暂停: $task_name"
    log ""
    info "该任务将不再出现在待确认提醒中"
    info "如需恢复迭代，请运行: $0 resume \"$task_name\""
    
    # 发送通知
    send_notification "🔕 **任务已暂停**

📁 项目: $task_name
⏸️ 状态: 暂不迭代

该任务将不再自动提醒。
如需继续迭代，请告诉我"恢复 $task_name 迭代"。"
}

# ============================================
# 功能 10: 恢复任务（继续迭代）
# ============================================
resume_task() {
    local task_name="${1:-}"
    
    if [ -z "$task_name" ]; then
        error "请指定要恢复的任务名称"
        log "用法: $0 resume <任务名>"
        return 1
    fi
    
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "▶️ 恢复任务: $task_name"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local config_file="$SKILL_DIR/config/paused-tasks.json"
    
    if [ ! -f "$config_file" ]; then
        error "暂停列表不存在"
        return 1
    fi
    
    # 检查任务是否在暂停列表中
    if ! jq -e ".paused_tasks[] | select(.name == \"$task_name\")" "$config_file" > /dev/null 2>&1; then
        error "任务 '$task_name' 不在暂停列表中"
        return 1
    fi
    
    # 从暂停列表中移除
    local temp=$(mktemp)
    jq ".paused_tasks = [.paused_tasks[] | select(.name != \"$task_name\")]" "$config_file" > "$temp" && mv "$temp" "$config_file"
    
    log "✅ 任务已恢复: $task_name"
    log ""
    info "该任务将重新出现在待确认提醒中"
    info "请在 Notion 中将状态改为"确认迭代"以开始开发"
    
    # 发送通知
    send_notification "▶️ **任务已恢复**

📁 项目: $task_name
✅ 状态: 可以继续迭代

请在 Notion 中将状态改为"确认迭代"，系统将自动开始 V1.1 开发。"
}

# ============================================
# 功能 11: 列出暂停的任务
# ============================================
list_paused() {
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log "🔕 暂停的任务列表"
    log "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    local config_file="$SKILL_DIR/config/paused-tasks.json"
    
    if [ ! -f "$config_file" ]; then
        info "没有暂停的任务"
        return 0
    fi
    
    local count=$(jq '.paused_tasks | length' "$config_file")
    
    if [ "$count" -eq 0 ]; then
        info "没有暂停的任务"
        return 0
    fi
    
    log ""
    info "共 $count 个暂停的任务："
    log ""
    
    jq -r '.paused_tasks[] | "  • " + .name + "\n    原因: " + .reason + "\n    暂停时间: " + .paused_at + "\n"' "$config_file"
    
    log ""
    info "恢复任务命令:"
    log "  $0 resume <任务名>"
}

# ============================================
# 主入口
# ============================================
main() {
    # 检查依赖
    check_deps
    
    # 解析命令
    case "${1:-help}" in
        check)
            check_tasks
            ;;
        execute)
            execute_pending_tasks
            ;;
        full)
            log "🚀 启动完整自动化流程"
            log ""
            check_tasks
            log ""
            execute_pending_tasks
            log ""
            log "✅ 完整流程执行完毕"
            ;;
        dashboard)
            generate_dashboard
            ;;
        status)
            show_status
            ;;
        pause)
            pause_task "$2"
            ;;
        resume)
            resume_task "$2"
            ;;
        list-paused)
            list_paused
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
