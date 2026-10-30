part of 'components.dart';

/// Raw diagnostics are opt-in; the main error view always explains recovery.
class DiagnosticDetails extends StatelessWidget {
  const DiagnosticDetails({super.key, required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    title: Text('Diagnostic details'.tl),
    children: [
      ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 180),
        child: SingleChildScrollView(child: SelectableText(error.toString())),
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: () =>
                Clipboard.setData(ClipboardData(text: error.toString())),
            icon: const Icon(Icons.copy, size: 18),
            label: Text('Copy'.tl),
          ),
          TextButton.icon(
            onPressed: () => saveFile(
              data: utf8.encode(Log().toString()),
              filename: 'log.txt',
            ),
            icon: const Icon(Icons.file_download_outlined, size: 18),
            label: Text('Export logs'.tl),
          ),
        ],
      ),
    ],
  );
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice({super.key, required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) {
    final info = AppErrorInfo.from(error);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(info.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        Text(info.message),
        DiagnosticDetails(error: error),
      ],
    );
  }
}

void showAppErrorDetails(BuildContext context, Object error) {
  final info = AppErrorInfo.from(error);
  final challenge = CloudflareException.fromString(error.toString());
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(info.title),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(info.message),
              DiagnosticDetails(error: error),
            ],
          ),
        ),
      ),
      actions: [
        if (challenge != null)
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              passCloudflare(challenge, () {});
            },
            child: Text('Verify'.tl),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Close'.tl),
        ),
      ],
    ),
  );
}

void showAppError({required BuildContext context, required Object error}) {
  final info = AppErrorInfo.from(error);
  Log.error('Operation failed', error.toString());
  showToast(
    context: context,
    message: info.message,
    seconds: 8,
    icon: const Icon(Icons.error_outline),
    trailing: TextButton(
      onPressed: () => showAppErrorDetails(context, error),
      child: Text('Details'.tl),
    ),
  );
}
