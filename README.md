# skills

我的 Agent Skills 中央仓库 —— 一边收集别人开源的 skill，一边写自己的 skill。
其他项目通过**软链接**引用这里的 skill，而不是复制，这样：

- **更新只需一次**：在这里 `git pull` 或 `npx skills add` 更新原件，所有引用的项目自动跟着变。
- **修复可以反哺**：在任意项目里改 skill，改的其实是这里的原件，可直接提交回开源项目。
- **节约上下文**：每个项目只链真正用得到的 skill，不污染全局。

## 目录结构

```
.agents/skills/<name>/   # skill 原件，每个一个目录
skills-lock.json         # npx 装的：记录每个 skill 的 package（source）
authored.txt             # 自己写的 skill 名单（提交进仓库）
external.json            # GitHub 仓库来的外部 skill 清单（提交进仓库）
PACKAGES.md              # 三类 skill 一览（脚本生成，勿手改）
links.txt                # 链接过的项目（本地、gitignore，绝对路径）
scripts/
  check.sh               # 一键校验（doctor + gen --check），可做 pre-commit / CI
  test.sh                # 烟雾测试（跑在仓库副本上，不碰真实环境）
  install-hooks.sh       # 启用 git 钩子（设置 core.hooksPath 指向 hooks/）
  hooks/
    pre-commit           # 提交前跑 check.sh，不一致就拦下
  store/                 # 管中央仓库
    doctor.sh            # 核对目录与三类清单是否一致
    gen-packages.sh      # 重新生成 PACKAGES.md
    mark-authored.sh     # 标记自己写的 skill 进 authored.txt
    add-external.sh      # 引入 GitHub 仓库里的 skill（clone + 符号链接）
    sync-external.sh     # 按 external.json 还原 / 更新外部 skill
    remove-external.sh   # 移除外部 skill（删链接 + 出 external.json + 去 gitignore）
  project/               # 管链接进目标项目
    link-skill.sh        # 把 skill / package 软链接进目标项目
    unlink-skill.sh      # 移除已链接的 skill（link 的反操作）
    register.sh          # 手动把项目登记进 links.txt
    prune-skills.sh      # 清理目标项目里失效（悬空）的软链接
    prune-all.sh         # 对所有登记过的项目批量清理
  lib/                   # 被 source 的共享函数（非命令）
    lock.sh              # skills-lock.json / authored.txt 查询
    external.sh          # 外部 skill（解析 repo、读写 external.json、gitignore）
```

skill 分三类，各有来源记录：`npx skills add` 装的记在 `skills-lock.json`，
自己写的记在 `authored.txt`，从 GitHub 仓库引入的记在 `external.json`。

> 克隆后跑一次 `scripts/install-hooks.sh` 启用提交前校验：每次 `git commit` 会先跑
> `scripts/check.sh`，仓库不一致（孤儿目录、`PACKAGES.md` 过期等）就拦下提交。
> 需要跳过时用 `git commit --no-verify`。

> `link-skill.sh` 每次链接都会把目标项目的绝对路径登记进 `links.txt`，
> 供 `prune-all.sh` 批量清理。路径是本机专属的，所以这个文件不提交（已 gitignore）。
> 早先手动建过软链接、没经过 `link-skill.sh` 的项目，用 `scripts/project/register.sh <项目>` 补登。

## 收集 skill

