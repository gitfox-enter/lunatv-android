import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/user_data_service.dart';
import 'services/api_service.dart';
import 'services/theme_service.dart';
import 'services/douban_cache_service.dart';
import 'services/local_mode_storage_service.dart';
import 'services/local_server_service.dart';
import 'services/subscription_service.dart';
import 'dart:io' show Platform;
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:media_kit/media_kit.dart';
import 'package:bitsdojo_window/bitsdojo_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 media_kit (用于 PC 端播放器)
  MediaKit.ensureInitialized();

  // 初始化 macOS 窗口配置
  if (Platform.isMacOS) {
    await WindowManipulator.initialize(enableWindowDelegate: true);
    // 设置标题栏为透明，让菜单栏颜色跟随主题
    await WindowManipulator.makeTitlebarTransparent();
    await WindowManipulator.enableFullSizeContentView();
    // 隐藏标题栏中的 Title
    await WindowManipulator.hideTitle();
  }

  // 初始化豆瓣缓存服务
  final cacheService = DoubanCacheService();
  await cacheService.init();

  // 启动定期清理
  cacheService.startPeriodicCleanup();

  runApp(const SeleneApp());

  // 初始化 Windows 窗口配置
  if (Platform.isWindows) {
    doWhenWindowReady(() {
      final win = appWindow;
      const initialSize = Size(1024, 600);
      const minSize = Size(1024, 600);
      win.minSize = minSize;
      win.size = initialSize;
      win.alignment = Alignment.center;
      win.title = "Selene";
      win.show();
    });
  }
}

class SeleneApp extends StatelessWidget {
  const SeleneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ThemeService(),
      child: Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return MaterialApp(
            title: 'Selene',
            debugShowCheckedModeBanner: false,
            theme: themeService.lightTheme,
            darkTheme: themeService.darkTheme,
            themeMode: themeService.themeMode,
            home: const AppWrapper(),
            builder: (context, child) {
              // 为 Windows 平台改善字体渲染
              if (Platform.isWindows) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.0),
                  ),
                  child: child!,
                );
              }
              return child!;
            },
          );
        },
      ),
    );
  }
}

class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> {
  bool _isLoading = true;

  /// Set when the bundled Android server never came up: the app then offers a
  /// retry instead of falling back to the manual login screen.
  String? _error;

