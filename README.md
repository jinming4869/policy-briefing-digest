# Policy Briefing Digest

> AI-powered policy intelligence for game & internet companies.
> 面向游戏/互联网公司的 AI 政策速递引擎。不是摘要新闻，是可以核验、追溯、执行的政策判断。

## 这是什么

一家游戏/互联网公司的合规岗，每周要从网信、工信、市监、版署、公安、法院以及海外监管机构的发布中，筛出真正影响业务的那几条，写进周报。

这个项目把这条流水线做成了一个 **Agent Skill**。你给政策线索（公众号链接、官网截图、PDF 原文，或者一句话的来源描述），它自动完成：来源核验 → 栏目判断 → 政策链条拆解 → 双版本（长版参考 + 短版正式稿）→ 质量检查 → 飞书文档写入。

核心输出不是"AI 摘要"，而是**可追溯的判断**：政策类型是什么、发布时间、文件名称、官方链接、和前置政策的门槛差异、落在哪个业务场景。

## 与同类项目的区别

市面上大多数政策 AI 工具做的是"爬虫 + 摘要"。这个项目做的是**判断力训练**。

- **不靠关键词匹配分栏目**。执法通报、征求意见稿、正式稿、首单落地、制度解读——这些文件类型有不同的判断口径，skill 里逐一规定了识别方法。
- **文风不是"要简洁"的泛泛要求**。有明确的禁用句式列表、罗列限制、抽象词限制、篇幅限制。每条规则都来自真实周报的修改对比。
- **不做新闻稿，做决策辅助**。长版帮你理清来龙去脉，短版只抓一个核心推力。两条线分开，不像大部分 AI 输出那样在"摘要"和"分析"之间模糊。

## 项目结构

```
policy-briefing-digest/
  SKILL.md                          # 主文件：全流程规则（约 1000 行）
  workbench.html                    # 交互式决策面板（见下方 §Workbench）
  LICENSE                           # MIT
  .editorconfig                     # PowerShell 5.1 编码约束
  .gitignore
  tools/
    feishu_write.ps1                # 飞书文档一键写入（fetch→replace→verify）
    doc_convert.ps1                 # .doc → .docx/.txt 转换（需 Word COM）
    gov_search.ps1                  # gov.cn 政策文件库精确搜索
  configs/
    feishu_targets.template.yaml    # 飞书文档目标配置模板
  content/
    writing_rubric.md               # 写作评分标准
    style_rules.md                  # 文风限制（禁用句式、篇幅、单一推力原则）
    anti_patterns.md                # 常见反模式
    overseas_compliance_style.md    # 海外合规栏目专用写法
  workflow/
    feishu_writeback.md             # 飞书写入协议（block ID 生命周期、str_replace vs block_replace）
  examples/
    gold_cases/
      20260626_sh_data_negative_list.md  # 范例：上海数据出境负面清单首单备案
  tests/
    validate.ps1                    # Windows PowerShell 5.1 发布校验
```

## 快速开始

### 1. 前置依赖

| 工具 | 用途 | 安装 |
|------|------|------|
| Python 3.10+ | 数据处理、校验 | `winget install python` |
| Node.js 18+ / npm | 飞书 CLI 运行环境 | `winget install nodejs` |
| PowerShell 5.1+ | 脚本运行环境 | Windows 预装 |

可选（飞书集成需要）：

