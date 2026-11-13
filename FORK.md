# Fork 本地构建与安装手册

本文件只适用于 **当前这台机器上的自用 fork**，不属于上游流程。上游是 App Store 分发（开启 App Sandbox），本 fork 关闭了沙盒并自行构建分发，所以**这些改动不能提交给上游**。

内容涵盖：怎么构建、怎么安装、为什么这样签名、怎么验证、出问题怎么查。

---

## 0. 先决条件

| 项目 | 当前状态 |
|---|---|
| Xcode | `/Applications/Xcode.app`，版本 **27.2**（`xcode-select -p` 已指向它） |
| 签名证书 | 唯一可用身份：`Apple Development: ettingshausen@outlook.com (HXJVLST8RM)`；**注意 CN 里的团队号是错的**，证书真实 OU（TeamIdentifier）是 **`L2H4AP63QB`** |
| GitHub 网络 | 直连常超时，需要代理：`export https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897 all_proxy=socks5://127.0.0.1:7897` |
| Git remote | `origin` = 上游 `runcat-dev/RunCatNeo`；`fork` = `ettingshausen/RunCatNeo`（SSH 免密可用） |

代理只影响 `git fetch` / SwiftPM 拉依赖，本机构建本身不需要。每次 Bash 调用都是新 shell，**变量不会自动继承**，所以每条需要联网的命令都要在同一条命令里 export。

---

## 1. 一键构建 + 安装（推荐）

```bash
cd /Users/ettingshausen/develop/source/Github/RunCatNeo
./scripts/install-local.sh          # 默认 Release
./scripts/install-local.sh Debug    # 需要调试时
```

脚本做的事，逐条：

1. `cd` 到仓库根目录（脚本自身在 `scripts/` 下）；
2. `xcodebuild build`：`scheme RunCatNeo`、`destination platform=macOS,arch=arm64`、`-derivedDataPath /tmp/rnc-dd`；
3. **重新签名**：`codesign --force --deep --sign "Apple Development: …" --entitlements RunCatNeo/RunCatNeo.entitlements`；
4. `codesign --verify` 校验；
5. 杀掉正在运行的 `/Applications/RunCatNeo.app` 进程；
6. `rm -rf` 旧包 → `cp -R` 新包 → `xattr -cr` 清隔离属性 → `open` 启动；
7. 打印最终签名条款（designated requirement）。

签名身份可用 `RUNCAT_SIGN_IDENTITY` 覆盖；构建配置可用第一个参数指定。

### 三个容易踩的构建参数

- `-skipPackagePluginValidation`：**必须加**。LicenseList 带一个 BuildToolPlugin（生成许可证清单），无头/CI 环境下 Xcode 会因"插件未被信任"直接失败。
- `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`：让 xcodebuild **不做签名**，构建完成后由我们手动签。这样能精确控制签名身份与 entitlements。
- `-derivedDataPath /tmp/rnc-dd`：固定派生数据目录，便于定位 `.app` 产物，也避免污染 `~/Library/Developer/Xcode/DerivedData`。

---

## 2. 为什么必须用证书签名（不要改回 ad-hoc）

这是本项目踩得最深的一个坑：

- **ad-hoc 签名**（`codesign -s -`）的 designated requirement 是 `cdhash H"..."`；
- **macOS 的 TCC（输入监控）授权是按 designated requirement 记录的**；
- 结论：每重建一次二进制，cdhash 变化 → **之前授予的输入监控权限全部失效**，应用表现为"键盘电量读不到"，而且系统设置里那条记录还在，极具误导性。

换用 Apple Development 证书后，requirement 变成：

```
identifier "com.kyome.Neo.RunCat" and anchor apple generic and
certificate leaf[subject.CN] = "Apple Development: ettingshausen@outlook.com (HXJVLST8RM)" and …
```

它访问与二进制内容无关，**重建、重签名、重装都不影响授权**。

验证当前包的 requirement：

```bash
codesign -d --requirements - /Applications/RunCatNeo.app 2>&1 | tail -1
codesign -dv /Applications/RunCatNeo.app 2>&1 | grep TeamIdentifier    # 应为 L2H4AP63QB
```

只要输出里出现 `identifier "com.kyome.Neo.RunCat"` + 证书 CN，就是稳定签名；若只看到 `cdhash`，说明退化成了 ad-hoc，授权会在下次构建后失效。

### 团队号（OU）的坑

