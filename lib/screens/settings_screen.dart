import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/settings_model.dart';
import '../services/settings_service.dart';
import '../theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = context.watch<SettingsService>();
    final s = svc.settings;

    return Scaffold(
      backgroundColor: kSurface,
      body: CustomScrollView(
        slivers: [
          // ── AppBar ───────────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: kSurface,
            pinned: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: kOnSurface),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text('설정', style: headline(20)),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── PLAYBACK ────────────────────────────────────────────────
                  _SectionHeader('재생'),
                  _SwitchTile(
                    icon: Icons.play_circle_outline,
                    title: '자동 재생',
                    subtitle: '큐가 끝나면 다음 곡을 자동으로 재생합니다',
                    value: s.autoplay,
                    onChanged: svc.setAutoplay,
                  ),
                  _DropdownTile<AudioQuality>(
                    icon: Icons.high_quality_outlined,
                    title: '오디오 품질',
                    value: s.audioQuality,
                    items: AudioQuality.values,
                    labelOf: (q) => q.label,
                    onChanged: svc.setAudioQuality,
                  ),

                  // ── NETWORK ─────────────────────────────────────────────────
                  _SectionHeader('네트워크'),
                  _SwitchTile(
                    icon: Icons.wifi_outlined,
                    title: 'Wi-Fi 전용',
                    subtitle: 'Wi-Fi 연결 시에만 스트리밍합니다',
                    value: s.wifiOnly,
                    onChanged: svc.setWifiOnly,
                  ),
                  _SwitchTile(
                    icon: Icons.data_saver_on_outlined,
                    title: '데이터 절약',
                    subtitle: '저품질 스트리밍으로 데이터 사용량을 줄입니다',
                    value: s.dataSaver,
                    onChanged: (v) {
                      svc.setDataSaver(v);
                      if (v) svc.setAudioQuality(AudioQuality.low);
                    },
                  ),

                  // ── CACHE ───────────────────────────────────────────────────
                  _SectionHeader('캐시'),
                  _SwitchTile(
                    icon: Icons.storage_outlined,
                    title: '캐시 사용',
                    subtitle: '이미지 및 메타데이터를 로컬에 저장합니다',
                    value: s.cacheEnabled,
                    onChanged: svc.setCacheEnabled,
                  ),
                  if (s.cacheEnabled)
                    _SliderTile(
                      icon: Icons.sd_card_outlined,
                      title: '캐시 크기',
                      value: s.cacheSizeMb.toDouble(),
                      min: 64,
                      max: 1024,
                      divisions: 15,
                      labelBuilder: (v) => '${v.round()} MB',
                      onChanged: (v) => svc.setCacheSizeMb(v.round()),
                    ),
                  _ActionTile(
                    icon: Icons.delete_sweep_outlined,
                    title: '캐시 지우기',
                    subtitle: '저장된 임시 파일을 모두 삭제합니다',
                    onTap: () => _confirmClearCache(context),
                  ),

                  // ── ADVANCED (hidden until advancedMode = true) ─────────────
                  if (s.advancedMode) ...[
                    _SectionHeader('고급  —  익스트랙터'),
                    _DropdownTile<ExtractorType>(
                      icon: Icons.alt_route_outlined,
                      title: '기본 익스트랙터',
                      value: s.primaryExtractor,
                      items: ExtractorType.values,
                      labelOf: (e) => e.label,
                      onChanged: (v) {
                        svc.setPrimaryExtractor(v);
                        // Push to MusicService at runtime
                        _applyExtractorSettings(context, svc.settings);
                      },
                    ),
                    _DropdownTile<ClientType>(
                      icon: Icons.devices_outlined,
                      title: '클라이언트 타입',
                      subtitle: 'YouTube 요청에 사용할 클라이언트를 선택합니다 (403 오류 해결에 유용)',
                      value: s.clientType,
                      items: ClientType.values,
                      labelOf: (c) => c.label,
                      onChanged: (v) {
                        svc.setClientType(v);
                        _applyExtractorSettings(context, svc.settings);
                      },
                    ),
                    _SwitchTile(
                      icon: Icons.safety_check_outlined,
                      title: 'Dart 폴백 사용',
                      subtitle: '네이티브 익스트랙터 실패 시 Dart 구현으로 재시도합니다',
                      value: s.enableFallback,
                      onChanged: (v) {
                        svc.setEnableFallback(v);
                        _applyExtractorSettings(context, svc.settings);
                      },
                    ),
                  ],

                  // ── DEBUG ───────────────────────────────────────────────────
                  _SectionHeader('디버그'),
                  _SwitchTile(
                    icon: Icons.developer_mode_outlined,
                    title: '고급 설정 표시',
                    subtitle: '익스트랙터 및 클라이언트 설정을 표시합니다',
                    value: s.advancedMode,
                    onChanged: svc.setAdvancedMode,
                  ),
                  _ActionTile(
                    icon: Icons.restore_outlined,
                    title: '설정 초기화',
                    subtitle: '모든 설정을 기본값으로 되돌립니다',
                    onTap: () => _confirmReset(context, svc),
                    destructive: true,
                  ),

                  // App version footer
                  const SizedBox(height: 32),
                  Center(
                    child: Text(
                      'Drizon',
                      style: body(12, color: kOutline),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _applyExtractorSettings(BuildContext context, AppSettings settings) {
    // MusicService is a plain Provider — reach it directly
    try {
      context.read<dynamic>()?.applySettings(settings);
    } catch (_) {}
  }

  Future<void> _confirmClearCache(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceContainerHigh,
        title: Text('캐시 지우기', style: headline(18)),
        content: Text('저장된 캐시를 모두 삭제할까요?',
            style: body(14, color: kOnSurfaceVariant)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('취소', style: body(14, color: kOnSurfaceVariant))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('삭제', style: body(14, color: Colors.redAccent))),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('캐시가 삭제되었습니다', style: body(13)),
          backgroundColor: kSurfaceContainerHigh,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmReset(
      BuildContext context, SettingsService svc) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceContainerHigh,
        title: Text('설정 초기화', style: headline(18)),
        content: Text('모든 설정을 기본값으로 되돌릴까요?',
            style: body(14, color: kOnSurfaceVariant)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('취소', style: body(14, color: kOnSurfaceVariant))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('초기화', style: body(14, color: Colors.redAccent))),
        ],
      ),
    );
    if (ok == true) svc.resetToDefaults();
  }
}

