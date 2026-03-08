# Notion Task Automation Skill - 环境配置

## 🔧 配置步骤

### 1. 复制配置文件

```bash
cp config/.env.example config/.env
```

### 2. 编辑 .env 文件

```bash
# 编辑配置文件
nano config/.env
```

### 3. 获取 Notion Token

1. 访问 https://www.notion.so/my-integrations
2. 点击 "New integration"
3. 填写名称，选择关联的工作空间
4. 复制 "Internal Integration Token"

### 4. 获取 Database ID

1. 打开你的 Notion 数据库页面
2. 从URL复制数据库ID：
   ```
   https://www.notion.so/workspace/xxx?v=yyy
                              ^^^
                           这就是 Database ID
   ```
3. 将数据库分享给 Integration：
   - 点击数据库右上角的 "..."
   - 选择 "Add connections"
   - 选择你创建的 Integration

### 5. 配置路径（跨平台支持）⭐

**Linux 用户（默认无需修改）：**
```bash
# 默认自动检测，无需配置
# OPENCLAW_WORKSPACE=$HOME/.openclaw/workspace
```

**macOS 用户（默认无需修改）：**
```bash
# 默认自动检测，无需配置
# OPENCLAW_WORKSPACE=$HOME/.openclaw/workspace
```

**自定义路径（如需要）：**
```bash
# 手动指定工作区路径
OPENCLAW_WORKSPACE=/Users/yourname/.openclaw/workspace
```

**自动检测逻辑：**
脚本会按以下优先级检测路径：
1. `OPENCLAW_WORKSPACE` 环境变量（最高优先级）
2. `$HOME/.openclaw/workspace`（自动检测）
3. 脚本所在位置的相对路径（自动推断）

### 6. 配置通知（可选）

```bash
# 飞书通知
NOTIFY_CHANNEL=feishu
NOTIFY_TARGET=user:your_user_id

# 或邮件通知
NOTIFY_CHANNEL=email
NOTIFY_EMAIL=your@email.com
```

### 7. 设置定时任务（可选）

```bash
# 编辑 crontab
crontab -e

# 添加以下行（每30分钟执行一次）
*/30 * * * * /path/to/automation.sh full >> /tmp/notion-skill.log 2>&1
```

## 🔒 安全提示

- **永远不要**将 `.env` 文件提交到 Git
- `.env` 文件已添加到 `.gitignore`
- 定期更换 Notion Token
- 使用只读权限的 Integration Token（最小权限原则）

## 🐛 故障排除

### 问题1：缺少 NOTION_TOKEN
```
错误: 缺少 NOTION_TOKEN 或 NOTION_DATABASE_ID
```
**解决：** 检查 `.env` 文件是否存在且配置正确

### 问题2：路径错误（跨平台）
```
错误: WORKSPACE 目录不存在
```
**解决：** 
1. 检查 `config/.env` 中的 `OPENCLAW_WORKSPACE` 配置
2. 确保路径符合你的系统（Linux: `/home/用户名`, macOS: `/Users/用户名`）
3. 或让脚本自动检测（删除 OPENCLAW_WORKSPACE 配置）

### 问题3：API 请求失败
```
错误: API 请求失败
```
**解决：** 
1. 检查 Token 是否有效
2. 确认数据库已分享给 Integration
3. 查看日志：`tail -f /tmp/notion-skill.log`

### 问题4：权限不足
```
错误: 权限不足
```
**解决：** 在 Notion 中将数据库分享给 Integration

## 📞 支持

有问题？查看：
- 完整文档：[SKILL.md](./SKILL.md)
- 常见问题：[README.md](./README.md)
- 日志文件：`/tmp/notion-skill.log`