证书 CN 里写的 `(HXJVLST8RM)` **不是真实团队号**，真实 OU 是 `L2H4AP63QB`。

- 用 `codesign --sign "Apple Development: …"`（按 CN 字符串匹配）：**不受影响**，`scripts/install-local.sh` 走的就是这条路；
- 用 **xcodebuild 自己签名**（`CODE_SIGN_STYLE=Manual`）时：xcodebuild 按 **OU** 匹配证书，`DEVELOPMENT_TEAM=HXJVLST8RM` 会报 "No certificate for team … matching"；项目自带的 `DEVELOPMENT_TEAM=VJ5N2X84K8` 在纯 CLI 下会报 "No Account for Team"。可行写法：

```bash
xcodebuild -configuration Release -derivedDataPath /tmp/rnc-release \
  -skipPackagePluginValidation \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=L2H4AP63QB \
  CODE_SIGN_IDENTITY="Apple Development: ettingshausen@outlook.com (HXJVLST8RM)" build
```

这条路径依赖 Xcode 的钥匙串访问，**必须在非沙盒 shell 里跑**（沙盒会挡住 keychain）。它与 `install-local.sh` 的"先不签、后手工签"是两条等价路线，选一条即可。

> CI 产物（`build-app.yml`）仍是 ad-hoc 签名——那是为了下载即用，不涉及 TCC。**日常开发请用本地脚本安装**，才能保住输入监控授权。

---

## 3. 测试

改完代码先跑全量单测（约 208 个用例，Swift Testing）：

```bash
cd /Users/ettingshausen/develop/source/Github/RunCatNeo
xcodebuild test \
  -project RunCatNeo.xcodeproj \
  -scheme RunCatNeo \
  -testPlan UnitTest \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/rnc-dd \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

只需要看结论时：

```bash
xcodebuild test … > /tmp/xc-test.log 2>&1; echo "exit=$?"
grep -E "TEST .*(SUCCEEDED|FAILED)" /tmp/xc-test.log | tail -1
```

注意：`xcodebuild test` 的 `Executed N tests` 统计行常常是 0（Swift Testing 的结果不走 XCTest 计数），判断标准看 `** TEST SUCCEEDED **`。

---

## 4. 输入监控（TCC）授权流程

键盘电量功能依赖 **Input Monitoring**（`kTCCServiceListenEvent`）。首次或重置后按下列步骤：

1. 设置 → 指标 → 打开"启用键盘电量监控"（会自动打开隐私面板）；
2. 在 **系统设置 › 隐私与安全性 › 输入监控** 里勾选 **RunCat Neo**；
3. **退出并重新启动应用**（TCC 变更对已运行进程不生效）。

应用启动时若已启用但未授权，会主动调用 `IOHIDRequestAccess`，保证它出现在该列表中。

### 记录"卡住"了怎么办

症状：列表里明明勾着，应用仍然读不到电量。查日志：

```bash
/usr/bin/log show --last 5m --predicate 'subsystem == "com.apple.TCC"' --style compact 2>&1 \
  | grep -i "com.kyome.Neo.RunCat" | grep -iE "Failed to match|authValue"
