## 纳西妲原格式单角色测试包 v0.2.0

这版修正了前一版的目录格式问题。ZIP 解压后导入根直接是：

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

验证结果：

- ZIP members: 121
- ZIP testzip: None
- ZIP roots: `live`, `originals`
- manifest: `manifest=2`, `api=2`
- export: `createNahidaBody`
- original parts: 36
- Minis 入口测试：`original-format entry OK · nahida · original`
- SHA-256: `99cdbd238fd1b8c52aad8475002be9cc4e55c92a0acc5eab22e958dfbbcfd2cf`
