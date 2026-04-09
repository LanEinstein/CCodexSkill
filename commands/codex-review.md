# Codex Review — 跨模型代码审查

调用 Codex CLI 对当前项目的未提交变更进行独立审查，Claude Code 根据反馈修复问题，迭代直到通过或达到最大轮次，最终输出中文审查报告。

## Instructions

When the user runs `/codex-review`, follow these steps:

### 1. Parse Arguments

From `$ARGUMENTS`, extract:
- `--max-cycles N` — Maximum review-fix cycles (default: 3)
- `--files file1,file2,...` — Specific files to review (default: all uncommitted changes)
- `--save` — Save report to `./codex-review-report.md`

### 2. Verify Prerequisites

Run these checks and stop with a clear Chinese error message if any fail:

```bash
# Must be a git repo
git rev-parse --is-inside-work-tree

# Must have uncommitted changes
git diff --quiet && git diff --cached --quiet
# If both return 0: no changes → stop

# Codex CLI must be available
command -v codex
```

### 3. Execute Review Flow

Follow the **codex-review** skill (SKILL.md) phases 1 through 7:

- **Phase 1 (PREPARE)**: Collect change stats, detect language, initialize state
- **Phase 2 (REVIEW)**: Call Codex via `scripts/run-codex-review.sh`
- **Phase 3 (EVALUATE)**: Parse Codex output, extract issues and verdict
- **Phase 4 (FIX)**: Fix genuine issues, dismiss false positives with reasoning
- **Phase 5 (LOOP)**: Continue if needed (cycle < max-cycles and fixes applied)
- **Phase 6 (FINAL VERIFICATION)**: When max-cycles is reached with fixes applied, run one read-only Codex pass to verify the last round's fixes — no new edits
- **Phase 7 (REPORT)**: Generate and display Chinese review report (includes the final verification result)

### 4. Output

Display the Chinese review report to the user. If `--save` was specified, also write it to `./codex-review-report.md`.

## Allowed Tools

This command uses: Bash, Read, Write, Edit, Glob, Grep
