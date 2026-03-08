#!/bin/bash
# skill-recommender.sh - Skill 自动推荐和安装系统
# 根据任务类型、阶段自动推荐并安装最优 skill
# 修复版本：支持跨平台路径检测

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DB="$1"

# 动态检测 WORKSPACE
if [ -n "$OPENCLAW_WORKSPACE" ]; then
    WORKSPACE="$OPENCLAW_WORKSPACE"
elif [ -n "$HOME" ] && [ -d "$HOME/.openclaw/workspace" ]; then
    WORKSPACE="$HOME/.openclaw/workspace"
else
    WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
fi

SKILL_DIR="$WORKSPACE/skills"

# ============================================================
# Skill 推荐数据库（使用函数替代关联数组，兼容 macOS bash）
# ============================================================

get_skill_recommendation() {
    local key="$1"
    case "$key" in
        # 产品经理阶段
        "pm_analysis") echo "superpowers-lite" ;;
        "pm_research") echo "web-search,web-fetch" ;;
        "pm_prd") echo "superpowers-lite" ;;
        "pm_general") echo "superpowers-lite" ;;
        
        # 研发工程师阶段
        "dev_web") echo "superpowers-lite,web-design-guidelines,performance,accessibility-a11y" ;;
        "dev_tool") echo "superpowers-lite" ;;
        "dev_api") echo "superpowers-lite" ;;
        "dev_script") echo "superpowers-lite" ;;
        "dev_general") echo "superpowers-lite" ;;
        
        # 测试工程师阶段
        "qa_test") echo "superpowers-lite" ;;
        "qa_auto") echo "superpowers-lite" ;;
        "qa_checklist") echo "superpowers-lite" ;;
        "qa_general") echo "superpowers-lite" ;;
        
        *) echo "" ;;
    esac
}

# ============================================================
# 函数：分析任务类型
# ============================================================
analyze_task_type() {
    local task_name="$1"
    local task_desc="$2"
    
    # 根据任务名称和描述判断类型
    if echo "$task_name $task_desc" | grep -qiE "web|网站|网页|前端|界面|页面|官网"; then
        echo "web"
    elif echo "$task_name $task_desc" | grep -qiE "工具|脚本|程序|自动化|工具"; then
        echo "tool"
    elif echo "$task_name $task_desc" | grep -qiE "api|接口|后端|服务"; then
        echo "api"
    else
        echo "general"
    fi
}

# ============================================================
# 函数：推荐 Skill
# ============================================================
recommend_skills() {
    local phase="$1"    # pm, dev, qa
    local task_type="$2"
    local task_name="$3"
    
    local key="${phase}_${task_type}"
    local recommendations=$(get_skill_recommendation "$key")
    
    # 如果没有特定推荐，使用通用推荐
    if [ -z "$recommendations" ]; then
        recommendations=$(get_skill_recommendation "${phase}_general")
    fi
    
    echo "$recommendations"
}

# ============================================================
# 函数：检查 Skill 是否已安装
# ============================================================
is_skill_installed() {
    local skill_name="$1"
    
    # 检查本地 skill 目录
    if [ -d "$SKILL_DIR/$skill_name" ]; then
        return 0
    fi
    
    # 检查 .agents/skills 目录
    if [ -d "$WORKSPACE/.agents/skills/$skill_name" ]; then
        return 0
    fi
    
    return 1
}

