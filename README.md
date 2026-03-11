# CCodexSkill — 跨模型 AI 代码审查

> 让 Claude Code 和 Codex CLI 协同审查你的代码，无需 API Key

**[中文](#为什么需要这个工具)** | **[English](#english)**

---

## 为什么需要这个工具？

**问题**：基于 API Key 的 AI 代码审查 token 消耗高昂，对个人开发者和小团队不友好。

**解决方案**：利用你已有的 **Claude Pro/Max 订阅** 和 **ChatGPT Plus 订阅**，通过 Claude Code CLI + Codex CLI 实现两大顶级模型的协同代码审查——**零 API 费用**。

```
┌─────────────┐    git diff     ┌─────────────┐
│ Claude Code  │ ──────────────→ │  Codex CLI   │
│  (修复代码)   │                │  (独立审查)    │
│ Claude Opus  │ ←────────────── │   GPT model  │
└─────────────┘   审查反馈       └─────────────┘
       │                                │
       └──── 迭代循环 (最多 3 轮) ────────┘
                     │
                     ▼
            📋 中文审查报告
```

## 特性

- **跨模型独立审查** — Claude Opus (修复) + GPT (审查)，两个模型互相校验
- **6 维度系统化审查** — 正确性、安全性、错误处理、性能、代码质量、语言规范
- **迭代修复循环** — 最多 3 轮，审查→修复→复审，直到通过
- **增量复审** — 后续轮次追踪验证前轮问题修复状态
- **中文审查报告** — 结构化中文报告，包含问题清单、修复详情、误报分析
- **多语言适配** — Python / JavaScript / TypeScript / Go / Java 语言特定检查
- **零 API 费用** — 仅使用订阅额度，无需任何 API Key

## 前置要求

| 工具 | 要求 | 安装方式 |
|------|------|----------|
| **Claude Code** | 已安装并登录 | [安装指南](https://docs.anthropic.com/en/docs/claude-code/overview) |
| **Codex CLI** | 已安装并登录 ChatGPT Plus | `npm i -g @openai/codex` |
| **Git** | 项目需为 git 仓库 | 系统自带或 `apt install git` |
| **Node.js** | >= 18.0 | [nvm](https://github.com/nvm-sh/nvm) 推荐 |

## 安装

### 方式一：Claude Code Plugin 安装（推荐）

```bash
# 在 Claude Code 中运行
claude plugin add https://github.com/LanEinstein/CCodexSkill
```

### 方式二：手动安装

```bash
# 1. 克隆仓库
git clone https://github.com/LanEinstein/CCodexSkill.git

# 2. 复制命令到用户级目录
mkdir -p ~/.claude/commands
cp CCodexSkill/commands/codex-review.md ~/.claude/commands/

# 3. 复制技能到用户级目录
mkdir -p ~/.claude/skills
cp -r CCodexSkill/skills/codex-review ~/.claude/skills/

# 4. 复制脚本到用户级目录
mkdir -p ~/.claude/scripts
cp CCodexSkill/scripts/run-codex-review.sh ~/.claude/scripts/
chmod +x ~/.claude/scripts/run-codex-review.sh

# 5. 更新脚本路径（手动安装必须）
# 编辑 ~/.claude/commands/codex-review.md 和 ~/.claude/skills/codex-review/SKILL.md
# 将 scripts/run-codex-review.sh 替换为 ~/.claude/scripts/run-codex-review.sh

# 6. 添加权限（在项目 .claude/settings.local.json 中）
# 见下方"权限配置"章节
```

> **注意**：手动安装后需要更新脚本路径。将 SKILL.md 和 codex-review.md 中的 `scripts/run-codex-review.sh` 替换为 `~/.claude/scripts/run-codex-review.sh` 的绝对路径。

### 权限配置

在项目的 `.claude/settings.local.json` 中添加以下权限：

```json
{
  "permissions": {
    "allow": [
      "Bash(command -v codex)",
      "Bash(codex --version)",
      "Bash(codex exec:*)",
      "Bash(codex review:*)",
      "Bash(bash scripts/run-codex-review.sh:*)",
      "Bash(timeout:*)",
      "Bash(git rev-parse:*)",
      "Bash(git diff:*)",
      "Bash(git add:*)",
      "Bash(mkdir:*)"
    ]
  }
}
```

## 快速开始

```bash
# 1. 在你的项目中修改一些代码
vim src/auth.py

# 2. 启动 Claude Code
claude

# 3. 运行审查命令
/codex-review

# 4. 等待审查循环完成，查看中文报告
```

## 使用指南

### 基本用法

```
/codex-review
```

审查所有未提交的变更，默认最多迭代 3 轮。

### 指定最大轮次

```
/codex-review --max-cycles 2
```

### 指定审查文件

```
/codex-review --files src/auth.ts,src/db.ts
```

### 保存报告到文件

```
/codex-review --save
```

报告将保存到 `./codex-review-report.md`。

## 审查维度详解

### 1. 正确性与逻辑 (CRITICAL)

逻辑错误、边界条件、竞态条件、算法选择错误。这是最高优先级维度——代码首先要正确。

### 2. 安全性 (CRITICAL)

硬编码密钥、SQL/命令注入、XSS/CSRF/SSRF、输入验证缺失、敏感数据泄露。安全问题必须在发布前修复。

### 3. 错误处理与韧性 (HIGH)

空 catch 块、缺失错误传播、未处理的 Promise rejection、缺少超时设置、静默失败。

### 4. 性能 (MEDIUM)

O(n²) 可优化为 O(n)、热路径中的不必要分配、N+1 查询、无界数据获取。

### 5. 代码质量与可维护性 (MEDIUM)

过长函数（>50行）、过深嵌套（>4层）、代码重复、命名不清晰、死代码。

### 6. 语言/框架最佳实践 (LOW)

根据项目主要语言自动注入特定检查项：

| 语言 | 检查重点 |
|------|----------|
| Python | 可变默认参数、裸 except、类型注解缺失、未使用 with 语句 |
| JS/TS | useEffect 依赖遗漏、any 滥用、== vs ===、未捕获 async 异常 |
| Go | 未检查 error、goroutine 泄漏、context 未传递 |
| Java | 资源未关闭、空指针、Optional 误用、缺少 @Override |

## 工作流程详解

```
Phase 1: PREPARE ─── 验证前置条件、收集变更信息、检测语言
    │
    ▼
Phase 2: REVIEW ──── 调用 Codex CLI 执行独立审查
    │
    ▼
Phase 3: EVALUATE ── 解析 Codex 输出、提取问题清单与判定
    │
    ▼
Phase 4: FIX ─────── Claude Code 修复问题、标注误报
    │
    ▼
Phase 5: LOOP ────── 判断: 通过? 达到上限? 继续?
    │                    │
    │ (继续)             │ (结束)
    └──→ Phase 2         ▼
                    Phase 6: REPORT ── 生成中文审查报告
```

## 报告示例

<details>
<summary>点击展开完整报告示例</summary>

```markdown
# Codex 跨模型代码审查报告

**项目**: my-web-app
**审查时间**: 2026-03-11 14:30:00
**审查轮次**: 2 / 3
**最终判定**: PASS

---

## 审查概览

| 指标 | 值 |
|------|-----|
| 变更文件数 | 3 |
| 变更行数 | 87 |
| 发现问题总数 | 4 |
| 已修复 | 3 |
| 误报排除 | 1 |
| 未解决 | 0 |

## 各轮次详情

### 第 1 轮

**Codex 判定**: NEEDS_FIXES

| # | 严重度 | 文件 | 问题描述 | 置信度 | 处理结果 |
|---|--------|------|----------|--------|----------|
| 1 | CRITICAL | src/auth.py:42 | SQL 注入：用户输入直接拼接到查询 | HIGH(95) | 已修复 |
| 2 | CRITICAL | src/auth.py:58 | 密码以明文存储在日志中 | HIGH(90) | 已修复 |
| 3 | WARNING | src/utils.ts:15 | 缺少空值检查，可能导致运行时错误 | MEDIUM(70) | 已修复 |
| 4 | INFO | src/main.go:3 | 未使用的导入 | MEDIUM(60) | 误报排除 |

### 第 2 轮

**Codex 判定**: PASS

所有前轮问题已正确修复，未发现新问题。

## 误报分析

| # | 问题 | 排除理由 |
|---|------|----------|
| 4 | src/main.go:3 未使用的导入 | 该导入用于 build tag 条件编译，在生产构建中使用 |

## 审查维度覆盖

| 维度 | 发现问题 |
|------|----------|
| 正确性与逻辑 | 0 |
| 安全性 | 2 |
| 错误处理 | 1 |
| 性能 | 0 |
| 代码质量 | 1 |
| 语言规范 | 0 |
```

</details>

## 常见问题

### Q: Codex CLI 未安装怎么办？

运行 `npm i -g @openai/codex` 安装，然后用 `codex login` 登录你的 ChatGPT Plus 账号。

### Q: 审查超时了怎么办？

默认超时 300 秒。如果项目较大，可以指定文件缩小范围：
```
/codex-review --files src/critical-module.ts
```

### Q: 支持哪些编程语言？

所有语言都支持基础审查（维度 1-5）。Python、JavaScript/TypeScript、Go、Java 有额外的语言特定检查（维度 6）。

### Q: 如何自定义审查标准？

编辑 `skills/codex-review/SKILL.md` 中的审查 prompt 模板，可以添加或修改维度检查项。

### Q: 两个 AI 模型会产生冲突吗？

不会。Codex 只负责审查（只读模式），Claude Code 负责修复。如果 Claude Code 认为 Codex 的建议是误报，会在报告中标注理由，不会盲目修改。

### Q: 审查结果不准确怎么办？

置信度 < 50 的问题已被自动过滤。如果仍有误报，Claude Code 会自动识别并标注。你也可以减少 max-cycles 来加快流程。

## 架构说明

```
┌──────────────────────────────────────────────────────────┐
│                    Claude Code CLI                        │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌────────────┐ │
│  │ /codex-review│───→│  SKILL.md    │───→│  Report    │ │
│  │   command    │    │  (6 phases)  │    │  Generator │ │
│  └──────────────┘    └──────┬───────┘    └────────────┘ │
│                             │                            │
│                     ┌───────▼────────┐                   │
│                     │ run-codex-     │                   │
│                     │ review.sh      │                   │
│                     └───────┬────────┘                   │
│                             │                            │
└─────────────────────────────┼────────────────────────────┘
                              │ subprocess
                     ┌────────▼────────┐
                     │   Codex CLI     │
                     │  (read-only)    │
                     │                 │
                     │ codex review    │  ← 第 1 轮
                     │ codex exec      │  ← 第 2+ 轮
                     └─────────────────┘
```

**数据流**：
1. `git diff` → Codex 自动读取未提交变更
2. Codex 输出 → 写入 `/tmp/codex_review_*.md` 临时文件
3. Claude Code 读取临时文件 → 解析问题 → 修复代码
4. 修复后的代码 `git add` 暂存 → 进入下一轮 Codex 审查

## 贡献

欢迎贡献！请查看 [Issues](https://github.com/LanEinstein/CCodexSkill/issues) 获取待办事项。

1. Fork 本仓库
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交变更 (`git commit -m 'Add amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 发起 Pull Request

## 许可证

[MIT](LICENSE) - 随意使用和修改。

---

<a name="english"></a>

## English

### What is CCodexSkill?

A Claude Code plugin that enables **cross-model code review** using Claude Code + Codex CLI. Claude Code writes/fixes code, Codex CLI independently reviews it — no API keys required, only your existing subscriptions (Claude Pro/Max + ChatGPT Plus).

### Key Features

- **Cross-model review**: Claude Opus (fix) + GPT (review) — two models cross-validate
- **6-dimension analysis**: Correctness, Security, Error Handling, Performance, Code Quality, Language Best Practices
- **Iterative fix loop**: Up to 3 rounds of review → fix → re-review
- **Incremental re-review**: Subsequent rounds track previous issue resolution
- **Chinese reports**: Structured reports in Chinese (customizable)
- **Multi-language**: Python / JS / TS / Go / Java specific checks
- **Zero API cost**: Uses subscription quotas only

### Quick Start

```bash
# Install the plugin
claude plugin add https://github.com/LanEinstein/CCodexSkill

# In your project, after making changes:
/codex-review
```

### Requirements

- Claude Code CLI (installed & authenticated)
- Codex CLI (`npm i -g @openai/codex`, authenticated with ChatGPT Plus)
- Git repository with uncommitted changes
