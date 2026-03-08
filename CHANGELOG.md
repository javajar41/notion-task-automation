# Changelog

## [2.5.2] - 2026-03-09

### Fixed
- **修复跨平台路径硬编码问题** (Critical)
  - 移除所有 `/home/shiyongwang` 硬编码路径
  - 添加动态路径检测逻辑，支持 Linux/macOS/Windows WSL
  - 支持 `OPENCLAW_WORKSPACE` 环境变量覆盖
  
### Changed
- 路径检测优先级：
  1. `OPENCLAW_WORKSPACE` 环境变量（最高优先级）
  2. `$HOME/.openclaw/workspace` 自动检测
  3. 脚本相对位置自动推断
- 更新 `config/.env.example` 添加路径配置选项
- 更新 `config/SETUP.md` 添加跨平台配置说明

### Files Modified
- `automation.sh` - 动态路径检测
- `lib/api-cache.sh` - 跨平台支持
- `lib/notification-sender.sh` - 动态 openclaw 路径检测
- `lib/notion-change-detector.sh` - 动态 WORKSPACE 检测
- `lib/report-generator.sh` - 动态路径检测
- `lib/skill-recommender.sh` - 移除硬编码路径
- `multi-db-wrapper.sh` - 动态路径检测
- `config/.env.example` - 添加路径配置
- `config/SETUP.md` - 添加跨平台说明

## [2.5.1] - 2026-03-08

### Fixed
- **修复任务统计显示为空的问题**
- **修复整数表达式错误**
- **修复缓存系统兼容性**

## [2.5.0] - 2026-03-08

### Added
- 分享版本打包（Skill + GitHub）
- 一键安装脚本
- GitHub Actions CI
- 完整配置文档

## [2.0.0] - 2026-03-04

### Added
- 完整任务状态检查
- 自动执行确认迭代的任务
- 可视化看板生成
- 产品经理分析工作流
- API 缓存系统
