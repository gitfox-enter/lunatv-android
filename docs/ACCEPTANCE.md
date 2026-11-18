# 验收报告 · lunatv-selene 4.0.0

验收时间：2026-11-18 10:35 (GMT+8)
设备：REDMI Turbo 4 Pro / `25053RT47C` / HyperOS 2 / Android 15 / API 35 / arm64-v8a
产物：`dist/lunatv-selene-4.0.0.apk`（115.7MB，debug key 签名）
连接：无线 ADB `192.168.137.231:39183`

## 结论：通过

Selene 界面 + 内嵌 LunaTV 服务在真机上完整跑通，首启自动解压、自动起服务、自动登录、
首页正常渲染（豆瓣热门电影/剧集海报）、收藏与播放记录落盘正常。

## 逐项验证

| 项 | 方法 | 结果 |
|---|---|---|
| 首启解压 | logcat `LunaGateway` | ✅ `LunaTV 1.6.8 解压完成 -> files/lunatv`（约 30s） |
| Bun 启动 | logcat + 进程 | ✅ `Ready in 392ms`，进程 `u0_a717 libbun.so` |
| 服务监听 | 设备内 curl | ✅ `HTTP 200` on `127.0.0.1:3000/api/server-config` |
| 存储后端 | server-config | ✅ `{"StorageType":"file","Version":"100.1.3"}` |
| owner 登录 | POST /api/login | ✅ 200，cookie `role=owner` |
| 首页 | GET /（登录态） | ✅ 200，40819B |
| 收藏写入/读回 | POST+GET /api/favorites | ✅ 200 / 200，中文无损 |
| 播放记录 | POST+GET /api/playrecords | ✅ 200 / 200，`index:4` 落盘 |
| 界面 | 截图 `dist/diag/v4-screen.png` | ✅ 首页渲染正常（热门电影/剧集海报） |

## 验收发现并修复的致命 Bug（接手 AI 未发现）

1. **R8 裁剪掉 LunaGateway/LunaPrefs**
   `isMinifyEnabled=true` 时 R8 判定这两个类（只经 Service/MethodChannel 引用）无用直接删除，
   `LunaService.start()` 调用不存在的类 → 服务永不启动 → 首启无限等待。
   → 关闭 release 的 `isMinifyEnabled` / `isShrinkResources`。

2. **Gradle 增量缓存不重编 Java 源**
   改完 Java 后构建仅 7 秒（全缓存命中），APK 里仍是旧 dex（无 Luna 类）。
   → 必须 `rm -rf android/app/build build` 后全量构建。

3. **`extractNativeLibs=false` 导致 Bun 无法 exec**
   AGP 默认把 .so 留在 APK 内不解压，而 `nativeLibraryDir` 里必须有实体文件才能 exec。
   运行时报 `Bun 二进制缺失`。
   → `packaging { jniLibs { useLegacyPackaging = true } }`（APK 也因此降到 115.7MB）。

4. **middleware 沙箱补丁丢失（首页 500）**
   重装 node_modules 后 Next 的 Bun 补丁没了，`runtime.context.addEventListener` 报错。
   → `scripts/make-standalone-zip.py` 打包时自动重打（固化，不再靠手工）。

5. **首启无进度提示**
   → Splash 加进度条 + 阶段文字（准备/解压 XX MB/启动服务/登录）+ 已用秒数，
     native 经 `getProgress` MethodChannel 上报。

## 已知限制

- 首启约 30-60 秒（解压 18436 文件），之后秒开
- 数据存 App 私有目录 `files/lunatv-data/storage.json`，卸载即失
- 片源不内置，需在管理后台（http://127.0.0.1:3000/admin）自行添加
- 服务绑 `0.0.0.0:3000`，局域网可访问（`owner` 密码保护）
- APK 为 self-use 构建：debuggable + debug key 签名
