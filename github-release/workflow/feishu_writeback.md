# Feishu Writeback Protocol

## 推荐方式：一键脚本

```powershell
powershell -NoProfile -File tools/feishu_write.ps1 -Doc "wiki-token" -HeadingId "h4-block-id" -DescFile "desc.xml" -InterpFile "interp.xml"
```

脚本自动完成：fetch block IDs → block_replace ×2 → 输出 revision。**每次运行时重新 fetch，不依赖缓存的 block ID。**

## Block ID 生命周期 — 关键教训

**用户每次在飞书中编辑文档后，block ID 会全部重新生成。** 不要缓存 block ID。每次写入前必须重新 `docs +fetch --detail with-ids`。

正确流程：
1. `docs +fetch --detail with-ids` → 获取最新 block IDs
2. 用新 ID 做 `block_replace`
3. 如果 `block_replace` 返回 `degrade_code=1011`（未产生变化），说明 ID 已过期，重新 fetch

## `str_replace` vs `block_replace`

`str_replace` 在 markdown 模式下要求 pattern 与文档原文**逐字符完全匹配**（含空格和换行），极易因不可见字符差异而失败。**替换完整段落时，始终用 `block_replace`（XML 格式）**。

## 环境

- **始终用 `cmd /c`** 调用 lark-cli。PowerShell 会把 `@file` 当 splat 运算符。
- `@file` 用相对路径（`@desc.xml`），避免中文路径。
- 飞书 CLI 通过 `npm i -g` 安装后位于 npm 全局目录。Windows 上通常为 `%APPDATA%\npm\lark-cli.cmd`。
