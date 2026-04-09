---
name: codex-review
description: "Cross-model iterative code review using Claude Code + Codex CLI with structured 6-dimension analysis and Chinese report output"
origin: CCodexSkill
---

# Codex Review Skill

Cross-model collaborative code review: Claude Code writes/fixes code, Codex CLI independently reviews it. Iterates until pass or max cycles reached. Outputs a Chinese review report.

## When to Use

- User invokes `/codex-review` command
- User wants independent code review from a different AI model
- User wants systematic multi-dimension code analysis before committing

## Prerequisites

- Project must be a git repository with uncommitted changes
- `codex` CLI must be installed and authenticated (`npm i -g @openai/codex`)
- The wrapper script `scripts/run-codex-review.sh` must be accessible

## Review Flow (6 Phases)

### Phase 1: PREPARE

1. **Verify prerequisites:**
   ```bash
   git rev-parse --is-inside-work-tree
   command -v codex
   ```
2. **Collect change info:**
   ```bash
   git diff --stat
   git diff --name-only
   ```
3. **Count diff size:**
   ```bash
   git diff --shortstat
   ```
   - If >500 lines changed or >10 files: plan to split into groups of <=5 files per review call, then merge results.
4. **Apply file filter** (if `--files` was specified):
   - Parse the comma-separated file list
   - Intersect with `git diff --name-only` output
   - If no overlap, stop with: "指定的文件没有未提交的变更"
   - Subsequent phases operate only on the filtered file set
5. **Detect primary language** from file extensions in the diff. Set `LANG_HINT` variable for Phase 2.
6. **Initialize state:**
   - `CYCLE=1`
   - `MAX_CYCLES` = user parameter or default 3
   - `ISSUES_LIST=[]`
   - `FIXES_APPLIED_TOTAL=0`  ← incremented in Phase 4 each time a real fix is applied
   - `FIX_HISTORY=[]`         ← preserves per-cycle FIX_SUMMARY for Phase 6 verification prompt
   - `REVIEW_DIR=$(mktemp -d /tmp/codex_review_XXXXXX)`

### Phase 2: REVIEW — Call Codex

#### First Cycle (CYCLE == 1): Use `codex review --uncommitted`

**Important**: `codex review --uncommitted` uses Codex's built-in review analysis. It does NOT accept a custom prompt alongside `--uncommitted`. The output goes to stderr and uses Codex's own format (`[P1]`/`[P2]` priority levels).

Claude Code should parse Codex's native output format (see Phase 3) rather than expecting the structured format below. The structured format below is the **reference checklist** for Claude Code to use when evaluating Codex's findings.

