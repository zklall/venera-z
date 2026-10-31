import 'package:flutter/material.dart';
import 'package:venera/foundation/reader_orientation.dart';
import 'package:venera/utils/translations.dart';

/// Rotates layout, hit testing and overlays together, including safe areas.
class ReaderRotationViewport extends StatelessWidget {
  const ReaderRotationViewport({
    super.key,
    required this.rotation,
    required this.child,
  });

  final ReaderRotation rotation;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => RotatedBox(
      quarterTurns: rotation.quarterTurns,
      child: MediaQuery(
        data: rotation.mediaQuery(MediaQuery.of(context), constraints.biggest),
        child: child,
      ),
    ),
  );
}

class ReaderRotationPanel extends StatelessWidget {
  const ReaderRotationPanel({
    super.key,
    required this.rotation,
    required this.pinned,
    required this.onChanged,
    required this.onPinChanged,
    required this.onClose,
  });

  final ReaderRotation rotation;
  final ReaderRotation? pinned;
  final ValueChanged<ReaderRotation> onChanged;
  final ValueChanged<bool> onPinChanged;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Reading direction'.tl,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Close'.tl,
                onPressed: onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final direction in ReaderRotation.values)
                  SizedBox(
                    width: (constraints.maxWidth - 24) / 3,
                    child: Semantics(
                      selected: rotation == direction,
                      child: Material(
                        color: rotation == direction
                            ? colors.primaryContainer
                            : colors.surfaceContainer,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: BorderSide(
                            color: rotation == direction
                                ? colors.primary
                                : colors.outlineVariant,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: ValueKey('reader-rotation-${direction.name}'),
                          onTap: () => onChanged(direction),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 14,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                RotatedBox(
                                  quarterTurns: direction.quarterTurns,
                                  child: const Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Icon(
                                        Icons.stay_current_portrait,
                                        size: 32,
                                      ),
                                      Icon(Icons.arrow_upward, size: 15),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  direction.label.tl,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SwitchListTile.adaptive(
            key: const Key('reader-rotation-pin'),
            contentPadding: EdgeInsets.zero,
            title: Text('Use as default for future reading'.tl),
            subtitle: pinned != null && pinned != rotation
                ? Text(
                    'Current default: @direction'.tlParams({
                      'direction': pinned!.label.tl,
                    }),
                  )
                : null,
            value: pinned == rotation,
            onChanged: onPinChanged,
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: onClose, child: Text('Close'.tl)),
        ],
      ),
    );
  }
}