| 工具 | 用途 | 安装 |
|------|------|------|
| [飞书 CLI](https://github.com/larksuite/cli) | 文档读写 | `npx @larksuite/cli@latest install` |
| Microsoft Word | .doc 转 .docx | Windows 预装或 Office 安装 |

### 2. 配置飞书（可选，跳过则仅输出可粘贴文本）

1. 将 `configs/feishu_targets.template.yaml` 复制为 `configs/feishu_targets.yaml`
2. 填入周报飞书 wiki 地址和栏目标题
3. 运行 `lark-cli auth status`，确认登录状态和文档权限

完整流程见下方 [§飞书接入](#飞书接入)。

### 3. 加载 skill

将 `SKILL.md` 作为 Agent 的 skill 文件加载。触发方式：

- 直接对话："帮我整理本周政策速递"
- 粘贴政策来源 URL 或正文
- 提及关键词：政策速递、行业监管动态、政策法规发布、海外合规风向

---

## 主动发现与 fetch

这个 skill 不要求用户先找到完整的政策网址。执行“整理本周政策速递”等任务时，Agent 会按 `SKILL.md` 中的来源清单主动检索：

- 中国政府网、网信办、工信部、市场监管总局、新闻出版署等官方来源
- 地方政府和主管部门网站
- 官方公众号、行业媒体和律所文章提供的线索
- 相关上位政策、征求意见稿、正式稿和配套解读

媒体和公众号只负责提供线索。写进周报的核心事实仍要回到官方原文核验。`tools/gov_search.ps1` 可辅助搜索中国政府网政策文件库；页面结构或反爬规则变化时，脚本会返回官方人工检索入口。

v1.0 的主动发现发生在任务执行期间，尚不包含常驻后台服务。定时扫描、增量去重、候选池和事件触发计划放在 v1.1。

---

## 飞书接入

如果你希望 Agent 在生成周报条目后**直接写入飞书文档**，而不是只给你一段可粘贴文本，这里是完整的接入链路。

### 为什么这套链路可靠

市面上的飞书文档自动化方案常见三类问题：

1. **block ID 过期**。用户在飞书中编辑文档后，block ID 会全部重新生成。很多方案缓存 block ID 不刷新，导致写入失败。
2. **str_replace 字符精度问题**。以 markdown 模式做 `str_replace` 要求 pattern 与原文逐字符完全匹配（含空格和换行），极易因不可见字符差异失败。
3. **PowerShell 编码降级**。用管道传中文正文到 lark-cli，编码可能降级为问号。

这个项目针对以上问题做了完整的工程化处理：

| 问题 | 解决方案 |
|------|----------|
| block ID 过期 | `feishu_write.ps1` 每次写入前强制 `docs +fetch --detail with-ids`，不缓存 ID |
| str_replace 精度 | 用 `block_replace` 替代 `str_replace`，操作 XML 格式段落而非 Markdown 文本匹配 |
| 编码降级 | PowerShell 脚本使用 UTF-8 BOM，正文通过 `--content @file` 传递 |
| 写入结果不确定 | 更新后重新 fetch 目标栏目，核对正文并返回最新 revision |

### 接入步骤

**第一步：安装飞书 CLI**

```powershell
npx @larksuite/cli@latest install
```

**第二步：认证**

```powershell
lark-cli config init --new
lark-cli auth login --recommend
lark-cli auth status
```

**第三步：配置周报地址**

复制配置模板并填写周报 wiki URL 与栏目标题：

```powershell
Copy-Item configs/feishu_targets.template.yaml configs/feishu_targets.yaml
```

**第四步：验证链路**

准备 UTF-8 编码的 `desc.xml` 和 `interp.xml`，每个文件包含要替换的 Docx XML 段落。手动跑一次写入流程：

```powershell
powershell -NoProfile -File tools/feishu_write.ps1 `
  -Doc "你的wiki-token" `
  -HeadingId "h4-block-id" `
  -DescFile "desc.xml" `
  -InterpFile "interp.xml"
```

**第五步：配置到 Agent**

在 Agent 的工具入口配置中，将飞书 CLI 路径和项目工具脚本路径固定下来。之后 Agent 在执行 `policy_digest_writeback` 任务时会自动走这条链路。

### 写入协议

写入流程遵循 `workflow/feishu_writeback.md` 中定义的协议：

1. `docs +fetch` → 获取最新 block IDs
2. `block_replace` × 2 → 写入政策描述 + 政策解读
3. 回读受影响区域 → 校验内容完整性
4. 输出最新 revision；更新或回读失败时以非零状态退出

**如果 CLI/API 不可用**，Agent 会降级为交付可粘贴的 Markdown 文本，不声称已完成飞书写入。

---

## Workbench

`workbench.html` 是这个项目最独特的组件：一个为 **Agent 与人类双向决策** 设计的交互面板。

### 为什么要做这个

常规的 AI Agent workflow 是单向的：人给指令 → Agent 执行 → 输出结果。但政策周报的写作过程中，Agent 经常会遇到需要人类判断的时刻：

- "这条政策应该归入'行业监管动态'还是'政策法规发布'？"
- "来源是公众号转载，无法确认原始发文机关。要标注'来源待核验'还是直接采用转载方的说法？"
- "这条政策涉及数据出境和未成年人保护两个方向，解读时只抓一个点——抓哪个？"

传统的做法是 Agent 在对话中逐条提问，人逐条回答。但一次周报可能涉及 5-8 条政策，每条政策可能触发 2-3 个决策点，问来问去对话很快就乱了。

### workbench.html 的设计

**Agent 输出决策卡片 → 粘贴到 workbench → 人类一次性做出所有选择 → 复制结果粘贴回对话。**

具体流程：

1. Agent 在处理政策时，遇到不确定的判断点，输出一个 JSON 格式的决策卡片（不需要打开浏览器，直接在对话里给）
2. 用户打开 `workbench.html`（一个纯前端 HTML 文件，双击即用，无需服务器）
3. 把 Agent 回复中的 JSON 粘贴进去
4. 卡片自动渲染为可点击的选项（单选 / 多选）
5. 逐一选择后，底部自动生成结果摘要
6. 一键复制，粘贴回 Agent 对话

Agent 协议中定义的 JSON 格式：

```json
{
  "decisions": [
    {
      "id": "col_001",
      "title": "栏目归属",
      "detail": "本条涉及工信部对 SDK 的通报，同时也涉及个人信息保护要求。",
      "type": "single",
      "options": [
        {"id": "a", "label": "行业监管动态（侧重执法通报）"},
        {"id": "b", "label": "政策法规发布（侧重合规要求）"}
      ]
    }
  ]
}
```

`type` 为 `single` 时渲染单选框，`multi` 时渲染复选框。卡片数量、选项数量、交互轮次全部由 Agent 根据具体政策动态生成，不做预设。

### 设计理念

大多数 AI 工具的设计思路是"替代人工判断"。workbench 的思路正相反：**AI 最有价值的时刻不是给最终答案，而是精准地识别出"这里需要人拍板"，并给人类提供足够清晰的选项来高效拍板。**

这种模式有几个好处：

- **决策可追溯**。每次选择都有记录，回头看周报时可以定位当时的判断依据。
- **降低认知负荷**。不用在对话中来回追问题，一个面板一次搞定。
- **保持对话干净**。Agent 对话本身只保留最终输出，决策过程在 workbench 里完成。

---

## 方法论

### 四栏目体系

| 栏目 | 关注内容 | 判断要点 |
|------|----------|----------|
| 行业监管动态 | 版号、APP/SDK 通报、专项行动、法院判例 | 区分"执法通报"和"合规趋势"；培训会只在出现明确检查方向时进周报 |
| 政策法规发布 | 法律、法规、规章、标准、征求意见稿、首单落地 | 区分"征求意见"和"正式稿"；首单落地必须回溯上位政策 |
| 产业政策指引 | 扶持、补贴、园区、营商环境、出海支持 | 必须确认公开发布，涉及补贴需提示合规复核 |
| 海外合规风向 | GDPR、DMA、DSA、PIPA、COPPA、AI 监管 | 中文公众号只能作为线索；不同法域不能直接套用到中国业务 |

### 来源层级

不是所有来源同等可信。skill 内建了 7 层来源优先级：

1. 官方文件原文
2. 官方答记者问、政策解读、新闻发布会实录
3. 主管部门转载的权威媒体报道
4. 地方政府或部门官网
5. 企业公告、平台规则页面
6. 权威新闻社
7. 媒体报道、律所文章和公众号文章

媒体报道只能提供线索。**核心事实必须回到官方原文**。

### 双版本输出

每条政策产出两个版本，各司其职：

- **长版参考**（500-1000 字）：帮内部读者理清来龙去脉。可含政策链条、横向比较、法条引用、行业影响面分析。
- **短版正式稿**（220-360 字）：只抓一个核心判断方向，直接可入周报。删旁支、删例外条款、删"需注意"式尾注。

短版不是长版的摘要。短版是对长版做减法——删到只剩一条推力。

### 文风限制

政策周报不是新闻稿，不是法律备忘录，不是 AI 总结。它有自己的语言。

**禁用句式**：`不是……而是……`、`值得注意的是`、`释放信号`、`监管趋严`、`持续加码`、`形成闭环`、`赋能`、`底层逻辑`

**罗列限制**：单句不超过 3 个顿号词组。

**抽象词限制**：少用"强化""推进""完善""加强""促进""压实""深化""常态化""机制化"。用也可以，但必须接具体事实。

这些规则不是拍脑袋来的。每一条都来自用户修改稿和原稿的逐句对比分析。详见 `content/style_rules.md` 和 `content/anti_patterns.md`。

### 内容迭代

这个 skill 有一个设计原则：**从用户的修改中学习**。

当用户提供了自己改过的更好版本，skill 会执行差异分析协议：
1. 对比原稿和用户稿，从 8 个维度分析改了什么、为什么更好
2. 抽取 5-10 条可迁移规则
3. 将优质稿写入 `examples/gold_cases/`，后续生成时自动参考相似案例

这意味着用得越久，skill 输出质量越高。它不是一个静态的 prompt，而是一套会进化的写作标准。

---

## Roadmap

- v1.1：可配置来源清单、定时扫描、增量去重和候选政策池
- 后续：事件触发、历史政策关联和来源健康检查

---

## License

MIT

---

## 适用场景

- 游戏/互联网公司的法务、合规、GR 岗位
- 咨询公司为游戏客户提供政策监测服务
- 关注中国互联网监管和海外合规动态的研究者
- 需要定期生成结构化政策周报的团队

如果你的业务不在游戏/互联网领域，SKILL.md 中的栏目逻辑、来源层级和文风限制仍然可以参考，但第 4 节的重点来源和业务场景需要替换为你的行业。
