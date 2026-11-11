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

重连回归是最容易退化的点，改过 `KeyboardBatteryObserver` 后务必测。

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