```

- 出现 `Failed to match existing code requirement … kTCCServiceListenEvent` → 现存记录绑的是旧签名（通常是 ad-hoc 时代留下的），与新包不匹配；
- 处理：清掉该应用记录并重新授权：

```bash
tccutil reset ListenEvent com.kyome.Neo.RunCat
kill $(pgrep -f "/Applications/RunCatNeo.app/Contents/MacOS")
open /Applications/RunCatNeo.app     # 重新登记
```

然后回到第 4 节步骤 2–3。

一句话自检：**当前包是稳定签名 + 记录能匹配 + 授权后重启过进程**，三者齐备才会生效。

---

## 5. 安装后验证清单

| 功能 | 预期 |
|---|---|
| 风扇（Dashboard） | 网络区块下方出现风扇行：转速 + 相对最大值的进度条 |
| 风扇（指标栏） | 打开开关后出现转速读数；**转速为 0 时不显示**（设置弹窗有说明小字） |
| 键盘电量 | `⌨ 94%` 形式；未授权显示 `⌨ --`；断开连接则整项隐藏 |
| 重连回归 | 关键盘电源 → 项隐藏；重开 → **数秒内**恢复显示（先显示上次值，再跟随新采样） |
| Touch Bar | 见下方专节 |

重连回归是最容易退化的点，改过 `KeyboardBatteryObserver` 后务必测。

**键盘电量是「准静态」指标，不要每 3/5/10 秒去读：** K6 的电量在输入报告 3 里，由键盘**自己**决定何时发送；macOS HID 驱动只缓存最后一次收到的报告。实测（2026-11-13）：缓存值 69%、报告年龄约 9331 秒（即当天 11:58 之后没有再采样），`kIOHIDDeviceGetValueWithUpdate` 仍返回同一份缓存（值/年龄都不变），而 `IOHIDDeviceGetReport(type=Input, id=3)` 直接返回 `kIOReturnUnsupported`（输入报告主机无法主动索取）。结论：**应用无法强制键盘刷新电量**，显示的就是系统已有的最新样本；要拿到新值只能等键盘固件再发报告或断电重连（观察器已处理重连，并保留上次值）。因此采样节奏是 300 秒轮询 + 未读到时 3 秒重试；`scan()` 还加了「同一设备 5 秒内只读一次」的去重（一个物理键盘会暴露多个 HID entry、设备回调也会重复触发，否则一次启动会连续唤醒键盘几十次）。

### Touch Bar 指标栏

设置 →「指标」→ 三个页签：**系统指标**（菜单栏）｜**Touch Bar 指标**｜**Touch Bar 股票**。带 DFR 硬件的机器才有页签栏（检测见下）；没有 Touch Bar 的机器整页退化成「系统指标」一页。整页宽度固定 536pt，切页签不会缩放窗口。

| 显示模式 | 行为 | 适用 |
|---|---|---|
| 仅锚点图标 | Control Strip 里只有一个小仪表盘图标，点它才展开、点 `×` 收起 | 零配置、不抢任何应用的 Touch Bar（推荐给不想维护列表的人） |
| 常驻展开 | 全宽指标条一直挂着，无视排除列表 | 想随时一眼看到 |
| 智能让位 | 前台应用在**排除列表**里时自动收起，切走自动展开 | 既要常驻又要让位 |

**为什么需要排除列表（而不是自动识别）：** 实机验证过三条自动识别通道全部不可用——`CGWindowList` 里看不到 Touch Bar 表面（我们是呈现者时也没有任何窗口）、分布式通知全量监听无 TB 相关推送、`DFRFoundation` 里 174 个 TB 类没有可从外部进程查询“当前呈现者”的共享对象（状态在独立守护进程里，打通需逆向 XPC 协议）。所以判断依据只能是 bundle id 列表。

排除列表操作：「**排除当前前台应用**」一键加入（它取的是**最后一个非本应用的前台应用**，因为点按钮时设置窗口自己会变成前台）；「**添加应用…**」打开系统原生选择器，可搜索、可多选。

**实现要点与坑（改这块前务必读）：**

1. **私有 API**：`NSTouchBarItem.addSystemTrayItem:`（Control Strip 锚点）、`NSTouchBar.presentSystemModalTouchBar:systemTrayItemIdentifier:` / `minimizeSystemModalTouchBar:` / `dismissSystemModalTouchBar:`。10.13 的 `...FunctionBar` 命名已不存在，仅 10.14+ 的 `TouchBar` 命名可用。封装在 `DataSource/Dependencies/TouchBarClient.swift`，纯薄封装 + `responds(to:)` 守卫。
2. **硬件检测**：Apple Silicon 上 DFR 屏在 IORegistry 里叫 `lcddfr` / `dispdfr`（**不是 Intel 时代的 `AppleDFR` 类名**），`TouchBarClient` 里的 `TouchBarHardwareProbe` 用 `IOServiceNameMatching` 匹配。
3. **锚点不显示**：Control Strip 只在系统**见过该 bar 被 present 一次**后才渲染 tray item。仅锚点图标模式启动时从不 present，锚点会整个隐形——所以启动时做一次 `present → 下一 runloop minimize` 的预热（`primeTrayItemIfNeeded`）。
4. **有效宽度只有 621pt（最坑的一个）**：系统模态栏的宿主视图是 `NSTouchBarView`，实测帧宽 **621pt**（整条 1085pt，右侧 ~400pt 属于 Control Strip 和系统按钮），而我们的 item 容器可以比它宽——要 800pt 时容器真的拿到 800pt，但**超过 621pt 的部分直接被裁掉、且不会滚动**。所以 `TouchBarMetricsContainerView.barWidth` 必须**正好 621pt**，所有 `trailing` 约束才落在可见区。item 宽度只在插入那一刻被读一次，条内布局必须在创建时就定好。
5. **不能用 SwiftUI 画条内容**：`Image(size:)` 画布在 `NSHostingView` 里渲染成全透明；`NSHostingView` 的内容会整体漂到 28pt 条形之外（`ignoresSafeArea` 无效）；safe-area 内边距也会把内容推出去。现在整条是纯 AppKit：`NSStackView` + `NSTextField`（`lineBreakMode = .byClipping`）+ `NSImageView`（SF Symbol 固定 16×13）+ `NSButton` 或 `NSClickGestureRecognizer`。
6. **Touch Bar 不产生滚动事件**：实机用 `scrollWheel` 重写 + 进程级 `NSEvent.addLocalMonitorForEvents([.scrollWheel])` 双重埋点验证——横扫手势被 DFR 自己吃掉，**不会变成 App 的 `scrollWheel`**（日志里只有应用自己窗口的滚动，没有 Touch Bar 的）。所以不要指望“内容超宽就能滑动”：条内的一切都得放得下。股票用**两行单元格**（缩写 9pt 上、涨跌幅 9pt 下，同网速那对的思路），单只约 32–45pt，5 只最坏 ~257pt < 可用 ~270pt。
7. **重建一律推迟到下一 runloop**：在 `viewDidMoveToSuperview` / `layout()` 里改视图树会让 `NSTouchBarView _layoutSubtree` 抛 `EXC_BREAKPOINT`。`scheduleRebuildIfNeeded()` 只比对快照并 `DispatchQueue.main.async` 重建。约束也必须在视图进入层级之后再 `activate`，否则 `NSLayoutConstraint _setActive:` 报 "no common ancestor"。
8. **不要用外层 `NSStackView` 做整条布局**：gravity 分配会在 CPU 和内存之间留出巨大空隙。整条改用显式约束：优先组 `leading + 12`、分隔线 1×20pt、滚动容器从分隔线 `+10` 到 `trailing - 12`；分隔线没有尺寸就完全不渲染，容器没有高度就塌成 0。
9. **详情态不画分隔线**：点某只股票后整条归详情面板所有——分隔线和滚动容器**从视图树移除**（不只是隐藏，否则旧 frame 的线还留在屏幕上）；面板尾部放一个弹性 `NSView` 占位，内容才会左对齐铺开。
10. **指标内容**：Touch Bar 有**自己的一套指标开关**（`TouchBarConfiguration.visibleMetrics`，8 个标准指标 + 每个自定义指标源），与菜单栏指标条的 `MetricsBarConfiguration` **互不影响**——两个界面的显示集合可以完全不同。`MetricsBar.touchBarIndicators` 把可见集合折算成纯值 `TouchBarIndicator`（图标 + 文案），视图只做渲染（符合 LUCA「视图不含逻辑」）。老配置（没有 `visibleMetrics` 字段）解码为“全部显示”，避免升级后指标栏突然变空；Touch Bar 侧开关打开时会**自动补齐该指标的采集**（否则采集关着就永远没数据可显示）。
11. **菜单栏指标条与 Touch Bar 互不影响**：两个开关各自独立；关掉「在 Touch Bar 上显示指标栏」会移除锚点（不只是收起）。注意「系统指标」那一组是**监控开关**（决定是否采集数据），它仍会级联写菜单栏指标条的显示开关，但**不再影响 Touch Bar 的显示集合**。
12. **显示优先级**：`touchBarConfiguration.prioritizeStocks` 决定哪组贴左边、哪组进右侧容器。两组在 621pt 内一般都能放全，所以优先级更多是“超长时谁被裁”的顺序；条目多时靠堆叠压缩宽度（见下）。
13. **堆叠轮换**：设置里每个指标行 / 股票行右侧有一个「独立 / 堆叠 N / 新建堆叠」菜单，把同组条目放进一个固定槽位（系统指标与自定义指标算同组，股票单独一组，**不混放**）。槽位宽度取成员最大宽度（切换不抖动），**每 3 秒**轮换一个成员，0.3s 上滚动画（`TouchBarStackView`：两个 24pt band 同步上移一行，完成后在 `CATransaction` 关闭隐式动画重置坐标，终点画面完全一致所以不闪）。最多 4 个堆叠；一个条目只能属于一个堆叠；空堆叠自动删除（编号保持连续）。
14. **堆叠分组是纯函数**：`TouchBarSlotBuilder` 在 `MetricsBar.touchBarMetricSlots / touchBarStockSlots` 里把指示器折算成 slot（`stack:<uuid>` / `member:<key>`）。堆叠占据**首个可见成员原来的位置**，槽内顺序按配置里的成员顺序；成员暂时缺席（风扇 0 转、行情未到）自动跳过，只剩一个成员时按普通单元格静态渲染。容器视图的快照比对的是 slot 而不是裸指示器数组。
15. **轮换相位与重建**：`TouchBarMetricsContainerView` 用 `rotationPhases: [String: Int]` 按 slot id 记住当前成员，任何重建（数据刷新、配置变更）后从原位继续，不会跳回第一只。一次 3s tick 内同一 slot 只推进一次相位——领先组和滚动组各保存了一份 stack 视图，只有真正挂在 `self` 层级下的那份做动画（`isInHierarchy` 沿 superview 链判断）。展开详情时跳过轮换。计时器用 `.common` mode，与 0.5s 重建轮询一起在 `viewDidMoveToSuperview` 重建/失效。

### 股票（Touch Bar 股票页签）

数据源是**新浪财经** `https://hq.sinajs.cn/list=<codes>`：需要 `Referer: https://finance.sina.com.cn`，响应是 **GBK** 编码（用 `CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)` 转成 `String.Encoding`），批量返回多行 `var hq_str_<code>="..."`，未知代码返回空串。三个市场的字段布局不同（见 `StockQuoteParser` 顶部注释）：A 股用昨收自算涨跌幅，港股/美股直接取现成字段。