  /// Splash-screen progress: what the native shell reports it is doing, and
  /// how long the wait has lasted. The first launch unpacks ~18k files, which
  /// on a phone takes minutes — a bare spinner reads as a hang.
  String _stage = '正在启动本地服务…';
  Duration _waited = Duration.zero;
  Timer? _progressTimer;
  DateTime _startedAt = DateTime.now();

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  /// Polls the native unpacking state so the splash screen can name the step.
  void _startProgressPolling() {
    _progressTimer?.cancel();
    _startedAt = DateTime.now();
    _stage = '正在启动本地服务…';
    _progressTimer = Timer.periodic(const Duration(milliseconds: 600), (t) async {
      if (!mounted || !_isLoading) {
        t.cancel();
        return;
      }
      final waited = DateTime.now().difference(_startedAt);
      String next = _stage;
      try {
        final p = await LocalServerService.progress();
        final state = (p['state'] as String?) ?? '';
        final ready = (p['ready'] as bool?) ?? false;
        if (ready) {
          next = '本地服务已就绪，正在登录…';
        } else if (state.isNotEmpty) {
          next = state;
        } else if (waited.inSeconds > 3) {
          next = '正在启动本地服务…';
        }
      } catch (_) {
        // the channel is not up yet; keep the last text
      }
      if (mounted) {
        setState(() {
          _stage = next;
          _waited = waited;
        });
      }
    });
  }

void _checkLoginStatus() async {
    try {
      // The Android build carries its own LunaTV server: there is no address
      // to type and no password to remember.
      if (LocalServerService.isBundled) {
        await _connectToBundledServer();
        return;
      }

      // 检查是否是本地模式
      final isLocalMode = await UserDataService.getIsLocalMode();

      if (isLocalMode) {
        // 本地模式：尝试刷新订阅内容
        try {
          final subscriptionUrl =
              await LocalModeStorageService.getSubscriptionUrl();
          if (subscriptionUrl != null && subscriptionUrl.isNotEmpty) {
            final response = await http.get(Uri.parse(subscriptionUrl));
            if (response.statusCode == 200) {
              final content =
                  await SubscriptionService.parseSubscriptionContent(
                      response.body);
              if (content != null) {
                if (content.searchResources != null && content.searchResources!.isNotEmpty) {
                  await LocalModeStorageService.saveSearchSources(
                      content.searchResources!);
                }
                if (content.liveSources != null && content.liveSources!.isNotEmpty) {
                  await LocalModeStorageService.saveLiveSources(
                      content.liveSources!);
                }
              }
            }
          }
        } catch (e) {
          // 刷新失败也继续进入首页
        }

        // 无论刷新成功与否，都进入首页
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        }
      }

      // 检查是否有自动登录所需的数据
      final hasAutoLoginData = await UserDataService.hasAutoLoginData();

      if (!hasAutoLoginData) {
        // 如果没有自动登录数据，直接进入登录页
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      // 服务器模式：尝试自动登录
      final loginResult = await ApiService.autoLogin();

      if (mounted) {
        if (loginResult.success) {
          // 自动登录成功，进入首页
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (context) => const HomeScreen()),
          );
        } else {
          // 自动登录失败，进入登录页
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // 发生异常，进入登录页
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

/// Reads the address/password of the bundled server, waits for its port and
  /// signs in. Failing that it shows a retry card instead of the login form —
  /// the user has no credentials to type.
  Future<void> _connectToBundledServer() async {
    try {
      _startProgressPolling();
      final info = await LocalServerService.info();
      final url = (info['url'] as String?) ?? 'http://127.0.0.1:3000';
      await UserDataService.saveUserData(
        serverUrl: url,
        username: (info['username'] as String?) ?? 'admin',
        password: (info['password'] as String?) ?? '',
        cookies: '',
      );
      final ready = await LocalServerService.waitReady(url);
      if (!mounted) return;
      if (!ready) {
        setState(() {
          _isLoading = false;
          _error = '内置服务尚未就绪。首次启动要解压运行环境，约需 1-2 分钟；之后再打开会快很多。';
        });
        return;
      }
      final result = await ApiService.autoLogin();
      if (!mounted) return;
      if (result.success) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const HomeScreen()),
        );
      } else {
        setState(() {
          _isLoading = false;
          _error = '内置服务已启动，但自动登录被拒绝。';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = '启动内置服务失败：$e';
      });
    }
  }

  Widget _buildError() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 16),
              Text(_error ?? '未知错误', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _error = null;
                  });
                  _checkLoginStatus();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildError();
    }
    if (_isLoading) {
      return Consumer<ThemeService>(
        builder: (context, themeService, child) {
          return Scaffold(
            body: Container(
              decoration: BoxDecoration(
                color: themeService.isDarkMode
                    ? const Color(0xFF000000) // 深色模式纯黑色
                    : null,
                gradient: themeService.isDarkMode
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFe6f3fb),
                          Color(0xFFeaf3f7),
                          Color(0xFFf7f7f3),
                          Color(0xFFe9ecef),
                          Color(0xFFdbe3ea),
                          Color(0xFFd3dde6),
                        ],
                        stops: [0.0, 0.18, 0.38, 0.60, 0.80, 1.0],
                      ),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Indeterminate on purpose: the native side unpacks
                      // file-by-file and reports a text stage, not a ratio.
                      SizedBox(
                        width: 180,
                        child: LinearProgressIndicator(
                          minHeight: 4,
                          backgroundColor: themeService.isDarkMode
                              ? const Color(0xFF2A2A2A)
                              : const Color(0xFFD3DDE6),
                          valueColor: AlwaysStoppedAnimation<Color>(
                              themeService.isDarkMode
                                  ? const Color(0xFFffffff)
                                  : const Color(0xFF2c3e50)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _stage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: themeService.isDarkMode
                              ? const Color(0xFFffffff)
                              : const Color(0xFF2c3e50),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _waited.inSeconds < 3
                            ? '首次启动需要解压运行环境，请稍候'
                            : '已等待 ${_waited.inSeconds} 秒 · 首次启动需 1-3 分钟，之后会快很多',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: themeService.isDarkMode
                              ? const Color(0xFF9AA0AC)
                              : const Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return const LoginScreen();
  }
}
