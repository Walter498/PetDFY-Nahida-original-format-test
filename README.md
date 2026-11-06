# PetDFY Nahida original-format test package

这是一个按 `PetDFY-assets.zip` 原始目录格式整理的纳西妲单角色测试包。

## 导入根

解压 `PetDFY-Nahida-original-format-test.zip` 后，导入根直接包含：

```text
live/model.json
originals/figure.json
originals/figure.js
originals/model.json
originals/tex/
originals/feat/
originals/states/
originals/outfits/
originals/thumbs/
```

没有 `legacy/`、`character/` 或自定义的 `nahida-runtime-test-package/` 外层目录。

## 入口

```text
originals/figure.json
  entry: figure.js
  export: createNahidaBody
  model: model.json
```

`live/model.json` 使用原包的 `version/tables/models/upstreamCommit` 结构，并注册 `original`、`pajamas`、`sailor`、`blazer` 四个模型键；当前可直接测试的重点是纳西妲 `original`。

## 已验证

- ZIP `testzip=None`
- ZIP 根目录只有 `live/` 与 `originals/`
- `originals/figure.json`、`originals/model.json`、`originals/figure.js`、`live/model.json` 均存在
- 纳西妲 36 个原装部件 PNG/PNG 路径存在
- 入口在 Minis WebKit 中实际加载：`original-format entry OK · nahida · original`
- SHA-256：见 `VALIDATION.json`

## 测试页面

工作区内的入口验证页面：

`nahida-original-format-check.html`

## 说明

本仓库专门修正之前测试包的目录格式问题。纳西妲原装入口使用独立 figure renderer；三个新增服装的资源已按原目录路径纳入，但其完整动态形变仍属于后续整合任务。