| 项 | 取值 |
|---|---|
| 上限 | 不限（靠堆叠在一行里轮换；条目多时超出 621pt 的部分会被裁掉，建议用堆叠压缩宽度） |
| 代码格式 | `sh600519` / `sz000001` / `rt_hk00700` / `gb_aapl`，也接受裸代码（`300253`→`sz300253`、`0700`→`rt_hk00700`、`AAPL`→`gb_aapl`），另有交易所前缀 `bj430047` |
| 添加校验 | 先用实时行情拉一次验证，成功才入库；缩写留空则用返回的中文名填充。**新浪返回空串（未上市/不存在的代码）报「无法识别的股票代码」，只有真正的请求失败才报「获取行情失败」** |
| 显示 | 缩写 + 涨跌幅，两行；**红涨绿跌**（国内惯例），平盘白色；可多条进同一堆叠轮换 |
| 详情 | 点按→ 名称、现价、涨跌额、今开/最高/最低 + 大号涨跌幅；再点返回 |
| 刷新 | 设置里可选 5 / 10 / 15 / 30 秒（默认 30），一次请求打包全部代码；**只在开市时段请求**（见下）；失败保留上一份行情 |
| 表面 | **仅 Touch Bar**，菜单栏指标条不显示股票 |

**盘前零价（踩过）：** 集合竞价（约 09:15–09:25）新浪把现价报成 `0.000`，A 股按 `(现价−昨收)/昨收` 会算出 **−100%**，五只全绿。解析器现在把 `≤0` 的价格/开/高/低一律当“缺失”：现价回落到昨收、涨跌幅记 0（白盘），开盘后才恢复正常。港股、美股盘前同理。

