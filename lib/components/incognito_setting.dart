import 'dart:async';
import 'package:flutter/material.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/utils/translations.dart';

class IncognitoSetting extends StatelessWidget {
  const IncognitoSetting({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: appdata.settings,
    builder: (context, _) => SwitchListTile(
      secondary: const Icon(Icons.visibility_off_outlined),
      title: Text('Incognito mode'.tl),
      value: appdata.isIncognito,
      onChanged: (enabled) {
        appdata.settings['incognitoMode'] = enabled;
        unawaited(appdata.saveData(false));
      },
    ),
  );
}
