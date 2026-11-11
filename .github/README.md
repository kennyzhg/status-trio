<p align="center">
  <img src="../Support/AppIcon.png" width="112" alt="Status Trio 应用图标">
</p>

<h1 align="center">Status Trio（个人修改版）</h1>

<p align="center"><strong>这是 Status Trio 的个人 fork，只供自己使用，不提供安装包，也不向原项目提交改动。</strong></p>

> [!IMPORTANT]
> **原项目：[lingyired/status-trio](https://github.com/lingyired/status-trio)**（作者 [@lingyired](https://github.com/lingyired)）
>
> - 项目主页与完整说明：<https://github.com/lingyired/status-trio>
> - 官方正式版下载：<https://github.com/lingyired/status-trio/releases/latest>
> - 在线预览图标效果：<https://statustrio.lingai.net/>
> - 问题反馈与功能建议：<https://github.com/lingyired/status-trio/issues>
>
> 想正常使用 Status Trio，请到原项目下载官方签名版本。本仓库的改动没有经过原作者审核，出现问题请不要到原项目反馈。

## 本仓库与原项目的关系

- 代码来自原项目，并**每天自动合并原项目的最新改动**，在此基础上叠加下面列出的个人修改。
- 所有个人修改都在分支 [`feat/topslot-power-when-plugged`](https://github.com/kennyzhg/status-trio/tree/feat/topslot-power-when-plugged)。
- 许可证沿用原项目的 [Apache-2.0](../LICENSE)，版权归原作者所有。
- 原项目的英文及多语言说明仍保留在仓库根目录（[README.md](../README.md)、[README.zh-Hans.md](../README.zh-Hans.md) 等），本页只介绍个人修改。

## 个人修改的功能

| # | 功能 | 设置位置 | 对应原项目 issue |
| --- | --- | --- | --- |
| 1 | 顶部槽位可选显示内容 | 设置 › 应用图标 › 顶部圆弧 › 顶部标记 › 顶部槽位 | [#274](https://github.com/lingyired/status-trio/issues/274) |
| 2 | 顶部槽位：接电显示功耗，用电池显示电量 | 同上 | — |
| 3 | ~~使用电池 / 接入电源分开设置刷新间隔~~（原项目 1.9.4 已自带，改用原项目实现） | 设置 › 通用 › 状态刷新间隔 | [#255](https://github.com/lingyired/status-trio/issues/255) |
| 4 | 状态面板天气（和风天气 3 天预报） | 设置 › 面板 › 天气 | — |
| 5 | 设置窗口的输入框可以复制粘贴 | — | — |
| 6 | 「每次打开回到主界面」补充测试 | 设置 › 面板 › 打开行为 | [#262](https://github.com/lingyired/status-trio/issues/262) |

### 1. 顶部槽位可选显示内容（#274）

组合图标的圆环顶部原本固定显示电池状态。没有内置电池的 Mac（如 Mac mini、Mac Studio）也会在这里显示一个没有意义的「100」。现在可以选择顶部槽位显示什么：

- **自动**（默认）：按原项目 1.9.5 新加的「顶部标记」显示——下方可以分别设置使用电池、充电中、连接电源但未充电时显示电量数字、闪电、插头或隐藏；没有电池的 Mac 显示「顶部指示图标」里选的装饰插头/闪电（也可选隐藏），圆环画满一圈。
- **电池**：和「自动」相同，从不显示假的 100。
- **隐藏**：始终隐藏，圆环画成完整的一圈。
- **功耗（瓦）**：显示整机当前功耗，取整数瓦（没有电池的 Mac 显示在整圈圆环的顶部缺口里）。读数过期时，有电池的 Mac 改回显示电池状态，没有电池的显示 `--`。

菜单栏和程序坞的图标使用同一套规则。原项目重构设置页后，这个选项移到了「应用图标 › 顶部圆弧」的「顶部标记」组，排在第一位。

### 2. 顶部槽位：接电显示功耗，用电池显示电量

顶部槽位新增的选项：

- 接入电源时显示整数瓦功耗；没有电池的 Mac 视为一直接电，所以一直显示功耗。
- 使用电池时显示原来的电量缺口。
- 只有接电时才读取功耗，用电池时不读取，不额外耗电。

### 3. 分开设置刷新间隔（#255）

原项目 1.9.4 自己加入了这个功能，而且用的是相同的设置项，所以个人版不再单独维护，改用原项目的实现：「使用电池」「接入电源」两个滑条，都是 5–60 秒、每档 1 秒，默认 15 秒，插拔电源后立即生效。原来存的值会沿用；之前设成 1–4 秒的会变成 5 秒。

### 4. 状态面板天气（和风天气）

状态面板可以加一个天气区块，显示今天、明天、后天三天的天气图标、描述和最高 / 最低气温，下方画出高温、低温两条趋势线。

**开启方法**

1. 到 [和风天气开发者控制台](https://console.qweather.com/) 创建项目，拿到自己账号的 **API Host** 和 **API Key**。
2. 打开「设置 › 面板」，勾选「天气」，在下面出现的设置组里填写 API Host 和 API Key，点「保存」。
3. 选择位置方式，需要时填写城市。

**说明**

- **默认关闭**，不开启时不会创建任何天气相关的组件，也不会发出网络请求。
- **API Key** 保存在系统钥匙串里，只放在请求头 `X-QW-Api-Key` 中发送，不会出现在网址里。
- **位置**有两种方式：
  - 「自动定位，失败时用城市」（默认）：只使用 App 已有的定位权限（原项目读取 Wi-Fi 名称时申请的），不会为天气单独弹窗；拿不到位置时使用设置里的城市。
  - 「只用城市」：完全不定位。
- 城市框可以填城市名搜索，也可以直接填「纬度,经度」（如 `39.92,116.41`），这样不需要城市搜索接口。
- 发送前坐标会约简到 0.01°（约 1 公里）。
- **请求频率**：没有定时器，后台也不刷新。只在打开面板、并且天气区块可见时获取；30 分钟内重复打开直接用上次的结果。面板右上角的刷新按钮可以立即重新获取。
- **用量估算**：每次获取发 1 个天气预报请求；自动定位时，第一次还会发 1 个城市搜索请求来取地名。正常使用每台 Mac 每天几十次，远低于和风天气每月 5 万次的免费额度。
- 获取失败时保留上一次的预报，并在下方提示原因；能区分 Key 错误、凭据安全限制（403）、额度用完等情况。
- 使用的接口：`/v7/weather/3d`、`/geo/v2/city/lookup`。详见 [docs/weather.md](../docs/weather.md)。

> [!NOTE]
> 和风天气官方推荐使用 JWT 认证。从 2027-01-01 起，使用 API Key 认证会限制每日请求量（具体数字官方尚未公布），到时可能需要改用 JWT。

### 5. 设置窗口可以复制粘贴

App 没有「编辑」菜单（原项目有意不加），所以设置窗口的输入框里 ⌘V 等快捷键都不起作用，填写天气的 API Key 时很不方便。现在设置窗口自己处理 ⌘X / ⌘C / ⌘V / ⌘A / ⌘Z / ⇧⌘Z（剪切、复制、粘贴、全选、撤销、重做），不改动原项目的菜单结构。

### 6. 「每次打开回到主界面」补充测试（#262）

这个功能原项目已经实现：在「设置 › 面板 › 打开行为」打开「每次打开回到主界面」后，每次点开状态面板都从主界面开始；默认关闭，保留上次查看的详情页。本仓库只补充了「默认关闭」和「保存后能读回」的测试。

## 自行编译

需要 Xcode，以及 Homebrew 安装的 `autoconf`、`automake`、`libtool`、`pkg-config`（编译 Helper 用）。

```bash
git clone -b feat/topslot-power-when-plugged https://github.com/kennyzhg/status-trio.git
cd status-trio
bash scripts/verify-local.sh full                              # 测试
UNIVERSAL_BUILD=1 bash scripts/build-app.sh release no-open    # 编译通用版
ditto dist/StatusTrio.app "/Applications/Status Trio.app"      # 先退出正在运行的 App
```

注意：

- 编译出的 App 是 Ad-hoc 签名，在其他 Mac 上首次打开会被系统拦下，需要到「系统设置 › 隐私与安全性」点「仍要打开」。
- 应用标识与官方版相同（`com.lingsmbp.StatusTrio`），两者共用设置，可以随时换回官方版。
- **请关闭 App 内的自动更新**，否则官方新版会覆盖自己编译的版本。

## 换回官方版

退出 App，删除 `/Applications/Status Trio.app`，再从 [原项目 Releases](https://github.com/lingyired/status-trio/releases/latest) 下载安装即可，设置会保留。