**只在开市时段请求（周末/午休/节假日不再打接口）：** `StockMarket` 按代码前缀分市场，每个市场用自己的本地时区与常规时段——A 股 09:30–11:30 / 13:00–15:00，港股 09:30–12:00 / 13:00–16:00，美股 09:30–16:00 ET；周末直接跳过，午休、盘前盘后也不请求。每个交易日开市后 2 分钟（美股 5 分钟）先用**指数报价**（`sh000001` / `rt_hkHSI` / `gb_dji`）探一次当天是否开市：指数从不因停牌而缺失，报价自带时间戳（A 股字段 30/31、港股 17/18、美股字段 3，均为北京时间/当地时间的字符串），换算到该市场本地日历日；不是今天就是节假日或休市，当天不再请求该市场（每个节假日最多 1 次探针请求）。`StockQuote.asOf` 就是这个时间戳；`StockPollPlanner` 是纯函数（按 `closedOn`/`probedOn` 状态决定本次可请求的代码与需要探针的市场），`StockService` 负责执行并把探针失败留到下一轮重试。配置里混有多个市场时逐市场判定，只请求开市的那部分代码。


改成 ad-hoc 签名跑 Debug 时，键盘电量会显示 `--`——不是 bug，是 TCC 授权绑在稳定签名上，见第 2、4 节。

