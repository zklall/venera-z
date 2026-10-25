part of 'reader.dart';

class _SpreadPairPicker extends StatefulWidget {
  const _SpreadPairPicker({
    required this.initialStart,
    required this.imageCount,
    required this.rightToLeft,
    required this.imageSizes,
    required this.imageBuilder,
  });

  final int initialStart;
  final int imageCount;
  final bool rightToLeft;
  final Map<int, Size> imageSizes;
  final Widget Function(int imageIndex, ValueChanged<Size> onSize) imageBuilder;

  @override
  State<_SpreadPairPicker> createState() => _SpreadPairPickerState();
}

class _SpreadPairPickerState extends State<_SpreadPairPicker> {
  late int selected = widget.initialStart.clamp(0, widget.imageCount - 2);
  late final sizes = Map<int, Size>.of(widget.imageSizes);

  void recordSize(int index, Size size) {
    if (sizes.containsKey(index)) return;
    sizes[index] = size;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  List<int> get candidates => [
    for (
      var start = widget.initialStart - 1;
      start <= widget.initialStart + 1;
      start++
    )
      if (start >= 0 && start + 1 < widget.imageCount) start,
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final glass = LiquidGlass.enabledOf(context);
    final images = widget.rightToLeft
        ? [selected + 1, selected]
        : [selected, selected + 1];
    final previewHeight = (MediaQuery.sizeOf(context).height * .3).clamp(
      84.0,
      240.0,
    );
    return SafeArea(
      top: false,
      child: buildSurface(
        context,
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Choose two pages for a spread'.tl,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close'.tl,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  'Numbers refer to single-page images. Select the pair that belongs together.'
                      .tl,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final start in candidates)
                      ChoiceChip(
                        key: ValueKey('reader-spread-pair-${start + 1}'),
                        selected: selected == start,
                        backgroundColor: glass
                            ? colors.surface.withValues(alpha: .34)
                            : null,
                        selectedColor: glass
                            ? colors.primaryContainer.withValues(alpha: .78)
                            : null,
                        side: glass
                            ? BorderSide(
                                color: selected == start
                                    ? colors.primary.withValues(alpha: .45)
                                    : colors.outlineVariant.withValues(
                                        alpha: .6,
                                      ),
                              )
                            : null,
                        onSelected: (_) => setState(() => selected = start),
                        label: Text(
                          'Pages @first–@last'.tlParams({
                            'first': start + 1,
                            'last': start + 2,
                          }),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: glass
                        ? colors.surface.withValues(alpha: .62)
                        : colors.surfaceContainerLowest,
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      height: previewHeight + 28,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final rects = readerSpreadRects(
                            Size(constraints.maxWidth, previewHeight),
                            [for (final index in images) sizes[index]],
                          );
                          return Stack(
                            children: [
                              for (var slot = 0; slot < 2; slot++) ...[
                                Positioned.fromRect(
                                  rect: rects[slot],
                                  child: KeyedSubtree(
                                    key: ValueKey(
                                      'reader-spread-preview-${images[slot] + 1}',
                                    ),
                                    child: widget.imageBuilder(
                                      images[slot],
                                      (size) => recordSize(images[slot], size),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: rects[slot].left,
                                  top: rects[slot].bottom + 6,
                                  width: rects[slot].width,
                                  child: Text(
                                    '${images[slot] + 1}',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('reader-spread-pair-confirm'),
                  onPressed: () => Navigator.of(context).pop(selected),
                  child: Text(
                    'Use pages @first–@last as a spread'.tlParams({
                      'first': selected + 1,
                      'last': selected + 2,
                    }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget buildSurface(BuildContext context, Widget child) {
    final colors = Theme.of(context).colorScheme;
    final glass = LiquidGlass.enabledOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: glass ? const EdgeInsets.all(12) : EdgeInsets.zero,
      child: LiquidGlass(
        borderRadius: BorderRadius.circular(28),
        bevelWidth: 20,
        refraction: 9,
        lightIntensity: 1.8,
        tint: colors.surface.withValues(alpha: dark ? .86 : .82),
        child: child,
      ),
    );
  }
}
