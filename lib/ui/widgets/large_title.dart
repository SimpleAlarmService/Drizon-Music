import 'package:flutter/material.dart';
import '../../theme.dart';

/// iOS-style large page title with an optional trailing action.
class LargeTitle extends StatelessWidget {
  const LargeTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: Type.largeTitle(pal))),
          ?trailing,
        ],
      ),
    );
  }
}