---

## 6. 排障

### 应用崩溃 / 启动即退

```bash
ls -t ~/Library/Logs/DiagnosticReports/ | grep -i runcat | head -3
```

读取 `.ips` 里的关键字段（顶行是 JSON 元数据，第二行才是正文）：

```bash
python3 - <<'PY'
import json
p = "/Users/ettingshausen/Library/Logs/DiagnosticReports/<文件>.ips"
raw = open(p).read()
body = json.loads(raw.split("\n", 1)[1])
print(body.get("asi"), body.get("exception"), body.get("termination"))
for f in body["threads"][0]["frames"][:6]:
    print(" ", f.get("symbol"), f.get("symbolLocation"))
PY
```

经验：`asi` 里出现 `BUG IN CLIENT OF LIBPLATFORM: Trying to recursively lock an os_unfair_lock` = 在 `AllocatedUnfairLock.withLock` 闭包内部又拿了同一把锁（`AllocatedUnfairLock` 不可重入）。诊断代码尤其容易犯，写临时探针时把读取放到锁外。

### 应用日志

```bash
/usr/bin/log show --last 10m --predicate 'process == "RunCatNeo"' --style compact
```

**必须写绝对路径 `/usr/bin/log`**：zsh 把 `log` 当作数学内置函数，直接敲 `log` 会报 `too many arguments`。

### SwiftPM 依赖解析失败

症状：`no versions of 'swift-log' match the requirement 1.16.1` 之类，明明刚更新过依赖。

原因：`~/Library/Caches/org.swift.swiftpm/repositories/` 里有**残缺的 bare 仓库**（早期手工克隆留下的旧 tag）。

处理：删掉对应缓存再重跑（务必带代理）：

```bash
export https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897 all_proxy=socks5://127.0.0.1:7897
rm -rf ~/Library/Caches/org.swift.swiftpm/repositories/swift-log-* \
       ~/Library/Caches/org.swift.swiftpm/repositories/swift-collections-* \
       /tmp/rnc-dd
```

**第二个缓存位置**：`LocalPackage/.build/repositories/<name>-<hash>` 也会残留旧 tag，而且 `swift package resolve` 会优先读它。两者都删：

```bash
rm -rf LocalPackage/.build/repositories
```

### 想用 `swift test` 而不是 xcodebuild

裸 Swift CLI 下，LicenseList 的 `PrepareLicenseList` 插件会向上查找 `SourcePackages` 目录，找不到就抛 `SourcePackages not found`，**连不依赖该插件的 target 也无法规划构建**。补一个环境变量即可：

```bash
export PLL_SOURCE_PACKAGES_PATH=$(ls -d ~/Library/Developer/Xcode/DerivedData/RunCatNeo-*/SourcePackages | head -1)
cd LocalPackage && swift test
```

（该目录由至少成功跑过一次 xcodebuild 后才会存在。）

### 需要临时加诊断

推荐两种不改代码的方式：

1. **环境变量 + 打点**：代码里读 `ProcessInfo.processInfo.environment["…"]`，把状态写到 `/tmp/<name>.log`；
2. **给 GUI 应用注入环境变量**（`open` 不传环境变量）：

```bash
launchctl setenv RUNCAT_KB_STATE 1
kill $(pgrep -f "/Applications/RunCatNeo.app/Contents/MacOS"); sleep 1
open /Applications/RunCatNeo.app          # 应用继承 launchd 的环境变量
# 查完清理
launchctl unsetenv RUNCAT_KB_STATE
```

**诊断代码用完必须删干净**（连同 `launchctl unsetenv`），不要留在提交里。

---

## 7. CI 备选路径（GitHub Actions）

`.github/workflows/build-app.yml`：push 到 `feat/fan-metrics` 自动触发；跑测试 → Release 构建 → ad-hoc 签名 → 上传 artifact。

适合"没有本地 Xcode"或"只想下个包"的场景。下载：

