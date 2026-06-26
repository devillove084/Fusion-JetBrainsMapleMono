# Lilex Maple Mono

> 一个从 `Fusion-JetBrainsMapleMono` 分叉出来的个人构建版：用 **Lilex** 替换原来的 JetBrains Mono，并使用最新 **Maple Mono v7** 作为 CJK/Nerd Font 字形来源。

## 这是什么

**Lilex Maple Mono** 是一个融合字体：

- 拉丁字母、代码符号、连字风格来自 [Lilex](https://github.com/mishamyrt/Lilex)
- 中文、日文、Nerd Font 图标来自 [Maple Mono](https://github.com/subframe7536/maple-font) 的 `MapleMonoNormal-NF-CN`
- 默认输出字体族名为 `Lilex Maple Mono`
- 输出文件名 / PostScript 名使用 `LilexMapleMono-*`

这个 fork 和上游原项目的主要区别：

1. **不再使用 JetBrains Mono** 作为英文字形来源
2. **默认使用 Lilex 2.700**
3. **默认使用 Maple Mono v7.9** 的 release 产物，而不是从源码重新构建 Maple
4. **构建脚本改为本地脚本 `build_lilex_maple.sh`**
5. 原上游的 JetBrains 自动构建 workflow 已禁用，避免误发旧项目产物

## 推荐下载

高分屏 / 4K+ / macOS / Windows 缩放环境，推荐使用 unhinted 版：

```text
LilexMapleMono-NF-XX-XX-XX.zip
```

低分屏或觉得字形发虚时，可以试 hinted 版：

```text
LilexMapleMono-NF-XX-XX-HT.zip
```

文件名含义：

| 标记 | 含义 |
| --- | --- |
| `NF` | 包含 Nerd Font 图标 |
| `XX` | 占位符，表示没有启用该额外变体 |
| `NL` | No Ligatures，移除连字 |
| `HT` | Hinted，适合低分屏 |
| 最后一段 `XX` | Unhinted，适合高分屏 |

> 不建议同时安装 hinted 和 unhinted 两套同名字体，可能导致系统或编辑器选错 face。

## 编辑器配置示例

Zed：

```json
{
  "buffer_font_family": "Lilex Maple Mono",
  "buffer_font_features": {
    "calt": true,
    "zero": true,
    "ss01": true,
    "ss02": true,
    "ss03": true,
    "ss04": true,
    "cv01": true,
    "cv03": true,
    "cv10": true,
    "cv11": true,
    "cv13": true,
    "cv15": true
  }
}
```

如果觉得 `Regular 400` 偏轻，可以在编辑器里使用 `500` 字重：

```json
{
  "buffer_font_family": "Lilex Maple Mono",
  "buffer_font_weight": 500
}
```

## 本地构建

依赖：

- `fontforge`
- `fonttools` / `ttx`
- `gftools`
- `curl`
- `unzip`
- `zip`
- `ftcli` 可选，用于修正 monospace 元数据

快速构建：

```sh
./build_lilex_maple.sh
```

使用原 CI 风格的慢速 FontForge 优化流程：

```sh
./build_lilex_maple.sh --optimize
```

后台运行优化构建：

```sh
mkdir -p logs
nohup ./build_lilex_maple.sh --optimize > logs/build-lilex-maple-optimized.log 2>&1 &
echo $! > logs/build-lilex-maple-optimized.pid
```

查看进度：

```sh
tail -f logs/build-lilex-maple-optimized.log
```

只构建部分样式：

```sh
./build_lilex_maple.sh --styles Regular,Bold,Italic,BoldItalic
```

常用选项：

| 选项 | 说明 |
| --- | --- |
| `--optimize` | 使用原 CI 的慢速优化流程 |
| `--no-nerd` | 使用不带 Nerd Font 的 Maple CN |
| `--no-ligatures` | 移除连字 |
| `--styles LIST` | 只构建指定样式 |
| `--lilex-version VER` | 指定 Lilex release tag |
| `--maple-version VER` | 指定 Maple Mono release tag |
| `--no-proxy` | 不使用 GitHub 下载代理 |

脚本默认使用 `https://gh-proxy.org/` 加速下载 GitHub release zip。

## 字体特性

Lilex 提供的主要 OpenType features 包括：

```text
calt zero ss01 ss02 ss03 ss04 cv01 ... cv15
```

其中：

- `calt`：代码连字/上下文替换
- `zero` / `cv04` / `cv14`：不同的零字形，建议三选一
- `cv02` / `cv03`：不同的 `g` 字形，建议二选一
- `ss01`：恢复部分逻辑操作符箭头风味
- `ss02`：等号相关连字变体
- `ss03`：更细的反斜杠风格
- `ss04` / `cv15`：`#` 相关变体
- `cv13`：括号风格变体

## 致谢

- [Lilex](https://github.com/mishamyrt/Lilex)：拉丁、代码符号、连字与 OpenType 风格来源
- [Maple Mono](https://github.com/subframe7536/maple-font)：CJK、Nerd Font、中文/日文字形来源
- 原项目 [Fusion-JetBrainsMapleMono](https://github.com/SpaceTimee/Fusion-JetBrainsMapleMono)：字体融合流程参考

## 许可证

本项目及生成字体遵循 [SIL Open Font License 1.1](./OFL.txt)。
