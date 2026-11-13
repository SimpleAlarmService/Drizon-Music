import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/settings_model.dart';
import '../../services/download_service.dart';
import '../../services/library_service.dart';
import '../../services/music_service.dart';
import '../../services/settings_service.dart';
import '../../theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _updating = false;

  Future<T?> _pick<T>(String title, List<T> values, String Function(T) label) {
    return showCupertinoModalPopup<T>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(title),
        actions: [
          for (final v in values)
            CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(ctx, v), child: Text(label(v))),
        ],
        cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
      ),
    );
  }

  Future<void> _updateExtractor() async {
    setState(() => _updating = true);
    String message;
    try {
      message = await context.read<MusicService>().updateExtractor();
    } catch (e) {
      message = '업데이트에 실패했어요: $e';
    }
    if (!mounted) return;
    setState(() => _updating = false);
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx), child: const Text('확인')),
        ],
      ),
    );
  }

  Future<void> _confirm(String message, String action, VoidCallback onYes) async {
    final yes = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        content: Text(message),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('취소')),
          CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action)),
        ],
      ),
    );
    if (yes == true) onYes();
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final service = context.watch<SettingsService>();
    final s = service.settings;
    final downloads = context.watch<DownloadService>();

    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          CupertinoListSection.insetGrouped(
            header: const Text('재생'),
            children: [
              CupertinoListTile(
                title: const Text('자동 재생'),
                trailing: CupertinoSwitch(
                    value: s.autoplay, onChanged: service.setAutoplay),
              ),
              CupertinoListTile(
                title: const Text('음질'),
                additionalInfo: Text(s.audioQuality.label),
                trailing: const CupertinoListTileChevron(),
                onTap: () async {
                  final v = await _pick('음질', AudioQuality.values, (q) => q.label);
                  if (v != null) service.setAudioQuality(v);
                },
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: const Text('화면'),
            children: [
              CupertinoListTile(
                title: const Text('다크 모드'),
                trailing: CupertinoSwitch(
                    value: s.darkMode, onChanged: service.setDarkMode),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: const Text('추출기'),
            footer: Text(
              Platform.isIOS
                  ? 'iOS에서는 기기 안에서 yt-dlp가 실행됩니다. 재생이 안 되면 업데이트하거나 클라이언트를 바꿔 보세요.'
                  : '',
              style: Type.caption(pal),
            ),
            children: [
              CupertinoListTile(
                title: const Text('엔진'),
                additionalInfo: Text(_engineLabel(s.primaryExtractor)),
                trailing: const CupertinoListTileChevron(),
                onTap: () async {
                  final v = await _pick('엔진', ExtractorType.values, _engineLabel);
                  if (v != null) service.setPrimaryExtractor(v);
                },
              ),
              CupertinoListTile(
                title: const Text('클라이언트'),
                additionalInfo: Text(_clientLabel(s.clientType)),
                trailing: const CupertinoListTileChevron(),
                onTap: () async {
                  final v = await _pick('클라이언트', ClientType.values, _clientLabel);
                  if (v != null) service.setClientType(v);
                },
              ),
              if (Platform.isIOS)
                CupertinoListTile(
                  title: const Text('yt-dlp 업데이트'),
                  trailing: _updating
                      ? const CupertinoActivityIndicator()
                      : const CupertinoListTileChevron(),
                  onTap: _updating ? null : _updateExtractor,
                ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: const Text('다운로드'),
            footer: Text('기본은 스트리밍이에요. 곡의 ⋯ 메뉴에서 다운로드하면 오프라인으로 재생돼요.',
                style: Type.caption(pal)),
            children: [
              CupertinoListTile(
                title: const Text('사용 중인 공간'),
                additionalInfo: Text(_formatBytes(downloads.totalBytes)),
              ),
              CupertinoListTile(
                title: Text('다운로드 모두 삭제 (${downloads.tracks.length}곡)',
                    style: const TextStyle(color: CupertinoColors.destructiveRed)),
                onTap: downloads.tracks.isEmpty
                    ? null
                    : () => _confirm('다운로드한 곡을 모두 지울까요?', '삭제', downloads.removeAll),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: const Text('데이터'),
            children: [
              CupertinoListTile(
                title: const Text('재생 기록 지우기',
                    style: TextStyle(color: CupertinoColors.destructiveRed)),
                onTap: () => _confirm('재생 기록을 모두 지울까요?', '지우기',
                    () => context.read<LibraryService>().clearHistory()),
              ),
              CupertinoListTile(
                title: const Text('설정 초기화',
                    style: TextStyle(color: CupertinoColors.destructiveRed)),
                onTap: () => _confirm(
                    '모든 설정을 기본값으로 되돌릴까요?', '초기화', service.resetToDefaults),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _engineLabel(ExtractorType t) => switch (t) {
        ExtractorType.auto => '자동',
        ExtractorType.newpipe => Platform.isIOS ? 'yt-dlp' : 'NewPipe',
      };

  String _clientLabel(ClientType t) => switch (t) {
        ClientType.android => '기본',
        ClientType.web => 'Web',
        ClientType.tv => 'TV',
      };
}
