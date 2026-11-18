import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/font_utils.dart';

/// The first-launch notice.
///
/// One rule: the dialog holds only what the user must read before using the
/// app — what it is, that it is no longer maintained, the terms line, and the
/// dismiss button as the last thing in the card. The author's referral is NOT
/// in the dialog: it is a separate sheet shown once after dismissal, so no
/// advertisement ever shares a container with the terms.
class NoticeDialog {
  static const String noticeVersion = 'v4-2026-11';

  static const String _legal =
      '本应用仅提供影视信息搜索服务，所有内容均来自第三方网站，'
      '不存储任何视频资源，不对内容的准确性与完整性作出保证。';

  static const String _disclaimerTitle = '关于更新';
  static const String _disclaimerBody =
      '这是我个人出于兴趣做的学习项目，能力有限，后续不再维护更新。'
      '遇到问题可以先自行尝试解决，仍未解决可在 GitHub 提 issue。';

  static const String _referralLabel = '作者推荐 · 非本应用内容';
  static const String _referralBody =
      'DuMate 是个 AI 办公工具，处理文档和杂事挺省时间。'
      '通过下面的链接注册，双方各得 2000 积分。';
  static const String _referralUrl = 'https://www.dumate.cn/?track=yqyl';
  static const String _referralCode = 'AXWJBV8';

  static const String _prefsKey = 'seenNoticeVersion';

  static Future<void> maybeShow(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_prefsKey) == noticeVersion) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    await _showNotice(context, prefs);
    if (context.mounted) {
      await _showReferral(context);
    }
  }

  static Future<void> _showNotice(
      BuildContext context, SharedPreferences prefs) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0xD9000000),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final surface = isDark ? const Color(0xFF1C1F26) : Colors.white;
        final bodyColor =
            isDark ? const Color(0xFFC3CAD5) : const Color(0xFF4B5563);
        final mutedColor =
            isDark ? const Color(0xFF8A93A0) : const Color(0xFF6B7280);
        final titleColor = isDark ? Colors.white : const Color(0xFF111827);

        return Dialog(
          backgroundColor: surface,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: mutedColor),
                      const SizedBox(width: 8),
                      Text(
                        '关于本应用',
                        style: FontUtils.poppins(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _legal,
                    style: FontUtils.poppins(
                      fontSize: 13,
                      height: 1.6,
                      color: bodyColor,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF2A2118)
                          : const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _disclaimerTitle,
                          style: FontUtils.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? const Color(0xFFFBBF24)
                                : const Color(0xFFB45309),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          _disclaimerBody,
                          style: FontUtils.poppins(
                            fontSize: 12.5,
                            height: 1.6,
                            color: bodyColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '使用即表示同意《用户协议》与《隐私政策》：'
                    '本应用不收集个人信息，播放记录与收藏仅保存在本机。',
                    style: FontUtils.poppins(
                      fontSize: 11,
                      height: 1.55,
                      color: mutedColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF15803D),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () async {
                        await prefs.setString(_prefsKey, noticeVersion);
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                      },
                      child: Text(
                        '我知道了',
                        style: FontUtils.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static Future<void> _showReferral(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final surface = isDark ? const Color(0xFF1C1F26) : Colors.white;
        final bodyColor =
            isDark ? const Color(0xFFC3CAD5) : const Color(0xFF4B5563);
        final mutedColor =
            isDark ? const Color(0xFF8A93A0) : const Color(0xFF6B7280);

        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _referralLabel,
                        style: FontUtils.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          color: mutedColor,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: mutedColor),
                      onPressed: () => Navigator.of(ctx).pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                Text(
                  _referralBody,
                  style: FontUtils.poppins(
                    fontSize: 12.5,
                    height: 1.55,
                    color: bodyColor,
                  ),
                ),
                const SizedBox(height: 12),
                _CopyRow(
                  label: '链接',
                  value: _referralUrl,
                  color: bodyColor,
                  muted: mutedColor,
                  isDark: isDark,
                ),
                const SizedBox(height: 6),
                _CopyRow(
                  label: '邀请码',
                  value: _referralCode,
                  color: bodyColor,
                  muted: mutedColor,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.label,
    required this.value,
    required this.color,
    required this.muted,
    required this.isDark,
  });

  final String label;
  final String value;
  final Color color;
  final Color muted;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已复制$label'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(24, 0, 24, 90),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                label,
                style: FontUtils.poppins(fontSize: 11, color: muted),
              ),
            ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  softWrap: false,
                  style: FontUtils.poppins(
                    fontSize: 11.5,
                    color: color,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF2E3440)
                    : const Color(0xFFE8EDF3),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, size: 11, color: muted),
                  const SizedBox(width: 3),
                  Text('复制',
                      style: FontUtils.poppins(fontSize: 10, color: muted)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