# ============================================================
# 函数：安装 Skill
# ============================================================
install_skill() {
    local skill_name="$1"
    local install_source="$2"
    
    echo "🔧 正在安装 skill: $skill_name"
    
    case "$skill_name" in
        "superpowers-lite")
            # 从 GitHub 安装
            if [ ! -d "$SKILL_DIR/superpowers-lite" ]; then
                cd /tmp && git clone https://github.com/JarJiang/openclaw-superpowers-lite.git 2>/dev/null
                cp -r /tmp/openclaw-superpowers-lite "$SKILL_DIR/superpowers-lite" 2>/dev/null
                rm -rf "$SKILL_DIR/superpowers-lite/.git" 2>/dev/null
                echo "✅ superpowers-lite 安装完成"
            else
                echo "✅ superpowers-lite 已安装"
            fi
            ;;
        "web-design-guidelines")
            # 从 .agents/skills 复制
            if [ -d "$WORKSPACE/.agents/skills/web-design-guidelines" ]; then
                cp -r "$WORKSPACE/.agents/skills/web-design-guidelines" "$SKILL_DIR/"
                echo "✅ web-design-guidelines 安装完成"
            elif [ -d "$HOME/.agents/skills/web-design-guidelines" ]; then
                cp -r "$HOME/.agents/skills/web-design-guidelines" "$SKILL_DIR/"
                echo "✅ web-design-guidelines 安装完成"
            else
                echo "⚠️ web-design-guidelines 源文件不存在"
            fi
            ;;
        "performance")
            if [ -d "$WORKSPACE/.agents/skills/performance" ]; then
                cp -r "$WORKSPACE/.agents/skills/performance" "$SKILL_DIR/"
                echo "✅ performance 安装完成"
            elif [ -d "$HOME/.agents/skills/performance" ]; then
                cp -r "$HOME/.agents/skills/performance" "$SKILL_DIR/"
                echo "✅ performance 安装完成"
            else
                echo "⚠️ performance 源文件不存在"
            fi
            ;;
        "accessibility-a11y")
            if [ -d "$WORKSPACE/.agents/skills/accessibility-a11y" ]; then
                cp -r "$WORKSPACE/.agents/skills/accessibility-a11y" "$SKILL_DIR/"
                echo "✅ accessibility-a11y 安装完成"
            elif [ -d "$HOME/.agents/skills/accessibility-a11y" ]; then
                cp -r "$HOME/.agents/skills/accessibility-a11y" "$SKILL_DIR/"
                echo "✅ accessibility-a11y 安装完成"
            else
                echo "⚠️ accessibility-a11y 源文件不存在"
            fi
            ;;
        *)
            echo "⚠️ 未知 skill: $skill_name，跳过安装"
            ;;
    esac
}

# ============================================================
# 函数：自动推荐并安装 Skill（主入口）
# ============================================================
auto_recommend_and_install() {
    local phase="$1"        # pm, dev, qa
    local task_name="$2"
    local task_desc="$3"
    local phase_name=""
    
    case "$phase" in
        "pm") phase_name="产品经理分析" ;;
        "dev") phase_name="研发开发" ;;
        "qa") phase_name="测试" ;;
        *) phase_name="未知阶段" ;;
    esac
    
    echo "🔍 [$phase_name] 分析任务类型并推荐最优 skill..."
    
    # 分析任务类型
    local task_type=$(analyze_task_type "$task_name" "$task_desc")
    echo "  任务类型识别: $task_type"
    
    # 获取推荐 skills
    local recommended=$(recommend_skills "$phase" "$task_type" "$task_name")
    echo "  推荐 skills: $recommended"
    
    # 安装未安装的 skills
    local installed_count=0
    IFS=',' read -ra SKILLS <<< "$recommended"
    for skill in "${SKILLS[@]}"; do
        skill=$(echo "$skill" | xargs)  # 去除空格
        if ! is_skill_installed "$skill"; then
            install_skill "$skill"
            installed_count=$((installed_count + 1))
        else
            echo "  ✅ $skill 已安装"
        fi
    done
    
    if [ $installed_count -gt 0 ]; then
        echo "✅ 成功安装 $installed_count 个 skill"
    else
        echo "✅ 所有推荐 skill 已安装"
    fi
    
    echo "$recommended"
}

# ============================================================
# 如果直接运行此脚本
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -lt 3 ]; then
        echo "用法: $0 <阶段:pm|dev|qa> <任务名> <任务描述>"
        echo ""
        echo "示例:"
        echo "  $0 pm '官网 redesign' '现代化企业官网'"
        echo "  $0 dev '官网 redesign' '现代化企业官网'"
        echo "  $0 qa '官网 redesign' '现代化企业官网'"
        exit 1
    fi
    
    auto_recommend_and_install "$1" "$2" "$3"
fi
