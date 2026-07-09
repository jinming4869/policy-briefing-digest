# Feishu Writeback Protocol

## 推荐方式：一键脚本

```powershell
powershell -NoProfile -File tools/feishu_write.ps1 -Doc "wiki-token" -HeadingId "h4-block-id" -DescFile "desc.xml" -InterpFile "interp.xml"
```

脚本自动完成：fetch block IDs → block_replace ×2 → 再次 fetch → 核对正文 → 输出最新 revision。**每次运行时重新 fetch，不依赖缓存的 block ID。**

## Block ID 生命周期 — 关键教训

**用户每次在飞书中编辑文档后，block ID 会全部重新生成。** 不要缓存 block ID。每次写入前必须重新 `docs +fetch --detail with-ids`。

正确流程：
1. `docs +fetch --detail with-ids` → 获取最新 block IDs
2. 用新 ID 做 `block_replace`
3. 再次 fetch 目标栏目，核对新正文并读取最新 revision
4. 如果更新失败或回读正文不一致，以非零状态退出，不声称写入成功

## `str_replace` vs `block_replace`

`str_replace` 在 markdown 模式下要求 pattern 与文档原文**逐字符完全匹配**（含空格和换行），极易因不可见字符差异而失败。**替换完整段落时，始终用 `block_replace`（XML 格式）**。

## 调用与编码

- 使用参数数组调用 `lark-cli.cmd`，不要拼接整条命令字符串。
- `--content` 的 `@file` 作为独立参数传入，脚本会解析为绝对路径。
- 脚本使用 UTF-8 BOM 保存，兼容 Windows PowerShell 5.1。
- 默认从 PATH 查找 `lark-cli.cmd`；需要固定版本或自定义路径时使用 `-LarkCli`。
- 官方安装命令：`npx @larksuite/cli@latest install`。
