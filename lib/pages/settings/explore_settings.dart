part of 'settings_page.dart';

class ExploreSettings extends StatefulWidget {
  const ExploreSettings({super.key});

  @override
  State<ExploreSettings> createState() => _ExploreSettingsState();
}

class _ExploreSettingsState extends State<ExploreSettings> {
  @override
  Widget build(BuildContext context) {
    return SmoothCustomScrollView(
      slivers: [
        SliverAppbar(title: Text("Explore".tl)),
        SelectSetting(
          title: "Display mode of comic tile".tl,
          settingKey: "comicDisplayMode",
          optionTranslation: {
            "detailed": "Detailed".tl,
            "brief": "Brief".tl,
          },
        ).toSliver(),
        _SliderSetting(
          title: "Size of comic tile".tl,
          settingsIndex: "comicTileScale",
          interval: 0.05,
          min: 0.5,
          max: 1.5,
        ).toSliver(),
        _PopupWindowSetting(
          title: "Explore Pages".tl,
          builder: setExplorePagesWidget,
        ).toSliver(),
        _PopupWindowSetting(
          title: "Category Pages".tl,
          builder: setCategoryPagesWidget,
        ).toSliver(),
        _PopupWindowSetting(
          title: "Network Favorite Pages".tl,
          builder: setFavoritesPagesWidget,
        ).toSliver(),
        _PopupWindowSetting(
          title: "Search Sources".tl,
          builder: setSearchSourcesWidget,
        ).toSliver(),
        _SwitchSetting(
          title: "Show favorite status on comic tile".tl,
          settingKey: "showFavoriteStatusOnTile",
        ).toSliver(),
        _SwitchSetting(
          title: "Show history on comic tile".tl,
          settingKey: "showHistoryStatusOnTile",
        ).toSliver(),
        _SwitchSetting(
          title: "Reverse default chapter order".tl,
          settingKey: "reverseChapterOrder",
        ).toSliver(),
        _PopupWindowSetting(
          title: "Keyword blocking".tl,
          builder: () => const _ManageBlockingWordView(),
        ).toSliver(),
        _PopupWindowSetting(
          title: "Comment keyword blocking".tl,
          builder: () => const _ManageBlockingCommentWordView(),
        ).toSliver(),
        SelectSetting(
          title: "Default Search Target".tl,
          settingKey: "defaultSearchTarget",
          optionTranslation: {
            '_aggregated_': "Aggregated".tl,
            ...((){
              var map = <String, String>{};
              for (var c in ComicSource.visible()) {
                map[c.key] = c.name;
              }
              return map;
            }()),
          },
        ).toSliver(),
        SelectSetting(
          title: "Auto Language Filters".tl,
          settingKey: "autoAddLanguageFilter",
          optionTranslation: {
            'none': "None".tl,
            'chinese': "Chinese",
            'english': "English",
            'japanese': "Japanese",
          },
        ).toSliver(),
        SelectSetting(
          title: "Initial Page".tl,
          settingKey: "initialPage",
          optionTranslation: {
            '0': "Home Page".tl,
            '1': "Favorites Page".tl,
            '2': "Explore Page".tl,
            '3': "Categories Page".tl,
          },
        ).toSliver(),
        SelectSetting(
          title: "Display mode of comic list".tl,
          settingKey: "comicListDisplayMode",
          optionTranslation: {
            "paging": "Paging".tl,
            "Continuous": "Continuous".tl,
          },
        ).toSliver(),
      ],
    );
  }
}

class _ManageBlockingWordView extends StatefulWidget {
  const _ManageBlockingWordView();

  @override
  State<_ManageBlockingWordView> createState() =>
      _ManageBlockingWordViewState();
}

class _ManageBlockingWordViewState extends State<_ManageBlockingWordView> {
  @override
  Widget build(BuildContext context) {
    assert(appdata.settings["blockedWords"] is List);
    return PopUpWidgetScaffold(
      title: "Keyword blocking".tl,
      tailing: [
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: Text("Add".tl),
          onPressed: add,
        ),
      ],
      body: ListView.builder(
        itemCount: appdata.settings["blockedWords"].length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(appdata.settings["blockedWords"][index]),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                appdata.settings["blockedWords"].removeAt(index);
                appdata.saveData();
                setState(() {});
              },
            ),
          );
        },
      ),
    );
  }

  void add() {
    showDialog(
      context: App.rootContext,
      builder: (context) {
        var controller = TextEditingController();
        String? error;
        return StatefulBuilder(builder: (context, setState) {
          return ContentDialog(
            title: "Add keyword".tl,
            content: TextField(
              controller: controller,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                label: Text("Keyword".tl),
                errorText: error,
              ),
              onChanged: (s) {
                if (error != null) {
                  setState(() {
                    error = null;
                  });
                }
              },
            ).paddingHorizontal(12),
            actions: [
              Button.filled(
                onPressed: () {
                  if (appdata.settings["blockedWords"]
                      .contains(controller.text)) {
                    setState(() {
                      error = "Keyword already exists".tl;
                    });
                    return;
                  }
                  appdata.settings["blockedWords"].add(controller.text);
                  appdata.saveData();
                  this.setState(() {});
                  context.pop();
                },
                child: Text("Add".tl),
              ),
            ],
          );
        });
      },
    );
  }
}

