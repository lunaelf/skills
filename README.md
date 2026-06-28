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
scripts/link-skill.sh      # 把 skill / package 软链接进目标项目
```

## 收集 skill

用 [skills.sh](https://www.skills.sh/) 把开源 skill 装到本仓库：

```bash
npx skills add <package>     # 例如 mattpocock/skills，会装入多个 skill
```

装完后 `.agents/skills/` 多出对应目录，`skills-lock.json` 记录来源。

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
scripts/link-skill.sh ~/GitHub/baoyu-writing mattpocock/skills

# 只装两个 skill
scripts/link-skill.sh ~/GitHub/baoyu-writing tdd prototype

# 混着传，自动去重
scripts/link-skill.sh ~/GitHub/baoyu-writing tdd mattpocock/skills
```

### 行为说明

- **幂等**：已正确链接的 skill 会跳过，不报错。
- **去重**：同一个 skill 在一次调用中只链一次。
- **入口链接**：`.claude/skills` 已是软链接则保持不动；若是真实目录则只告警、不覆盖。
- **冲突保护**：目标已存在指向别处的软链接时报错，加 `-f` 才替换；真实文件一律拒绝覆盖。
- **依赖**：展开 package 需要 `jq` 或 `python3`（任一即可）。

`-h` / `--help` 查看完整用法。