// ── Section Header ────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: label(11, color: kPrimary),
      ),
    );
  }
}

// ── Switch Tile ───────────────────────────────────────────────────────────────

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(icon, color: kOnSurfaceVariant, size: 22),
      title: Text(title, style: body(15, weight: FontWeight.w600)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: body(12, color: kOnSurfaceVariant))
          : null,
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: kPrimary,
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return kPrimary.withValues(alpha: 0.3);
          }
          return kSurfaceContainerHighest;
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return kPrimary;
          return kOutline;
        }),
      ),
    );
  }
}

// ── Dropdown Tile ─────────────────────────────────────────────────────────────

class _DropdownTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  const _DropdownTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(icon, color: kOnSurfaceVariant, size: 22),
      title: Text(title, style: body(15, weight: FontWeight.w600)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: body(12, color: kOnSurfaceVariant))
          : null,
      trailing: DropdownButton<T>(
        value: value,
        dropdownColor: kSurfaceContainerHigh,
        underline: const SizedBox.shrink(),
        style: body(13, color: kPrimary),
        icon: const Icon(Icons.expand_more, color: kOnSurfaceVariant, size: 18),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
        items: items
            .map((item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(labelOf(item), style: body(13)),
                ))
            .toList(),
      ),
    );
  }
}

// ── Slider Tile ───────────────────────────────────────────────────────────────

class _SliderTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String Function(double) labelBuilder;
  final ValueChanged<double> onChanged;

  const _SliderTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
      leading: Icon(icon, color: kOnSurfaceVariant, size: 22),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: body(15, weight: FontWeight.w600)),
          Text(labelBuilder(value), style: body(13, color: kPrimary)),
        ],
      ),
      subtitle: SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          activeTrackColor: kPrimary,
          inactiveTrackColor: kSurfaceContainerHighest,
          thumbColor: kPrimary,
          overlayColor: kPrimary.withValues(alpha: 0.12),
        ),
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ── Action Tile ───────────────────────────────────────────────────────────────

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool destructive;

  const _ActionTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? Colors.redAccent : kOnSurface;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Icon(icon, color: destructive ? Colors.redAccent : kOnSurfaceVariant, size: 22),
      title: Text(title,
          style: body(15, weight: FontWeight.w600, color: color)),
      subtitle: subtitle != null
          ? Text(subtitle!, style: body(12, color: kOnSurfaceVariant))
          : null,
      onTap: onTap,
    );
  }
}