用 [skills.sh](https://www.skills.sh/) 把开源 skill 装到本仓库：

```bash
npx skills add <package>     # 例如 mattpocock/skills，会装入多个 skill
```

装完后 `.agents/skills/` 多出对应目录，`skills-lock.json` 记录来源。

随后跑一下生成器，把已安装 package 一览刷新到 [`PACKAGES.md`](PACKAGES.md)：

```bash
scripts/store/gen-packages.sh            # 重新生成 PACKAGES.md
scripts/store/gen-packages.sh --check    # 只校验是否最新（适合放进 CI / 提交前检查）
```

## 自己写的 skill

自写 skill 同样放在 `.agents/skills/<name>/`，但**不在 `skills-lock.json` 里**（lock 只记录
`npx skills add` 装的）。链接和清理都照常工作，但有一处要注意：`doctor.sh` 区分不了
“你自己写的”和“删包后残留的”——两者都是“目录在、lock 没有”。

所以写完一个 skill，把它登记进 `authored.txt`：

```bash
scripts/store/mark-authored.sh <name>    # 标记为自写，doctor 不再误报、gen-packages 单列一节
```

`authored.txt` 会提交进仓库（它是仓库内容的一部分，和本机专属的 `links.txt` 不同）。

## 引入 GitHub 仓库里的 skill（不走 npx）

有些 skill 不在 npx 注册表里，只放在某个 GitHub 仓库。按“clone 到本地代码树 + 符号链接”的
方式引入：仓库按 `<root>/<host>/<owner>/<repo>` 的规则 clone（ghq / go 风格，root 默认
`~/Documents/code`，即 `~/Documents/code/github.com/<org>/<repo>`），再把其中的 skill 软链接进
`.agents/skills/<name>`。root 用环境变量 `SKILLS_CODE_ROOT` 覆盖。

```bash
scripts/store/add-external.sh <owner/repo 或 git URL> <仓库内 skill 路径> [name]
# 例（clone 到 ~/Documents/code/github.com/owner/cool-skills）：
scripts/store/add-external.sh owner/cool-skills packages/hello hello
```

它会 clone 仓库、建符号链接、把来源记进 `external.json`，并 gitignore 这个符号链接。

- **为什么 gitignore 链接、却提交 `external.json`**：链接指向本机绝对路径
  （`~/Documents/code/...`），提交了换台机器就失效；`external.json` 记录仓库地址 + 子路径，
  换机器靠它还原（和 `skills-lock.json` 思路一致）。
- **更新**：去 `$SKILLS_CODE_ROOT/<host>/<owner>/<repo>` 里 `git pull`，或一键
  `scripts/store/sync-external.sh`。
- **改了能反哺**：因为是符号链接，直接改的是 clone 里的原件，可在那边提交回上游。

换台机器、或链接 / clone 丢了，按清单还原：

```bash
scripts/store/sync-external.sh            # clone 缺失的、pull 更新、重建符号链接
scripts/store/sync-external.sh --no-pull  # 只还原，不拉更新
```

## 把 skill 装进某个项目

用 `scripts/project/link-skill.sh`，以软链接的形式安装，不复制文件：

```bash
scripts/project/link-skill.sh [-f] <目标项目路径> <skill或package> [更多...]
```

每个参数会被解析成一个或多个 skill：

- 如果是 `.agents/skills/` 里的某个 **skill 名** → 只链这一个；
- 否则当作 **package**（`skills-lock.json` 里的 `source`，如 `mattpocock/skills`）
  → 链接该 package 下的所有 skill，对应 `npx skills add <package>` 装多个 skill 的行为。

脚本会为每个 skill 建立：

```
<目标>/.agents/skills/<name>  ->  <本仓库>/.agents/skills/<name>
```

并确保 Claude Code 的入口软链接存在：

```
<目标>/.claude/skills         ->  ../.agents/skills
```

### 例子

```bash
# 整个 package 装进写作项目（展开成多个 skill）
scripts/project/link-skill.sh ~/Documents/code/github.com/me/demo mattpocock/skills

# 只装两个 skill
scripts/project/link-skill.sh ~/Documents/code/github.com/me/demo tdd prototype

# 混着传，自动去重
scripts/project/link-skill.sh ~/Documents/code/github.com/me/demo tdd mattpocock/skills
```

### 行为说明

- **幂等**：已正确链接的 skill 会跳过，不报错。
- **去重**：同一个 skill 在一次调用中只链一次。
- **入口链接**：`.claude/skills` 已是软链接则保持不动；若是真实目录则只告警、不覆盖。
- **冲突保护**：目标已存在指向别处的软链接时报错，加 `-f` 才替换；真实文件一律拒绝覆盖。
- **依赖**：展开 package 需要 `jq` 或 `python3`（任一即可）。

`-h` / `--help` 查看完整用法。

### 装成全局 skill（`-g`）

想让某个 skill 对所有项目可用，用 `-g`（不需要目标路径）。布局和 `npx skills add -g`
一致——规范位置在 `~/.agents/skills/`，再逐个软链接进 Claude Code 的全局目录：

```bash
scripts/project/link-skill.sh -g <skill或package> [更多...]
# 例：
scripts/project/link-skill.sh -g hv-analysis
```

为每个 skill 建立：

```
~/.agents/skills/<name>  ->  <本仓库>/.agents/skills/<name>
~/.claude/skills/<name>  ->  ../../.agents/skills/<name>
```

> 和项目模式不同：项目用单个入口链 `.claude/skills -> ../.agents/skills`，全局用**逐个**
> `~/.claude/skills/<name>` 链接（因为 `~/.claude/skills` 通常已是真实目录，混着 npx -g 装的
> skill）。已被 npx 装成真实目录的同名 skill 不会被覆盖。全局链接不登记进 `links.txt`。

### 移除已链接的 skill（`unlink-skill.sh`）

`link-skill.sh` 的反操作。`prune-skills.sh` 只删**失效**的链接；要删一个**仍然有效**的，用
`unlink-skill.sh`（参数同 link：skill 名或 package 名，`-g` 全局，`-n` dry-run）：

```bash
scripts/project/unlink-skill.sh <目标项目> <skill或package> [更多...]
scripts/project/unlink-skill.sh -g <skill或package> [更多...]   # 移除全局链接
```

只删**符号链接**（真实目录拒删）；项目里删空了顺带清掉入口链和空目录；全局只动**指向本仓库**
的链接。已经不在的就跳过（幂等）。

## package 更新后某些 skill 被删了怎么办

`npx skills update` 只更新现有 skill；upstream 删掉的 skill 用 `npx skills remove <skill>`
显式移除最稳妥。删除会牵连**两层**，分别处理：

**第一层 · 中央仓库**——更新/删除后核对目录与 lockfile 是否一致，再刷新一览：

```bash
scripts/store/doctor.sh            # 报告孤儿目录 / 缺失目录，给出修复建议
scripts/store/gen-packages.sh      # 核对通过后刷新 PACKAGES.md
```

- 孤儿目录（目录在、lock 没有）：`npx skills remove <name>` 或直接删目录。
- 缺失目录（lock 有、目录没了）：`npx skills experimental_install` 恢复。

**第二层 · 下游项目**——被删的 skill 在每个链过它的项目里会变成**悬空软链接**。
本仓库不记录谁链了什么，所以逐个项目清理：

```bash
scripts/project/prune-skills.sh -n <目标项目>   # 先 dry-run 看会删什么
scripts/project/prune-skills.sh    <目标项目>   # 删除悬空软链接
```

只删失效（broken）的软链接，有效链接和真实文件不动；若 `.agents/skills/` 因此清空，
顺带移除空目录和 `.claude/skills` 入口。

不想逐个项目跑，就用批量版——它遍历 `links.txt` 里所有登记过的项目：

```bash
scripts/project/prune-all.sh -n     # dry-run，看每个项目会删什么
scripts/project/prune-all.sh        # 逐个项目清理悬空软链接
```

已不在磁盘上的项目会自动从 `links.txt` 移除。

**全局链接**（`link-skill.sh -g` 装的）不在 `links.txt` 里。单独清，或给 `prune-all` 加 `-g`
一并清掉：

```bash
scripts/project/prune-skills.sh -g      # 只清全局：~/.agents/skills + ~/.claude/skills
scripts/project/prune-all.sh -g         # 所有登记项目 + 全局，一条命令清所有
```

只删**指向本仓库**且已失效的全局链接（连带配对的 `~/.claude/skills/<name>`）；指向别的
store、npx -g 装的真实目录、仍有效的链接都不动。
