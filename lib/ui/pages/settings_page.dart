import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/settings_model.dart';
import '../../services/download_service.dart';
import '../../services/extractor_update_service.dart';
import '../../services/library_service.dart';
import '../../services/settings_service.dart';
import '../../theme.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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
    final updates = context.watch<ExtractorUpdateService>();
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
                title: const Text('비슷한 곡 이어 듣기'),
                subtitle: const Text('대기열이 끝나면 같은 아티스트의 곡을 이어서 재생'),
                trailing: CupertinoSwitch(value: s.radio, onChanged: service.setRadio),
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
              (Platform.isIOS || Platform.isMacOS)
                  ? 'yt-dlp가 이 기기 안에서 실행됩니다. 재생이 안 되면 아래에서 업데이트하거나 클라이언트를 바꿔 보세요.'
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
            ],
          ),
          if (updates.supported) _componentsSection(updates, pal),
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

  Widget _componentsSection(ExtractorUpdateService u, Palette pal) {
    final last = u.lastChecked;
    final footer = [
      if (u.message != null) u.message!,
      if (u.message == null && u.restartPending) '새 버전을 받았어요. 앱을 다시 시작하면 적용돼요.',
      if (last != null)
        '마지막 확인: ${last.year}-${last.month.toString().padLeft(2, '0')}-${last.day.toString().padLeft(2, '0')} '
            '${last.hour.toString().padLeft(2, '0')}:${last.minute.toString().padLeft(2, '0')}',
    ].join('\n');
    return CupertinoListSection.insetGrouped(
      header: const Text('오픈소스 구성요소'),
      footer: footer.isEmpty ? null : Text(footer, style: Type.caption(pal)),
      children: [
        for (final c in u.components)
          CupertinoListTile(
            title: Text(c.name),
            subtitle: c.updateAvailable
                ? Text('새 버전 ${c.latest}', style: const TextStyle(color: CupertinoColors.activeBlue))
                : c.restartPending
                    ? const Text('재시작하면 적용')
                    : null,
            additionalInfo: Text(c.current.isEmpty ? '-' : c.current),
          ),
        CupertinoListTile(
          title: Text(u.hasUpdate ? '업데이트' : '업데이트 확인'),
          trailing: (u.checking || u.updating)
              ? const CupertinoActivityIndicator()
              : const CupertinoListTileChevron(),
          onTap: (u.checking || u.updating) ? null : (u.hasUpdate ? u.update : u.check),
        ),
        CupertinoListTile(
          title: const Text('자동으로 업데이트'),
          trailing: CupertinoSwitch(
              value: u.autoUpdate, onChanged: (v) => u.autoUpdate = v),
        ),
      ],
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _engineLabel(ExtractorType t) => switch (t) {
        ExtractorType.auto => '자동',
        ExtractorType.newpipe => (Platform.isIOS || Platform.isMacOS) ? 'yt-dlp' : 'NewPipe',
      };

  String _clientLabel(ClientType t) => switch (t) {
        ClientType.android => '기본',
        ClientType.web => 'Web',
        ClientType.tv => 'TV',
      };
}