Set<String> _hiddenPageKeys(String setting) {
  final manager = ComicSourceManager();
  Iterable<String> keys(ComicSource source) => switch (setting) {
    'explore_pages' => source.explorePages.map((page) => page.title),
    'categories' => [if (source.categoryData != null) source.categoryData!.key],
    'favorites' => [if (source.favoriteData != null) source.favoriteData!.key],
    'searchSources' => [if (source.searchPageData != null) source.key],
    _ => const <String>[],
  };
  final hidden = manager
      .all()
      .where((source) => !manager.isVisible(source.key))
      .expand(keys)
      .toSet();
  final visible = manager.visible().expand(keys).toSet();
  return hidden.difference(visible);
}

Widget setExplorePagesWidget() {
  var pages = <String, String>{};
  for (var c in ComicSource.visible()) {
    for (var page in c.explorePages) {
      pages[page.title] = page.title.ts(c.key);
    }
  }
  return _MultiPagesFilter(
    title: "Explore Pages".tl,
    settingsIndex: "explore_pages",
    pages: pages,
    preservedKeys: _hiddenPageKeys("explore_pages"),
  );
}

Widget setCategoryPagesWidget() {
  var pages = <String, String>{};
  for (var c in ComicSource.visible()) {
    if (c.categoryData != null) {
      pages[c.categoryData!.key] = c.categoryData!.title;
    }
  }
  return _MultiPagesFilter(
    title: "Category Pages".tl,
    settingsIndex: "categories",
    pages: pages,
    preservedKeys: _hiddenPageKeys("categories"),
  );
}

Widget setFavoritesPagesWidget() {
  var pages = <String, String>{};
  for (var c in ComicSource.visible()) {
    if (c.favoriteData != null) {
      pages[c.favoriteData!.key] = c.favoriteData!.title;
    }
  }
  return _MultiPagesFilter(
    title: "Network Favorite Pages".tl,
    settingsIndex: "favorites",
    pages: pages,
    preservedKeys: _hiddenPageKeys("favorites"),
  );
}

Widget setSearchSourcesWidget() {
  var pages = <String, String>{};
  for (var c in ComicSource.visible()) {
    if (c.searchPageData != null) {
      pages[c.key] = c.name;
    }
  }
  return _MultiPagesFilter(
    title: "Search Sources".tl,
    settingsIndex: "searchSources",
    pages: pages,
    preservedKeys: _hiddenPageKeys("searchSources"),
  );
}

class _ManageBlockingCommentWordView extends StatefulWidget {
  const _ManageBlockingCommentWordView();

  @override
  State<_ManageBlockingCommentWordView> createState() =>
      _ManageBlockingCommentWordViewState();
}

class _ManageBlockingCommentWordViewState extends State<_ManageBlockingCommentWordView> {
  @override
  Widget build(BuildContext context) {
    assert(appdata.settings["blockedCommentWords"] is List);
    return PopUpWidgetScaffold(
      title: "Comment keyword blocking".tl,
      tailing: [
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: Text("Add".tl),
          onPressed: add,
        ),
      ],
      body: ListView.builder(
        itemCount: appdata.settings["blockedCommentWords"].length,
        itemBuilder: (context, index) {
          return ListTile(
            title: Text(appdata.settings["blockedCommentWords"][index]),
            trailing: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                appdata.settings["blockedCommentWords"].removeAt(index);
                appdata.saveData();
                setState(() {});
              },
            ),
          );
        },
      ),
    );
  }

  void add() {
    showDialog(
      context: App.rootContext,
      builder: (context) {
        var controller = TextEditingController();
        String? error;
        return StatefulBuilder(builder: (context, setState) {
          return ContentDialog(
            title: "Add keyword".tl,
            content: TextField(
              controller: controller,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                label: Text("Keyword".tl),
                errorText: error,
              ),
              onChanged: (s) {
                if (error != null) {
                  setState(() {
                    error = null;
                  });
                }
              },
            ).paddingHorizontal(12),
            actions: [
              Button.filled(
                onPressed: () {
                  if (appdata.settings["blockedCommentWords"]
                      .contains(controller.text)) {
                    setState(() {
                      error = "Keyword already exists".tl;
                    });
                    return;
                  }
                  appdata.settings["blockedCommentWords"].add(controller.text);
                  appdata.saveData();
                  this.setState(() {});
                  context.pop();
                },
                child: Text("Add".tl),
              ),
            ],
          );
        });
      },
    );
  }
}