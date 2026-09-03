# TWS Media Router

把 TWS 耳机上“音乐停止后基本没用”的上一首、下一首按钮，变成语音输入、发送和删除按钮。

## 它解决什么问题

很多 TWS 耳机自带 `Media_Next` 和 `Media_Prev` 控制键：播放音乐时它们用于切歌，但音乐暂停或停止后通常没有实际作用。

TWS Media Router 会判断播放器当前是否正在播放，并选择性接管这两个按键：

- `Playing`：完全放行，耳机继续正常控制上一首/下一首。
- `Idle`：接管媒体键，用于语音输入、发送和删除。
- `Unknown`：无法可靠判断时完全放行，避免误吞媒体键。

默认动作：

- 连续按 `Media_Next`：语音输入 → 语音输入 → Enter 发送，然后循环。
- 第一次按 `Media_Prev`：重置 Next 循环，保留已输入文本。
- 第二次按 `Media_Prev`：发送 `Ctrl+A`、Backspace，清空当前输入框。

脚本不会主动激活或聚焦任何窗口。使用时请让目标输入框保持焦点。

## 播放状态来源

- `netease`（默认）：读取网易云音乐 `cloudmusic.elog`。
- `gsmtc`：读取 Windows 当前 GSMTC 媒体会话。

无法读取、没有可靠状态或 detector 退出时都会返回 `Unknown`，媒体键保持原功能。

## 环境要求

- Windows 10 1809 或更高版本
- Node.js 20.6 或更高版本
- AutoHotkey v2

仓库不包含 Node.js 或 AutoHotkey 安装包。可以手动安装，也可以把下面的提示词交给目标环境中的 agent，让它完成克隆、依赖检查、构建和配置。

## 手动安装

```powershell
git clone https://github.com/qy4747/tws-media-router.git
cd tws-media-router
npm install
npm run build
```

然后运行：

```text
automation\tws-media-router.ahk
```

如果系统询问使用哪个 AutoHotkey 版本，请选择 v2。

## 配置

所有个性化设置都在 [`config/router.ini`](config/router.ini)：

- 播放状态来源：`netease` 或 `gsmtc`
- 轮询间隔
- 语音/转录软件的全局快捷键
- Next、Prev 动作序列
- 清空输入框使用的按键

当前默认语音快捷键是 `Left Ctrl + Left Alt + Up`。支持的动作名称为 `voice`、`enter`、`reset`、`clear`。

修改配置后退出并重新运行 AHK 脚本即可。修改 TypeScript 源码后还需要先运行 `npm run build`。

## 给 agent 的安装与适配提示词

复制下面这段文字到需要安装本项目的 Windows 环境中的 coding agent：

```text
请在这台 Windows 电脑上安装并配置 TWS Media Router：
https://github.com/qy4747/tws-media-router

要求：
1. 将仓库克隆到一个新的独立目录，不要覆盖其他项目。
2. 先阅读仓库中的 README.md、AGENTS.md 和 config/router.ini。
3. 检查 Node.js 20.6+ 与 AutoHotkey v2 是否可用；缺少时从官方来源安装。不要下载或使用 AutoHotkey v1。
4. 运行 npm install 和 npm test。
5. 根据这台电脑实际使用的播放器选择 player.provider：网易云音乐用 netease，其他支持系统媒体会话的播放器优先尝试 gsmtc。
6. 询问或检查我使用的语音转录软件全局快捷键，只修改 config/router.ini 中的 [voice] 配置，不把软件名称硬编码进核心代码。
7. 保持默认媒体键语义：Playing 时完全放行；Idle 时接管；Unknown 时必须 fail-open。不要添加窗口自动聚焦。
8. 默认 Next=voice,voice,enter，Prev=reset,clear；除非我明确要求，否则不要改变。
9. 完成后告诉我配置文件位置、启动方法和一套实机验证步骤。不要启动会抢占按键的 AHK 实例，等我确认后再启动。
```

如果未来需要用声音电平判断播放状态，可让 agent 参考 `router.ini` 中被注释的 `[audio_level]` 提示；当前版本不会执行这部分逻辑。

## 开源与第三方代码

项目使用 MIT License。网易云 elog 解码与检测思路参考 Coooookies/netease-cloudmusic-detector，详情见 [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)。
