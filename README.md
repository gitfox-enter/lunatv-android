# LunaTV for Android · 手机端自包含移植

> **不用 NAS、不用服务器、不用 Docker —— 装个 APK，手机自己就是播放器。**

把 [LunaTV](https://github.com/MoonTechLab/LunaTV)（Next.js 影视聚合播放器）连服务端一起
塞进一个安卓 APK：手机本地跑一个 Next.js 服务，用 [Selene](https://github.com/MoonTechLab/Selene)
的 Flutter 界面直连它。装好即用，零部署。

---

## 为什么做这个

现有方案都得先有台机器：

| 方案 | 要求 |
|---|---|
| LunaTV 官方 | Docker / Vercel / Zeabur 部署，再配 Redis |
| Selene 官方客户端 | 先有跑着的 LunaTV 服务端 |
| **本项目** | **只要一台安卓手机** |

家里没有 NAS、不想买服务器、不想折腾 Docker 的话，这个 APK 就是为你准备的。

## 它是怎么工作的

```
┌─ APK (org.moontechlab.selene) ────────────────────────────┐
│   Selene 界面（Flutter，官方源码重建）                       │
│        │ 自动连接 + 自动登录（无需手输地址/密码）              │
│        ▼                                                   │
│   http://127.0.0.1:3000                                    │
│   libbun.so ← Bun 运行时（官方 Android 构建，NDK r27c）      │
│        │ exec                                               │
│        ▼                                                   │
│   assets/lunatv.zip ← Next.js standalone（18436 个文件）    │
│        首启解压到应用私有目录，之后秒开                       │
└────────────────────────────────────────────────────────────┘
```

- **Bun** 直接跑 Next.js 服务（比 Node 轻、冷启动 <400ms）
- **存储**用文件后端（本项目给 LunaTV 加的 `file` 模式，单个 JSON，无需 Redis）
- **界面**是 Selene 官方 Flutter 源码，不是套壳 WebView
- 服务绑 `0.0.0.0:3000`，**同 WiFi 的设备也能访问**（手机当迷你服务器）

## 特点

- ✅ **零部署**：一个 APK，装完就能看，不需要任何外部服务
- ✅ **零配置登录**：首启自动生成密码、自动登录，不用输地址和密码
- ✅ **带进度**：首启解压有进度条和阶段提示（不是黑屏干等）
- ✅ **局域网共享**：手机 IP:3000，平板/电脑/电视都能连
- ✅ **数据本地**：收藏、播放记录存在手机私有目录，不上传任何服务器
- ✅ **体积可控**：arm64 单架构，APK 约 116MB

## 快速开始

1. 去 [Releases](../../releases) 下载 **`lunatv-selene-*.apk`**
2. 手机上安装（HyperOS/ColorOS 可能拦截，需在开发者选项开「USB 安装」或关闭「纯净模式」）
3. 打开 App，等待首次解压（约 30-60 秒，有进度条）
4. 进首页 → 用管理后台配置片源（见下）

### 配置片源（必做）

App **不内置任何片源**，首次使用需自己添加：

```
手机浏览器打开：http://127.0.0.1:3000/admin
用户名：admin
密码：见 App 内「服务信息」页（每次安装随机生成，可在设置里查看/改端口）
```

同 WiFi 的其它设备：`http://<手机IP>:3000/admin`

## 环境要求

| 项 | 要求 |
|---|---|
| 架构 | **arm64-v8a**（绝大多数 2019 年后的手机） |
| Android | **8.0 (API 26)** 以上 |
| 存储 | 约 250MB 可用空间（116MB APK + 解压后 ~120MB） |
| 网络 | 首次启动无需联网；播放需要 |

> 不支持的：armeabi-v7a（32 位老机）、x86 模拟器

## 从源码构建

### 前置

- Flutter 3.35+、JDK 21、Android SDK (platform 35)
- Node 20 + pnpm（构建 LunaTV 用）

### 步骤

```bash
# 1. 克隆两个上游（本项目不放它们的大体积产物）
git clone https://github.com/MoonTechLab/LunaTV.git vendor/lunatv
git clone https://github.com/MoonTechLab/Selene.git selene-android

# 2. 给 LunaTV 打补丁（file 存储后端 + Bun middleware 兼容）
cd vendor/lunatv
git apply ../../patches/lunatv-file-storage.patch
cp ../../patches/file.db.ts src/lib/file.db.ts
pnpm install --registry=https://registry.npmmirror.com
NODE_ENV=production pnpm build

# 3. 打包成 assets/lunatv.zip（脚本自动重打 Bun middleware 补丁）
cd ../..
python scripts/make-standalone-zip.py

# 4. 放入 Bun 运行时（官方 Android 构建）
#    下载 https://github.com/oven-sh/bun/releases/download/bun-v1.4.2/bun-linux-aarch64-android.zip
unzip bun-linux-aarch64-android.zip
cp bun-linux-aarch64-android/bun selene-android/android/app/src/main/jniLibs/arm64-v8a/libbun.so

# 5. 构建 APK
cd selene-android
flutter build apk --release --target-platform android-arm64
```

### 构建时三个必须注意的坑

这些踩过，已在本仓库的配置里修好，自建时别改回去：

| 坑 | 症状 | 修复 |
|---|---|---|
| **R8 会把 `LunaGateway`/`LunaPrefs` 裁剪掉** | 服务永不启动，首启无限等待 | `isMinifyEnabled = false` |
| **`extractNativeLibs=false`** | `Bun 二进制缺失`，无法 exec | `packaging { jniLibs { useLegacyPackaging = true } }` |
| **Gradle 增量缓存跳过 Java 编译** | 改了代码但 APK 没变 | 构建前 `rm -rf android/app/build build` |

## 技术细节

### 对 LunaTV 的改动（全部在 `patches/`）

1. **`file` 存储后端**（`src/lib/file.db.ts`，新增）
   LunaTV 自带的 `localstorage` 模式只对网页有效，API 路由和原生客户端拿到的 `DbManager`
   是 `null`，收藏/播放记录全失败。新增单文件 JSON 后端：原子写、写队列串行化、
   损坏自动兜底，无需 Redis。
2. **middleware 跑 Node 运行时**（`src/middleware.ts`）
   Next 默认的 Edge 沙箱用 `runtime.context.addEventListener`，Bun 未实现 → 所有请求 500。
3. **沙箱补丁**（`scripts/make-standalone-zip.py` 自动应用）
   给 `next/dist/server/web/sandbox/context.js` 的两个 `addEventListener` 加 try/catch。

### Shell 层（`selene-android/android/app/src/main/java/`）

| 文件 | 职责 |
|---|---|
| `LunaGateway.java` | 解压 zip、spawn Bun、watchdog 重启、进度上报 |
| `LunaService.java` | 前台服务（specialUse）保活 |
| `LunaPrefs.java` | 端口、随机密码、解压标记 |
| `BootReceiver.java` | 开机自启 |
| `MainActivity.kt` | MethodChannel 桥（`getInfo`/`getProgress`/`setPort`/`lanAddress`/`openAdmin`） |

## 已知限制

- 首启解压约 30-60 秒（18436 个文件），之后秒开
- 数据在 App 私有目录，**卸载即失**
- 只支持 arm64
- HyperOS 等国产 ROM 需手动开「忽略电池优化」+ 自启动白名单，否则后台可能被杀
- 上游是影视聚合播放器，**播放源需自行配置**，本项目不提供任何片源

## 致谢与许可

本项目是**打包与适配工程**，站在这些项目肩上：

| 项目 | 作者 | 许可 |
|---|---|---|
| [LunaTV](https://github.com/MoonTechLab/LunaTV) | MoonTechLab | **CC BY-NC-SA 4.0** |
| [Selene](https://github.com/MoonTechLab/Selene) | MoonTechLab | 见其仓库 |
| [Bun](https://bun.sh) | Oven | MIT |
| [magpie-android](https://github.com/gllhack/magpie-android) | gllhack | 壳子架构参考（Bun 打包进 jniLibs 的思路） |

**本仓库同样以 CC BY-NC-SA 4.0 发布**：
- ✅ 可自由使用、修改、分发
- ❌ **禁止商业使用**
- 📝 必须署名原作者并保留本许可
- 🔄 衍生作品须用相同许可开源

## 免责声明

- 本项目**不提供、不托管、不分发任何影视内容或播放源**
- 仅作为 LunaTV 的技术移植示例，供学习与技术研究
- 使用者需自行确保所访问内容的合法性，并遵守当地法律法规
- 请勿用于商业用途，请勿公开传播或大规模推广