**Reference Review Dimensions** (for Claude Code's evaluation in Phase 3-4):

```
You are reviewing uncommitted code changes. Analyze systematically across these dimensions:

## Dimension 1: Correctness & Logic (CRITICAL priority)
- Logic errors, off-by-one, null/undefined handling
- Edge cases not covered
- Race conditions in async/concurrent code
- Incorrect algorithm or data structure choice

## Dimension 2: Security (CRITICAL priority)
- Hardcoded secrets or credentials
- SQL/command/path injection vulnerabilities
- XSS, CSRF, SSRF risks
- Improper input validation at system boundaries
- Sensitive data exposure in logs or error messages
- Authentication/authorization bypass

## Dimension 3: Error Handling & Resilience (HIGH priority)
- Empty catch blocks or swallowed errors
- Missing error propagation
- Unhandled promise rejections / unchecked errors
- Missing timeouts on external calls
- Silent failures that hide bugs

## Dimension 4: Performance (MEDIUM priority)
- O(n^2) or worse where O(n) is possible
- Unnecessary allocations in hot paths
- Missing caching for repeated expensive operations
- N+1 query patterns
- Unbounded data fetching (no LIMIT/pagination)

## Dimension 5: Code Quality & Maintainability (MEDIUM priority)
- Functions > 50 lines that should be split
- Nesting depth > 4 levels
- Code duplication (DRY violations)
- Unclear naming or misleading variable names
- Dead code, unused imports

## Dimension 6: Language/Framework Best Practices (LOW priority)
{LANG_SPECIFIC_CHECKS}

## Output Format
For each issue found:
[SEVERITY] Title
File: path/to/file:line_number
Confidence: HIGH(80-100) / MEDIUM(50-79) / LOW(1-49)
Issue: What is wrong and why it matters
Fix: Concrete suggestion (before/after code if applicable)

Only report issues with confidence >= 50.

## Summary Table
| Severity | Count |
|----------|-------|
| CRITICAL | N     |
| WARNING  | N     |
| INFO     | N     |

## Verdict
State one of: PASS / NEEDS_FIXES / MAJOR_CONCERNS
With 1-2 sentence justification.
```

**Language-Specific Checks for Dimension 6 (`{LANG_SPECIFIC_CHECKS}`):**

| Language | Inject into `{LANG_SPECIFIC_CHECKS}` |
|----------|--------------------------------------|
| Python | `- Mutable default arguments in function signatures` / `- Bare except clauses (use specific exceptions)` / `- Missing type annotations on public functions` / `- Resource handling without context managers (with statement)` / `- f-string or .format() with user input (potential injection)` |
| JavaScript/TypeScript | `- useEffect missing dependency array items` / `- Overuse of any type bypassing type safety` / `- == instead of === for comparisons` / `- Unhandled async/await without try-catch` / `- Direct DOM manipulation in React components` |
| Go | `- Unchecked error return values` / `- Goroutine leaks (missing context cancellation)` / `- Context not propagated through call chain` / `- Using init() when explicit initialization is clearer` / `- Exported functions missing doc comments` |
| Java | `- Resources not closed (missing try-with-resources)` / `- Potential NullPointerException (no null checks)` / `- Optional misuse (get() without isPresent())` / `- Mutable objects exposed from getters` / `- Missing @Override annotation` |
| Other/Mixed | `- Follow idiomatic patterns for the detected language` / `- Flag deprecated API usage` / `- Note any framework-specific anti-patterns` |

**Execute the review:**
```bash
bash scripts/run-codex-review.sh review \
    --project-dir "$(pwd)" \
    --output "$REVIEW_DIR/cycle_${CYCLE}.md" \
    --prompt "ignored-in-review-mode"
```

**Note**: In review mode, `--prompt` is ignored. Codex uses its own built-in review analysis. The output file will contain Codex's full stderr output including diagnostic messages — Claude Code should extract the review findings (lines starting with `- [P1]`, `- [P2]`, etc.) and the summary paragraph (line starting with `codex`).

#### Subsequent Cycles (CYCLE > 1): Use `codex exec` with incremental prompt

Build an incremental review prompt:

```
You are re-reviewing code after fixes were applied.

## Previous Issues Found:
{NUMBERED_ISSUE_LIST_WITH_FILE_AND_SEVERITY}

## Fixes Applied by Developer:
{FIX_SUMMARY_PER_ISSUE}

## Your Tasks:
1. For each previous issue, verify the fix:
   - RESOLVED: Fix correctly addresses the issue
   - NOT_RESOLVED: Issue persists or fix is incomplete
   - REGRESSED: Fix introduced a new problem

2. Scan the modified code for NEW issues using the same 6 dimensions as initial review.

## Output Format
### Previous Issue Verification
| # | Issue | Status | Notes |
|---|-------|--------|-------|
{per_issue_row}

### New Issues Found
[Same format as initial review: SEVERITY, File, Confidence, Issue, Fix]

### Summary Table
| Severity | Count |
|----------|-------|
| CRITICAL | N     |
| WARNING  | N     |
| INFO     | N     |

### Verdict
PASS / NEEDS_FIXES / MAJOR_CONCERNS
```

**Execute:**
```bash
bash scripts/run-codex-review.sh exec \
    --project-dir "$(pwd)" \
    --output "$REVIEW_DIR/cycle_${CYCLE}.md" \
    --prompt "$INCREMENTAL_PROMPT"
```

### Phase 3: EVALUATE — Parse Codex Output

1. **Check the wrapper's exit code first.** If `run-codex-review.sh` returned non-zero (Codex CLI failure, upstream stream disconnect, timeout, etc.), do **NOT** parse the output for issues. Skip directly to step 5 with `verdict = UNKNOWN`.

2. Read the output file: `$REVIEW_DIR/cycle_${CYCLE}.md`

3. **Detect Codex API failure markers.** Even when the wrapper exit was zero, the output file may contain failure markers from a partial response. If the file contains **any** of:
   - `ERROR: stream disconnected`
   - `ERROR: Reconnecting...`
   - `Review was interrupted`
   - `Codex timed out`
   - `Error: Codex exited with code`
   - is empty or under 100 bytes
   
   then set `verdict = UNKNOWN` and skip to step 5. **Critical**: an output that contains failure markers but no `- [P1]/[P2]` lines is NOT the same as "no issues found = PASS" — Codex never actually completed the review.

4. **Parse Codex's native format** (only reached when steps 1+3 passed):
   - **For cycle 1** (`codex review` output): Look for lines matching `- [P1]` or `- [P2]` etc. Each issue block contains:
     - Priority line: `- [P1] Title — file:line-line`
     - Description: indented paragraph following the priority line
     - Summary paragraph: line starting with word `codex` near the end
   - **For cycle 2+** (`codex exec` output): Parse the structured format requested in the incremental prompt
   - Map Codex priorities to severity: `P1` → CRITICAL, `P2` → WARNING, `P3+` → INFO
   - **Determine verdict**:
     - If any P1 issues found → NEEDS_FIXES or MAJOR_CONCERNS
     - If only P2/P3 issues → NEEDS_FIXES
     - If no issues found AND a substantive summary is present (e.g. line starting with `codex` followed by reviewer text) → PASS
     - If Codex summary says "safe to ship" or similar → PASS

5. **Store result**:
   - Store parsed issues in `ISSUES_LIST` for use in Phase 4 and subsequent cycles.
   - If `verdict == UNKNOWN`: Log warning `"Codex output could not be parsed for cycle N"`. Surface prominently in the final report: `"第 N 轮审查输出不可用,代码未经实际审查"`. Do **NOT** apply any fixes in Phase 4 for an UNKNOWN cycle (there are no validated issues to act on).

### Phase 4: FIX — Claude Code Applies Fixes

**Only if verdict is NEEDS_FIXES or MAJOR_CONCERNS:**

1. For each issue (CRITICAL first, then WARNING):
   - **Assess validity**: Is this a genuine issue or a false positive?
   - If **genuine**: Apply the fix using Edit/Write tools. Record what was done. Increment `FIXES_APPLIED_TOTAL`.
   - If **false positive**: Mark as `DISMISSED` with a clear reason. Do NOT skip silently — document the rationale.
2. Stage fixed files: `git add <fixed_files>`
3. Build `FIX_SUMMARY` for the incremental prompt:
   ```
   Issue #1 [CRITICAL] SQL Injection in auth.py:42 → FIXED: Used parameterized query
   Issue #2 [WARNING] Missing null check in utils.ts:15 → FIXED: Added guard clause
   Issue #3 [INFO] Unused import in main.go:3 → DISMISSED: Import used in build tag
   ```
4. Append the current cycle's `FIX_SUMMARY` (tagged with cycle number) to `FIX_HISTORY` so Phase 6 can replay the full fix trail to Codex during verification.

### Phase 5: LOOP — Decide Next Action

Track the exit reason in a variable `EXIT_REASON` so Phase 6 can decide whether to run final verification.

```
IF verdict == "UNKNOWN":
    # Codex itself failed (upstream error, timeout, etc.). No fixes possible.
    # Try one more cycle in case the failure was transient.
    IF this is the FIRST consecutive UNKNOWN AND CYCLE < MAX_CYCLES:
        CYCLE += 1
        → Go to Phase 2 (retry with same mode)
    ELSE:
        # Two consecutive UNKNOWNs OR already at max cycles → bail out cleanly.
        EXIT_REASON = "codex_unavailable"
        → Go to Phase 7 (skip Phase 6 — there is nothing to verify)

ELIF verdict == "PASS":
    EXIT_REASON = "passed"
    → Go to Phase 6
ELIF CYCLE >= MAX_CYCLES:
    EXIT_REASON = "max_cycles_reached"
    → Go to Phase 6
ELIF no fixes were applied (all dismissed):
    EXIT_REASON = "all_dismissed"
    → Go to Phase 6
ELSE:
    CYCLE += 1              ← increment FIRST
    → Go to Phase 2         ← then use new CYCLE value for output filename
```

**Important**: Always increment `CYCLE` before constructing the output path `cycle_${CYCLE}.md` to avoid overwriting previous cycle output.

### Phase 6: FINAL VERIFICATION — Read-only Closure Check

**Purpose**: When the loop exits because `MAX_CYCLES` was reached and Claude Code applied at least one fix in the last (or any) cycle, those final fixes have **never been re-checked by Codex**. This phase runs one extra read-only Codex pass to give the user real closure on whether the last round of changes actually resolved the issues — without consuming a fix cycle and without applying any new edits.

**Trigger decision**:

```
IF EXIT_REASON == "codex_unavailable":
    VERIFICATION_STATUS = "SKIPPED"
    SKIP_REASON = "codex_unavailable"
    → Go to Phase 7 (Phase 7 must surface this prominently)
ELIF EXIT_REASON == "passed":
    VERIFICATION_STATUS = "SKIPPED"
    SKIP_REASON = "first_or_intermediate_cycle_passed"
    → Go to Phase 7
ELIF EXIT_REASON == "all_dismissed" OR FIXES_APPLIED_TOTAL == 0:
    VERIFICATION_STATUS = "SKIPPED"
    SKIP_REASON = "no_fixes_applied"
    → Go to Phase 7
ELSE:  # EXIT_REASON == "max_cycles_reached" AND FIXES_APPLIED_TOTAL > 0
    VERIFICATION_STATUS = "EXECUTED"
    → Run verification below, then Phase 7
```

**Verification prompt** (built from `FIX_HISTORY`):

```
This is a FINAL VERIFICATION pass after {TOTAL_CYCLES} review-fix cycles.
Do NOT propose new improvements or refactors. This is a closure check, not another review.

## Previously reported issues across all cycles (with attempted fixes):
{FIX_HISTORY_FLATTENED}

## Your tasks:
1. For each previously reported issue, classify the CURRENT state of the code:
   - RESOLVED   : The fix correctly addresses it
   - UNRESOLVED : Issue still present or fix is incomplete
   - REGRESSED  : Fix introduced a new defect

2. Scan ONLY for NEW CRITICAL (P1) regressions introduced by the fixes themselves.
   IGNORE all P2/P3, style, and maintainability findings — they are out of scope here.

## Output Format
### Verification Table
| # | Original Issue | Status | Notes |
|---|----------------|--------|-------|

### New Critical Regressions (if any)
[SEVERITY] file:line — description
(Output the literal word "NONE" if no regressions found.)

### Final Verdict
PASS    — all previously reported issues RESOLVED, no regressions
PARTIAL — some issues UNRESOLVED but no critical regressions
FAILED  — at least one REGRESSED entry, or a P1-severity issue is still UNRESOLVED
```

**Execute**:

```bash
bash scripts/run-codex-review.sh exec \
    --project-dir "$(pwd)" \
    --output "$REVIEW_DIR/final_verification.md" \
    --prompt "$VERIFICATION_PROMPT"
```

**Parse the output** using the same logic as Phase 3, then build:

```
VERIFICATION_RESULT = {
    verdict:      PASS | PARTIAL | FAILED | UNKNOWN,
    table_rows:   [{ idx, issue, status, notes }, ...],
    regressions:  [{ severity, file, line, description }, ...],
    raw_output:   <verbatim contents of final_verification.md>
}
```

**Hard rules for this phase**:
- **Read-only**: Do NOT call Edit, Write, or `git add` here. Even if Codex flags a real remaining issue, do not fix it — it must surface in the report so the user can decide.
- **Does not increment `CYCLE`**: This is not a fix cycle.
- **Does not change `FIXES_APPLIED_TOTAL`**: No fixes happen here.
- **Unparseable / empty output**: Set `VERIFICATION_RESULT.verdict = UNKNOWN` and surface the raw output in the report. Do NOT silently treat unknown as PASS.

### Phase 7: REPORT — Generate Chinese Review Report

Generate a comprehensive Chinese report and display it to the user.

**Report Template:**

```markdown
# Codex 跨模型代码审查报告

**项目**: {project_name}
**审查时间**: {timestamp}
**审查轮次**: {total_cycles} / {max_cycles}
**最终判定**: {final_verdict_with_verification_suffix}

> `{final_verdict_with_verification_suffix}` 取值规则:
> - Phase 5 因 `passed` 退出 → `✅ 通过`
> - Phase 6 复核 verdict = PASS → `✅ 通过 (经最终复核)`
> - Phase 6 复核 verdict = PARTIAL → `⚠️ 部分通过 — 达到最大轮次后仍有 {n} 个问题未解决`
> - Phase 6 复核 verdict = FAILED → `❌ 未通过 — 复核发现严重回归 / 关键问题未解决`
> - Phase 6 复核 verdict = UNKNOWN → `❓ 复核结果不可用 — 详见最终验证章节`
> - Phase 5 因 `all_dismissed` 退出 → `ℹ️ 未变更 — 全部判定为误报`
> - Phase 5 因 `codex_unavailable` 退出 → `🚫 审查未完成 — Codex CLI 不可用 (上游错误 / 超时),代码未经实际审查`

---

## 审查概览

| 指标 | 值 |
|------|-----|
| 变更文件数 | {file_count} |
| 变更行数 | {line_count} |
| 发现问题总数 | {total_issues} |
| 已修复 | {fixed_count} |
| 误报排除 | {dismissed_count} |
| 未解决 | {unresolved_count} |

## 各轮次详情

### 第 {N} 轮

**Codex 判定**: {verdict}

#### 发现的问题

| # | 严重度 | 文件 | 问题描述 | 置信度 | 处理结果 |
|---|--------|------|----------|--------|----------|
{issue_rows}

#### 修复详情

{fix_details_per_issue}

---

## 误报分析

以下问题经 Claude Code 评估后判定为误报：

| # | 问题 | 排除理由 |
|---|------|----------|
{dismissed_rows}

## 最终验证 (Final Verification)

> 当审查在达到最大轮次时退出，会对最后一轮的修复结果执行一次独立的只读复核。

**复核状态**: {verification_status}    ← EXECUTED 或 SKIPPED
**复核判定**: {verification_verdict}    ← 仅当 EXECUTED：PASS / PARTIAL / FAILED / UNKNOWN
**跳过原因**: {skip_reason}              ← 仅当 SKIPPED：first_or_intermediate_cycle_passed / no_fixes_applied

### 历史问题复核结果

| # | 原问题 | 当前状态 | 备注 |
|---|--------|----------|------|
{verification_table_rows}

### 复核中发现的新增严重问题

| # | 严重度 | 文件 | 描述 |
|---|--------|------|------|
{regression_rows}

> 若 Codex 在复核中未报告新增严重问题，本表显示"无"。

## 未解决问题

以下问题在达到最大轮次后仍未解决：

| # | 严重度 | 文件 | 问题描述 | 建议 |
|---|--------|------|----------|------|
{unresolved_rows}

## 审查维度覆盖

| 维度 | 检查项数 | 发现问题 |
|------|----------|----------|
| 正确性与逻辑 | - | {n} |
| 安全性 | - | {n} |
| 错误处理 | - | {n} |
| 性能 | - | {n} |
| 代码质量 | - | {n} |
| 语言规范 | - | {n} |

---

> 本报告由 Claude Code + Codex CLI 协同生成
> 审查模型: Claude Code (修复) + Codex CLI (审查)
```

**Also optionally save** the report to `./codex-review-report.md` if the user requested it.

## Error Handling

| Scenario | Action |
|----------|--------|
| Not a git repo | Stop with message: "当前目录不是 git 仓库，请在 git 项目中运行 /codex-review" |
| No uncommitted changes | Stop with message: "没有未提交的变更，无需审查" |
| Codex CLI not installed | Stop with message: "未找到 codex CLI，请运行: npm i -g @openai/codex" |
| Codex timeout (exit 124) | Report partial results if available, note timeout in report |
| Codex non-zero exit | Log error, attempt to continue with available output |
| Empty Codex output | Treat as PASS with caveat note |
| Large diff (>500 lines) | Split files into groups of <=5, run multiple review calls, merge results |

## Important Notes

- **Codex is read-only**: exec mode uses `-s read-only`. Codex never modifies code.
- **Claude Code fixes**: Only Claude Code applies code changes based on Codex feedback.
- **Git state**: During the review loop, changes are staged with `git add` but NOT committed. The user decides when to commit.
- **False positives**: Claude Code uses its own judgment to dismiss false positives. Each dismissal is documented with reasoning in the final report.
- **Confidence threshold**: Only issues with confidence >= 50 are reported by Codex.
