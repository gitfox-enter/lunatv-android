import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/local_server_service.dart';

/// Everything about the server that ships inside the APK: where it listens, the
/// address other devices on the same Wi-Fi can use, the admin console entry and
/// the port.
class LocalServerScreen extends StatefulWidget {
  const LocalServerScreen({super.key});

  @override
  State<LocalServerScreen> createState() => _LocalServerScreenState();
}

class _LocalServerScreenState extends State<LocalServerScreen> {
  final TextEditingController _portController = TextEditingController();
  Map<String, dynamic> _info = const {};
  String? _lanIp;
  String? _notice;
  bool _savingPort = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!LocalServerService.isBundled) {
      return;
    }
    final info = await LocalServerService.info();
    final lan = await LocalServerService.lanAddress();
    if (!mounted) return;
    setState(() {
      _info = info;
      _lanIp = lan;
      _portController.text = '${info['port'] ?? 3000}';
    });
  }

  Future<void> _applyPort() async {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port < 1024 || port > 65535) {
      setState(() => _notice = '端口需要是 1024-65535 之间的数字');
      return;
    }
    setState(() {
      _savingPort = true;
      _notice = null;
    });
    final applied = await LocalServerService.setPort(port);
    if (!mounted) return;
    setState(() {
      _savingPort = false;
      _notice = applied == null
          ? '端口修改失败'
          : '端口已改为 $applied，服务正在重启，稍后回到首页重试即可';
    });
    await _load();
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _notice = '已复制：$text');
  }

  @override
  Widget build(BuildContext context) {
    final port = _info['port'] ?? 3000;
    final lanUrl = _lanIp == null ? null : 'http://$_lanIp:$port';

    return Scaffold(
      appBar: AppBar(title: const Text('本地服务')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('内置服务',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('本机地址'),
            subtitle: Text('${_info['url'] ?? 'http://127.0.0.1:$port'}'),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () =>
                  _copy('${_info['url'] ?? 'http://127.0.0.1:$port'}'),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('局域网地址'),
            subtitle: Text(lanUrl ?? '未连接 Wi-Fi'),
            trailing: lanUrl == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    onPressed: () => _copy(lanUrl),
                  ),
          ),
          const SizedBox(height: 8),
          const Text('同一 Wi-Fi 下的手机、平板或电脑，用浏览器打开上面的局域网地址即可，登录账号 admin、密码见下。',
              style: TextStyle(fontSize: 12, color: Colors.grey)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('登录密码'),
            subtitle: Text('${_info['password'] ?? ''}'),
            trailing: IconButton(
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () => _copy('${_info['password'] ?? ''}'),
            ),
          ),
          const Divider(height: 32),
          const Text('片源与站点配置',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('打开管理后台'),
            subtitle: const Text('在浏览器里添加资源站、修改站点设置'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () async {
              final url = await LocalServerService.openAdmin();
              if (!mounted) return;
              setState(() => _notice = url == null ? '打开失败' : '已打开 $url');
            },
          ),
          const Divider(height: 32),
          const Text('端口',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '服务端口',
                    helperText: '修改后会重启内置服务',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _savingPort ? null : _applyPort,
                child: Text(_savingPort ? '应用中' : '应用'),
              ),
            ],
          ),
          if (_notice != null) ...[
            const SizedBox(height: 16),
            Text(_notice!, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}