```bash
token=$(printf "protocol=https\nhost=github.com\n\n" | git credential fill 2>/dev/null | grep '^password=' | cut -d= -f2)
artid=$(curl -s -H "Authorization: Bearer $token" \
  "https://api.github.com/repos/ettingshausen/RunCatNeo/actions/runs/<run-id>/artifacts" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['artifacts'][0]['id'])")
curl -sL -H "Authorization: Bearer $token" \
  -o artifact.zip "https://api.github.com/repos/ettingshausen/RunCatNeo/actions/artifacts/$artid/zip"
```

注意 artifact 是**双层 zip**（GitHub 外层 + workflow 内层 `RunCatNeo-<sha>.zip`），要解两次。

已知问题：macOS runner 偶发"job 被取消、日志为空"（runner 侧故障，非代码问题）。重跑即可：

```bash
curl -s -X POST -H "Authorization: Bearer $token" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/ettingshausen/RunCatNeo/actions/runs/<run-id>/rerun
```

---

## 8. 与上游同步

```bash
export https_proxy=http://127.0.0.1:7897 http_proxy=http://127.0.0.1:7897 all_proxy=socks5://127.0.0.1:7897

git fetch origin
git checkout main && git merge --ff-only origin/main && git push fork main
git checkout feat/fan-metrics
git merge origin/main          # 或走 PR：main → feat/fan-metrics
```

历史上唯一冲突点是 `MetricsSettings.swift`（上游把错误弹窗移交给 `CustomMetricsSettings`，删掉了 `.errorOccurred` 分支，与本分支新增的风扇 case 相邻）。解决原则：**保留本 fork 新增的 case，跟随上游删除 error 分支**。

合并后重新跑第 3 节测试，再走第 1 节安装。

---

## 9. 关键文件索引

| 目的 | 路径 |
|---|---|
| 一键构建安装 | `scripts/install-local.sh` |
| 签名权限 | `RunCatNeo/RunCatNeo.entitlements`（`device.hid` + 书签权限，沙盒已关闭） |
| 风扇采集 | `LocalPackage/Sources/DataSource/Dependencies/SMCClient.swift`、`Model/Services/SystemMetricsService.swift` |
| 键盘电量采集 | `DataSource/Services/KeyboardBatteryObserver.swift`、`Sources/HIDShim/`（C shim）、`Model/Services/KeyboardBatteryService.swift` |
| AI Token 用量采集 | `DataSource/Entities/AITokenUsage/`、`Model/Services/AITokenUsage{Service,Scanner,Parser}.swift`、`DataSource/Dependencies/{FileSlice,SQLite}Client.swift`（15 秒固定刷新） |
| 指标栏绘制 | `UserInterface/Views/MetricsBar/MetricsBarView.swift` |
| Touch Bar 指标栏 | `Model/Services/TouchBarMetricsService.swift`、`UserInterface/Views/MetricsBar/TouchBarMetricsContainerView.swift`（纯 AppKit，621pt）、`TouchBarStackView.swift`（堆叠上滚） |
| Touch Bar 堆叠 | `DataSource/Entities/Metrics/TouchBar{Stack,Slot}.swift`、`Model/Services/TouchBarSlotBuilder.swift`、`Model/Stores/MetricsSettings.swift`（每行分配菜单） |
| Touch Bar 股票 | `DataSource/Dependencies/StockClient.swift`、`DataSource/Entities/Stocks/`（含 `StockMarket.swift` 时段）、`Model/Services/{StockQuoteParser,StockService,StockPollPlanner}.swift`、`Model/Stores/StockEditor.swift` |
| 本地化 | `UserInterface/Resources/Localizable.xcstrings`（新增文案需补全 10 种语言） |
| CI | `.github/workflows/build-app.yml` |

---

## 10. 一页速查

```bash
# 构建 + 安装
cd /Users/ettingshausen/develop/source/Github/RunCatNeo && ./scripts/install-local.sh

# 测试
xcodebuild test -project RunCatNeo.xcodeproj -scheme RunCatNeo -testPlan UnitTest \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/rnc-dd \
  -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO

# 确认签名是稳定的（不是 cdhash）
codesign -d --requirements - /Applications/RunCatNeo.app 2>&1 | tail -1

# TCC 卡住时
tccutil reset ListenEvent com.kyome.Neo.RunCat && open /Applications/RunCatNeo.app

# 查 TCC 判定
/usr/bin/log show --last 5m --predicate 'subsystem == "com.apple.TCC"' --style compact 2>&1 | grep -i runcat

# 推送 fork（参数化构建）
git push fork feat/fan-metrics
```
