import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/theme.dart';

/// A tactile "3D" button with a darker bottom edge that presses down.
class ChunkyButton extends StatefulWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.color = AppColors.green,
    this.textColor = Colors.white,
    this.icon,
    this.expand = true,
    this.outlined = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color color;
  final Color textColor;
  final IconData? icon;
  final bool expand;
  final bool outlined;

  @override
  State<ChunkyButton> createState() => _ChunkyButtonState();
}

class _ChunkyButtonState extends State<ChunkyButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final Color face;
    final Color edge;
    final Color fg;
    if (!enabled) {
      face = context.isDark ? const Color(0xFF37464F) : AppColors.grey;
      edge = face;
      fg = context.isDark ? const Color(0xFF52656D) : AppColors.greyDark;
    } else if (widget.outlined) {
      face = context.colors.surface;
      edge = context.border;
      fg = widget.color;
    } else {
      face = widget.color;
      edge = AppColors.darken(widget.color);
      fg = widget.textColor;
    }
    const depth = 4.0;
    final child = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, color: fg, size: 20),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            widget.label.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                HapticFeedback.lightImpact();
                widget.onPressed!();
              }
            : null,
        child: SizedBox(
          height: 50 + depth,
          child: Stack(
            children: [
              Positioned.fill(
                top: depth,
                child: Container(
                  decoration: BoxDecoration(
                    color: edge,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 60),
                left: 0,
                right: 0,
                top: _down || !enabled ? depth : 0,
                height: 50,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: face,
                    borderRadius: BorderRadius.circular(16),
                    border: widget.outlined && enabled
                        ? Border.all(color: context.border, width: 2)
                        : null,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A selectable tile with a pressed-in bottom edge, used for answer options.
class OptionTile extends StatelessWidget {
  const OptionTile({
    super.key,
    required this.child,
    required this.onTap,
    this.selected = false,
    this.state,
    this.dense = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final bool selected;

  /// null = neutral, true = shown as correct, false = shown as wrong.
  final bool? state;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    Color borderC = context.border;
    Color bg = context.colors.surface;
    if (state == true) {
      borderC = AppColors.green;
      bg = AppColors.green.withValues(alpha: context.isDark ? 0.18 : 0.12);
    } else if (state == false) {
      borderC = AppColors.red;
      bg = AppColors.red.withValues(alpha: context.isDark ? 0.18 : 0.10);
    } else if (selected) {
      borderC = AppColors.blue;
      bg = AppColors.blue.withValues(alpha: context.isDark ? 0.18 : 0.10);
    }
    return GestureDetector(
      onTap: onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              onTap!();
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 10 : 14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border(
            top: BorderSide(color: borderC, width: 2),
            left: BorderSide(color: borderC, width: 2),
            right: BorderSide(color: borderC, width: 2),
            bottom: BorderSide(color: borderC, width: 4),
          ),
        ),
        child: child,
      ),
    );
  }
}
