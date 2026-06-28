# skills

我的 Agent Skills 中央仓库 —— 一边收集别人开源的 skill，一边写自己的 skill。
其他项目通过**软链接**引用这里的 skill，而不是复制，这样：

- **更新只需一次**：在这里 `git pull` 或 `npx skills add` 更新原件，所有引用的项目自动跟着变。
- **修复可以反哺**：在任意项目里改 skill，改的其实是这里的原件，可直接提交回开源项目。
- **节约上下文**：每个项目只链真正用得到的 skill，不污染全局。

## 目录结构

```
.agents/skills/<name>/     # skill 原件，每个一个目录
skills-lock.json           # 记录每个 skill 来自哪个 package（source）
PACKAGES.md                # 已安装的 package 一览（由脚本生成，勿手改）
scripts/link-skill.sh      # 把 skill / package 软链接进目标项目
scripts/gen-packages.sh    # 从 lockfile 重新生成 PACKAGES.md
scripts/prune-skills.sh    # 清理目标项目里失效（悬空）的 skill 软链接
scripts/prune-all.sh       # 对所有登记过的项目批量执行清理
scripts/doctor.sh          # 核对中央仓库目录与 lockfile 是否一致
links.txt                  # 登记链接过的项目（本地、gitignore，绝对路径）
```

> `link-skill.sh` 每次链接都会把目标项目的绝对路径登记进 `links.txt`，
> 供 `prune-all.sh` 批量清理。路径是本机专属的，所以这个文件不提交（已 gitignore）。

## 收集 skill

用 [skills.sh](https://www.skills.sh/) 把开源 skill 装到本仓库：

```bash
npx skills add <package>     # 例如 mattpocock/skills，会装入多个 skill
```

装完后 `.agents/skills/` 多出对应目录，`skills-lock.json` 记录来源。

随后跑一下生成器，把已安装 package 一览刷新到 [`PACKAGES.md`](PACKAGES.md)：

```bash
scripts/gen-packages.sh            # 重新生成 PACKAGES.md
scripts/gen-packages.sh --check    # 只校验是否最新（适合放进 CI / 提交前检查）
```

## 把 skill 装进某个项目

用 `scripts/link-skill.sh`，以软链接的形式安装，不复制文件：

```bash
scripts/link-skill.sh [-f] <目标项目路径> <skill或package> [更多...]
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
scripts/link-skill.sh ~/GitHub/demo mattpocock/skills

# 只装两个 skill
scripts/link-skill.sh ~/GitHub/demo tdd prototype

# 混着传，自动去重
scripts/link-skill.sh ~/GitHub/demo tdd mattpocock/skills
```

### 行为说明

- **幂等**：已正确链接的 skill 会跳过，不报错。
- **去重**：同一个 skill 在一次调用中只链一次。
- **入口链接**：`.claude/skills` 已是软链接则保持不动；若是真实目录则只告警、不覆盖。
- **冲突保护**：目标已存在指向别处的软链接时报错，加 `-f` 才替换；真实文件一律拒绝覆盖。
- **依赖**：展开 package 需要 `jq` 或 `python3`（任一即可）。

`-h` / `--help` 查看完整用法。

## package 更新后某些 skill 被删了怎么办

`npx skills update` 只更新现有 skill；upstream 删掉的 skill 用 `npx skills remove <skill>`
显式移除最稳妥。删除会牵连**两层**，分别处理：

**第一层 · 中央仓库**——更新/删除后核对目录与 lockfile 是否一致，再刷新一览：

```bash
scripts/doctor.sh            # 报告孤儿目录 / 缺失目录，给出修复建议
scripts/gen-packages.sh      # 核对通过后刷新 PACKAGES.md
```

- 孤儿目录（目录在、lock 没有）：`npx skills remove <name>` 或直接删目录。
- 缺失目录（lock 有、目录没了）：`npx skills experimental_install` 恢复。

**第二层 · 下游项目**——被删的 skill 在每个链过它的项目里会变成**悬空软链接**。
本仓库不记录谁链了什么，所以逐个项目清理：

```bash
scripts/prune-skills.sh -n <目标项目>   # 先 dry-run 看会删什么
scripts/prune-skills.sh    <目标项目>   # 删除悬空软链接
```

只删失效（broken）的软链接，有效链接和真实文件不动；若 `.agents/skills/` 因此清空，
顺带移除空目录和 `.claude/skills` 入口。

不想逐个项目跑，就用批量版——它遍历 `links.txt` 里所有登记过的项目：

```bash
scripts/prune-all.sh -n     # dry-run，看每个项目会删什么
scripts/prune-all.sh        # 逐个项目清理悬空软链接
```

已不在磁盘上的项目会自动从 `links.txt` 移除。
