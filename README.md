# 悬浮待办 · Floating Todo

一个常驻桌面的轻量待办小组件。它通过半透明、始终置顶的浮窗展示今天、明天、后天的短期待办，适合放在屏幕角落随时查看。

> 隐私说明：本项目 README 和演示图片仅使用通用占位示例，不包含真实会议、客户、链接、账号或个人工作内容。

<div align="center">
  <img src="docs/images/banner.svg" alt="Floating Todo banner" width="100%" />
</div>

## 功能

- 今天 / 明天 / 后天三个待办列表。
- 快速新增、完成、删除、编辑待办。
- 每条待办可添加描述，描述中的网址会自动识别为可点击链接。
- 支持每天常驻待办，跨天自动重置为未完成。
- 跨天自动滚动，未完成事项会顺延。
- 一键清除已完成事项。
- 始终置顶、半透明、可拖拽缩放。
- 支持自定义背景色，以及跟随系统 / 浅色 / 深色外观。
- 支持全局备忘录，本地自动保存。
- 数据保存在本机，不需要登录，不连接网络服务。

<div align="center">
  <img src="docs/images/widget.svg" alt="Floating Todo interface preview" width="340" />
</div>

## 下载安装

前往 [Releases](../../releases) 下载对应平台安装包。

| 平台 | 安装包 | 说明 |
| --- | --- | --- |
| macOS Apple 芯片 | `floating-todo_x.x.x_aarch64.dmg` | M 系列芯片 |
| macOS Intel | `floating-todo_x.x.x_x64.dmg` | Intel 芯片 |
| Windows | `floating-todo_x.x.x_x64-setup.exe` | Windows 10/11 64 位 |

macOS 支持 11+，Windows 支持 10/11。

## 首次打开提示

当前安装包未包含付费代码签名证书，首次打开时可能会被系统安全提示拦截。

### macOS

如果提示无法验证开发者或应用已损坏，可以选择以下方式之一：

- 在「应用程序」中找到「悬浮待办」，右键选择「打开」，再确认打开。
- 在「系统设置」的「隐私与安全性」中找到拦截记录，选择仍要打开。
- 如果提示应用已损坏，可在终端执行：

```bash
sudo xattr -dr com.apple.quarantine "/Applications/悬浮待办.app"
```

### Windows

如果出现 SmartScreen 提示，点击「更多信息」，再选择「仍要运行」。

## 从源码构建

需要先安装 Node.js 18+ 和 Rust。

```bash
git clone <repository-url>
cd floating-todo
npm install
npm run dev
npm run build
```

## 技术栈

- Tauri 2
- Rust
- 原生 HTML / CSS / JavaScript
- 本地 `localStorage` 持久化

项目结构：

```text
floating-todo/
├─ src/                  # 前端界面与交互
├─ src-tauri/            # Tauri / Rust 后端与打包配置
├─ docs/images/          # README 演示图片
└─ legacy-macos-swift/   # 早期 Swift 版本存档
```

## Roadmap

- macOS 公证 / Windows 代码签名。
- 本地提醒通知。
- 全局快捷键。
- 可选数据同步。
- 点击穿透。

## License

[MIT](LICENSE)
