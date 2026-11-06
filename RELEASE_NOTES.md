## 纳西妲根入口原格式测试包 v0.3.0

这版补齐了宿主从 ZIP 根直接加载所需的入口层，同时保留原始 `originals/` 和 `live/` 资源路径。

解压后导入根：

```text
figure.json
figure.js
model.json
live/model.json
originals/figure.json
originals/model.json
characters/nahida/figure.json
characters/nahida/figure.js
characters/nahida/model.json
characters/nahida/live/model.json
characters/nahida/outfits/original/
```

验证结果：

- ZIP members: 610
- ZIP testzip: None
- ZIP roots: `figure.json`, `figure.js`, `model.json`, `live`, `originals`, `characters`
- root export: `createNahidaBody`
- character export: `createNahidaBody`
- original parts: 36
- Minis 入口测试：`root-entry OK · nahida · original`
- SHA-256: `9dcbe0ef434a74d1961f5b248746bd06ab2b2d8cdc01d1f5a31691d0cee194a0`

本版本只把纳西妲 `original` 注册为可直接测试服装。
