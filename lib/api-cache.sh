#!/bin/bash
# api-cache.sh - Notion API 缓存系统
# 减少API调用次数，缓存查询结果

CACHE_DIR="/tmp/notion-api-cache"
CACHE_TTL=300  # 缓存有效期5分钟（300秒）

# 初始化缓存目录
init_cache() {
    if [ ! -d "$CACHE_DIR" ]; then
        mkdir -p "$CACHE_DIR"
    fi
}

# 生成缓存key
get_cache_key() {
    local operation="$1"
    echo "${CACHE_DIR}/${operation}.json"
}

# 检查缓存是否有效
cache_is_valid() {
    local cache_file="$1"
    
    if [ ! -f "$cache_file" ]; then
        return 1  # 缓存不存在
    fi
    
    local cache_time=$(stat -c %Y "$cache_file" 2>/dev/null || stat -f %m "$cache_file" 2>/dev/null)
    local current_time=$(date +%s)
    local age=$((current_time - cache_time))
    
    if [ $age -gt $CACHE_TTL ]; then
        return 1  # 缓存已过期
    fi
    
    return 0  # 缓存有效
}

# 从缓存读取
cache_get() {
    local operation="$1"
    local cache_file=$(get_cache_key "$operation")
    
    if cache_is_valid "$cache_file"; then
        cat "$cache_file"
        return 0
    fi
    
    return 1
}

# 保存到缓存
cache_set() {
    local operation="$1"
    local data="$2"
    local cache_file=$(get_cache_key "$operation")
    
    init_cache
    echo "$data" > "$cache_file"
}

# 清除缓存
cache_clear() {
    if [ -d "$CACHE_DIR" ]; then
        rm -rf "$CACHE_DIR"/*
    fi
}

# 缓存查询所有任务（优化版）
cached_query_all_tasks() {
    local force_refresh="${1:-false}"
    
    # 尝试从缓存获取
    if [ "$force_refresh" != "true" ]; then
        local cached_data=$(cache_get "all_tasks")
        local cache_status=$?
        if [ $cache_status -eq 0 ] && [ -n "$cached_data" ]; then
            echo "$cached_data"
            return 0
        fi
    fi
    
    # 缓存未命中，调用API
    local result
    result=$(curl -s -X POST \
      "https://api.notion.com/v1/databases/${NOTION_DATABASE_ID}/query" \
      -H "Authorization: Bearer ${NOTION_TOKEN}" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d '{}') || true
    
    # 保存到缓存
    if [ -n "$result" ]; then
        cache_set "all_tasks" "$result"
    fi
    
    echo "$result"
}

# 缓存查询特定状态的任务
cached_query_by_status() {
    local status="$1"
    local force_refresh="${2:-false}"
    local cache_key="tasks_status_${status}"
    
    # 尝试从缓存获取
    if [ "$force_refresh" != "true" ]; then
        local cached_data=$(cache_get "$cache_key")
        if [ $? -eq 0 ]; then
            echo "$cached_data"
            return 0
        fi
    fi
    
    # 缓存未命中，调用API
    local result=$(curl -s -X POST \
      "https://api.notion.com/v1/databases/${NOTION_DATABASE_ID}/query" \
      -H "Authorization: Bearer ${NOTION_TOKEN}" \
      -H "Notion-Version: 2022-06-28" \
      -H "Content-Type: application/json" \
      -d "{
        \"filter\": {
          \"property\": \"完成状态\", \"status\": {\"equals\": \"$status\"}
        }
      }")
    
    # 保存到缓存
    cache_set "$cache_key" "$result"
    
    echo "$result"
}

# 获取缓存统计信息
cache_stats() {
    init_cache
    
    local cache_count=$(ls -1 "$CACHE_DIR" 2>/dev/null | wc -l)
    local cache_size=$(du -sh "$CACHE_DIR" 2>/dev/null | cut -f1)
    
    echo "缓存文件数: $cache_count"
    echo "缓存大小: $cache_size"
    echo "缓存TTL: ${CACHE_TTL}秒"
    
    if [ $cache_count -gt 0 ]; then
        echo "缓存内容:"
        ls -la "$CACHE_DIR"
    fi
}

# 如果直接运行此脚本
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-stats}" in
        stats)
            cache_stats
            ;;
        clear)
            cache_clear
            echo "✅ 缓存已清除"
            ;;
        *)
            echo "用法: $0 [stats|clear]"
            ;;
    esac
fi
