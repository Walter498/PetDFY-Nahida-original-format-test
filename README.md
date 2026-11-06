# PetDFY Nahida root-entry original-format test package

当前发布版本为 **v0.3.0**。它在保留原始 `originals/` 与 `live/` 资源层的同时，补齐了宿主从 ZIP 根直接加载所需的根入口。

## 导入根

解压 `PetDFY-Nahida-root-format-test.zip` 后，宿主导入根直接包含：

```text
figure.json
figure.js
model.json
live/model.json
originals/figure.json
originals/model.json
originals/tex/
originals/feat/
characters/nahida/figure.json
characters/nahida/figure.js
characters/nahida/model.json
characters/nahida/live/model.json
characters/nahida/outfits/original/
```

根入口是 `figure.json`；`originals/` 与 `live/` 是保留的原始资源层。

## 入口

```text
figure.json
  entry: figure.js
  export: createNahidaBody
  model: model.json

characters/nahida/figure.json
  entry: figure.js
  export: createNahidaBody
  model: model.json
```

`live/model.json` 保留原包的 `version/tables/models/upstreamCommit` 结构；纳西妲独立角色的 `characters/nahida/live/model.json` 注册 `original`。本 v0.3 测试包只把 `original` 标记为可直接测试，避免把未完成服装动态形变伪装成 ready。

## 已验证

- ZIP `testzip=None`
- ZIP 根目录包含 `figure.json`、`figure.js`、`model.json`、`live/`、`originals/`、`characters/`
- 根 `figure.json`、根 `figure.js`、根 `model.json` 均存在
- `characters/nahida/` 独立角色入口和 `live/model.json` 均存在
- 纳西妲 36 个原装部件、6 个状态 PNG 存在
- 入口在 Minis WebKit 中实际加载：`root-entry OK · nahida · original`
- v0.3.0 ZIP SHA-256：见 `VALIDATION.json`

## 测试页面

工作区内的入口验证页面：

`nahida-root-format-check.html`

## 说明

本仓库专门修正之前测试包的目录格式问题。纳西妲原装入口使用独立 figure renderer；三个新增服装的资源已按原目录路径纳入，但其完整动态形变仍属于后续整合任务。
