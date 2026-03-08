#!/bin/bash
# Notion Task Automation - 多渠道通知发送器 (P2-2)
# 修复版本：支持跨平台路径检测

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/notifications.json"

# 动态检测 WORKSPACE
if [ -n "$OPENCLAW_WORKSPACE" ]; then
    WORKSPACE="$OPENCLAW_WORKSPACE"
elif [ -n "$HOME" ] && [ -d "$HOME/.openclaw/workspace" ]; then
    WORKSPACE="$HOME/.openclaw/workspace"
else
    WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

# 检测 openclaw 命令位置
detect_openclaw() {
    if command -v openclaw &> /dev/null; then
        echo "openclaw"
    elif [ -x "$HOME/.npm-global/bin/openclaw" ]; then
        echo "$HOME/.npm-global/bin/openclaw"
    elif [ -x "/usr/local/bin/openclaw" ]; then
        echo "/usr/local/bin/openclaw"
    elif [ -x "$WORKSPACE/../node_modules/.bin/openclaw" ]; then
        echo "$WORKSPACE/../node_modules/.bin/openclaw"
    else
        echo "openclaw"  # 回退，让系统 PATH 去查找
    fi
}

# 加载配置
load_notification_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "{}"
        return
    fi
    cat "$CONFIG_FILE"
}

# 发送 Feishu 通知
send_feishu() {
    local message="$1"
    local target="${2:-${NOTIFY_TARGET:-user:ou_33e8141e4496f0a674219423723997bf}}"
    
    export OPENCLAW_WORKSPACE="$WORKSPACE"
    
    local openclaw_cmd=$(detect_openclaw)
    
    $openclaw_cmd message send \
        --channel feishu \
        --target "$target" \
        --message "$message" 2>&1
}

# 发送邮件通知（简化版，需要配置 mail 命令）
send_email() {
    local subject="$1"
    local body="$2"
    local to="${3:-${NOTIFY_EMAIL:-}}"
    
    if [[ -z "$to" ]]; then
        echo "错误: 未配置邮件接收地址"
        return 1
    fi
    
    echo "$body" | mail -s "$subject" "$to" 2>&1 || echo "邮件发送失败"
}

# 发送 Slack 通知
send_slack() {
    local message="$1"
    local webhook="${2:-${SLACK_WEBHOOK:-}}"
    
    if [[ -z "$webhook" ]]; then
        echo "错误: 未配置 Slack Webhook"
        return 1
    fi
    
    curl -s -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"$message\"}" \
        "$webhook" 2>&1
}

# 统一发送接口
send_notification() {
    local channel="$1"
    local message="$2"
    local target="$3"
    
    case "$channel" in
        feishu)
            send_feishu "$message" "$target"
            ;;
        email)
            send_email "Notion Task Automation" "$message" "$target"
            ;;
        slack)
            send_slack "$message" "$target"
            ;;
        *)
            echo "不支持的通知渠道: $channel"
            return 1
            ;;
    esac
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 测试发送
    send_feishu "测试通知消息"
fi
