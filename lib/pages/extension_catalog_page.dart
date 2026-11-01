import 'dart:async';
import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/foundation/app.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'package:venera/foundation/comic_source/mihon_source.dart';
import 'package:venera/foundation/comic_source/mihon_catalog.dart';
import 'package:venera/foundation/comic_source/source_library.dart';
import 'package:venera/network/app_dio.dart';
import 'package:venera/utils/io.dart';
import 'package:venera/utils/translations.dart';

class ExtensionCatalogPage extends StatefulWidget {
  const ExtensionCatalogPage({
    super.key,
    this.repository = MihonCatalog.defaultUrl,
    this.initialApkPath,
    this.title,
    this.loadCatalog,
  });
  final String repository;
  final String? initialApkPath;
  final String? title;
  final Future<List<MihonExtension>> Function(String)? loadCatalog;
  @override
  State<ExtensionCatalogPage> createState() => _ExtensionCatalogPageState();
}

class _ExtensionCatalogPageState extends State<ExtensionCatalogPage> {
  late String repository;
  List<MihonExtension>? extensions;
  Map<String, dynamic> installed = {};
  Object? failure;
  String query = '', language = 'zh';
  final busy = <String>{};
  bool loading = false;
  int loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    repository = widget.repository;
    unawaited(_load());
    if (widget.initialApkPath != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _importPath(widget.initialApkPath!),
      );
    }
  }

  Future<void> _load() async {
    final generation = ++loadGeneration;
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      final result = await (widget.loadCatalog ?? MihonCatalog.load)(
        repository,
      );
      final state = await MihonSource.installed();
      if (!mounted || generation != loadGeneration) return;
      setState(() {
        extensions = result;
        if (language.isNotEmpty &&
            !result.any(
              (e) =>
                  e.languages.contains(language) || e.languages.contains('all'),
            )) {
          language = '';
        }
        installed = state;
      });
    } catch (error) {
      if (mounted && generation == loadGeneration) {
        setState(() => failure = error);
      }
    } finally {
      if (mounted && generation == loadGeneration) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _syncInstalled() async {
    final previous = ComicSource.all().whereType<MihonSource>().toList();
    await ComicSourceManager().reload();
    final current = ComicSource.all().whereType<MihonSource>().toList();
    final keys = current.map((s) => s.key).toSet();
    final previousKeys = previous.map((s) => s.key).toSet();
    appdata.settings['searchSources'] = <String>{
      for (final key
          in (appdata.settings['searchSources'] as List).cast<String>())
        if (!key.startsWith('mihon_') || keys.contains(key)) key,
      ...keys.difference(previousKeys),
    }.toList();
    final oldPages = previous
        .expand((s) => s.explorePages)
        .map((p) => p.title)
        .toSet();
    final enabledPages = (appdata.settings['explore_pages'] as List)
        .cast<String>();
    final previousByKey = {for (final source in previous) source.key: source};
    appdata.settings['explore_pages'] = <String>{
      for (final page in enabledPages)
        if (!oldPages.contains(page)) page,
      for (final source in current)
        if (!previousByKey.containsKey(source.key) ||
            previousByKey[source.key]!.explorePages.any(
              (page) => enabledPages.contains(page.title),
            ))
          ...source.explorePages.map((page) => page.title),
    }.toList();
    await appdata.saveData();
    final state = await MihonSource.installed();
    if (mounted) setState(() => installed = state);
  }

  Future<bool> _confirm(String path, String name) async {
    final metadata = await MihonSource.inspect(path);
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text('Install extension'.tl),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(metadata['name']?.toString() ?? name),
                  Text(metadata['version']?.toString() ?? ''),
                  ExpansionTile(
                    title: Text('Details'.tl),
                    children: [
                      SelectableText(
                        '${metadata['package']}\n${(metadata['signatures'] as List).join('\n')}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: Text('Cancel'.tl),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: Text('Install'.tl),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _install(MihonExtension extension) async {
    if (!busy.add(extension.package)) return;
    setState(() {});
    Directory? directory;
    try {
      directory = await Directory.systemTemp.createTemp('mihon-apk-');
      final path = '${directory.path}/extension.apk';
      await AppDio().download(
        extension.apkUrl,
        path,
        options: Options(headers: {'cache-time': 'no'}),
      );
      final metadata = await MihonSource.inspect(path);
      if (metadata['package'] != extension.package) {
        throw const FormatException(
          'Extension package does not match the catalog',
        );
      }
      if (!await _confirm(path, extension.name)) return;
      await MihonSource.install(path);
      await _syncInstalled();
      final library = ComicSourceLibraryManager.add('', repository);
      for (final source in ComicSource.all().whereType<MihonSource>().where(
        (s) => s.packageName == extension.package,
      )) {
        ComicSourceLibraryManager.recordOrigin(
          source.key,
          library.id,
          sourceFileName: Uri.parse(extension.apkUrl).pathSegments.last,
        );
      }
      if (mounted) context.showMessage(message: 'Installed'.tl);
    } catch (error) {
      if (mounted) context.showError(error: error);
    } finally {
      await directory?.delete(recursive: true);
      busy.remove(extension.package);
      if (mounted) setState(() {});
    }
  }

  Future<void> _import() async {
    final file = await selectFile(ext: ['apk']);
    if (file == null) return;
    final directory = await Directory.systemTemp.createTemp('source-import-');
    try {
      final path = '${directory.path}/extension.apk';
      await file.saveTo(path);
      await _importPath(path);
    } finally {
      await directory.delete(recursive: true);
    }
  }

  Future<void> _importPath(String path) async {
    try {
      if (!await _confirm(path, path.split('/').last)) return;
      await MihonSource.install(path);
      await _syncInstalled();
      if (mounted) context.showMessage(message: 'Installed'.tl);
    } catch (error) {
      if (mounted) context.showError(error: error);
    }
  }

  Future<void> _repository() async {
    var value = repository;
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Repository link'.tl),
        content: TextFormField(
          initialValue: value,
          decoration: const InputDecoration(labelText: 'URL'),
          onChanged: (text) => value = text.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text('Cancel'.tl),
          ),
          FilledButton(
            onPressed: () {
              if (!isHttpSourceUrl(value)) {
                context.showMessage(message: 'Invalid URL'.tl);
                return;
              }
              repository = value;
              ComicSourceLibraryManager.add('', value);
              appdata.settings['mihonRepository'] = value;
              unawaited(appdata.saveData(false));
              Navigator.pop(dialog);
              unawaited(_load());
            },
            child: Text('Save'.tl),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final installedPackages = {
      for (final s in (installed['sources'] as List? ?? []).whereType<Map>())
        s['package']: s['version'],
    };
    final languages = {
      for (final e in extensions ?? <MihonExtension>[]) ...e.languages,
    }.toList()..sort();
    String languageName(String code) => switch (code) {
      '' => 'All languages'.tl,
      'zh' => '中文',
      'en' => 'English',
      'ja' => '日本語',
      'ko' => '한국어',
      'all' => 'Multiple languages'.tl,
      _ => code,
    };
    final hiddenPackages = appdata.isIncognito
        ? <String>{}
        : ComicSource.all()
              .whereType<MihonSource>()
              .where(
                (source) => ComicSourceManager().isIncognitoOnly(source.key),
              )
              .map((source) => source.packageName)
              .toSet();
    final visible = (extensions ?? <MihonExtension>[])
        .where(
          (e) =>
              !hiddenPackages.contains(e.package) &&
              (language.isEmpty ||
                  e.languages.contains(language) ||
                  e.languages.contains('all')) &&
              '${e.name} ${e.sources.join(' ')} ${e.package}'
                  .toLowerCase()
                  .contains(query.trim().toLowerCase()),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'Source catalog'.tl),
        actions: [
          IconButton(
            tooltip: 'Repository link'.tl,
            icon: const Icon(Icons.dns_outlined),
            onPressed: _repository,
          ),
          IconButton(
            tooltip: 'Import file'.tl,
            icon: const Icon(Icons.file_open_outlined),
            onPressed: _import,
          ),
          IconButton(
            tooltip: 'Refresh'.tl,
            icon: const Icon(Icons.refresh),
            onPressed: loading ? null : _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search'.tl,
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (value) => setState(() => query = value),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Language'.tl,
                  initialValue: language,
                  onSelected: (value) => setState(() => language = value),
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem(
                      value: '',
                      checked: language.isEmpty,
                      child: Text('All languages'.tl),
                    ),
                    for (final lang in languages)
                      CheckedPopupMenuItem(
                        value: lang,
                        checked: language == lang,
                        child: Text(languageName(lang)),
                      ),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.language),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 120),
                          child: Text(
                            languageName(language),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final entry in (installed['failures'] as Map? ?? {}).entries)
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(entry.key.toString()),
              onTap: () => showAppErrorDetails(context, entry.value.toString()),
            ),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : failure != null
                ? NetworkError(
                    message: failure.toString(),
                    retry: _load,
                    withAppbar: false,
                  )
                : visible.isEmpty
                ? Center(child: Text('No results'.tl))
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final e = visible[index];
                      final version = installedPackages[e.package];
                      final installed = version == e.version;
                      return ListTile(
                        leading: Icon(
                          installed
                              ? Icons.extension
                              : Icons.extension_outlined,
                        ),
                        title: Text(e.name),
                        subtitle: Text(
                          '${e.languages.join(', ')} · ${e.version}',
                        ),
                        onTap: () => showDialog<void>(
                          context: context,
                          builder: (dialog) => AlertDialog(
                            title: Text(e.name),
                            content: SingleChildScrollView(
                              child: SelectableText(e.sources.join('\n')),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialog),
                                child: Text('Close'.tl),
                              ),
                            ],
                          ),
                        ),
                        trailing: busy.contains(e.package)
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : installed
                            ? const Icon(Icons.check)
                            : IconButton(
                                tooltip:
                                    (version == null ? 'Install' : 'Update').tl,
                                icon: Icon(
                                  version == null
                                      ? Icons.download_outlined
                                      : Icons.system_update_alt,
                                ),
                                onPressed: App.isAndroid
                                    ? () => _install(e)
                                    : null,
                              ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
