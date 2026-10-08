# Milky Frog Stead

一个用 **Godot 4.7** 做的游戏项目。

## 快速开始

```bash
git clone https://gitee.com/hong-qizhi/milky_frog_stead.git
cd milky_frog_stead/milky-frog-stead
```

然后用 Godot 4.7 打开 `milky-frog-stead/project.godot`。

> 注意：**Godot 工程在 `milky-frog-stead/` 子目录里**，仓库根目录不是工程根目录。

## 参与开发

第一次参与请先完整阅读 👉 **[docs/协作指南.md](docs/协作指南.md)**

里面包含：获取仓库权限、安装环境、配置 Git 身份、配置推送凭据（令牌 / SSH）、
日常提交与 Pull Request 流程、常见报错排查，以及本仓库的特殊注意事项。

## 目录结构

```
.
├── docs/                  # 文档
├── .gitignore             # 忽略规则
└── milky-frog-stead/      # Godot 工程
    ├── project.godot
    ├── assets/            # 美术资源
    ├── scenes/            # 场景
    ├── scripts/           # 脚本
    └── data/              # 数据
```

## 约定

- `.godot/` 引擎缓存**不提交**（已在 `.gitignore` 中忽略）
- `*.import` 资源导入文件**必须提交**
- 所有人统一使用 **Godot 4.7**
- 不要对 `master` 执行 `git push -f`
