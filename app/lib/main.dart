import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'src/app_state.dart';
import 'src/storage/session.dart';
import 'src/ui/home.dart';
import 'src/ui/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  RandomAccessFile lock;
  try {
    lock = await lockSession();
  } catch (e) {
    stderr.writeln(e);
    exit(1);
  }

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(1050, 740),
      minimumSize: Size(560, 360),
      title: 'writestuff',
    ),
    () async {
      await windowManager.setPreventClose(true);
      await windowManager.show();
      await windowManager.focus();
    },
  );

  final loaded = await loadSession();
  final state = AppState(
    loaded.session,
    notice: loaded.notice,
    onExit: () async {
      await lock.unlock();
      await lock.close();
      await windowManager.setPreventClose(false);
      await windowManager.close();
    },
  );
  for (final path in args.where((a) => !a.startsWith('-'))) {
    await state.openPath(path);
  }
  runApp(WritestuffApp(state: state));
}

class WritestuffApp extends StatefulWidget {
  const WritestuffApp({super.key, required this.state});
  final AppState state;

  @override
  State<WritestuffApp> createState() => _WritestuffAppState();
}

class _WritestuffAppState extends State<WritestuffApp>
    with WidgetsBindingObserver, WindowListener {
  AppState get state => widget.state;
  String _title = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
    _readBrightness();
    state.addListener(_onState);
    state.focusActive();
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    windowManager.removeListener(this);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _readBrightness() => state.setSystemDark(
    PlatformDispatcher.instance.platformBrightness == Brightness.dark,
  );

  @override
  void didChangePlatformBrightness() => _readBrightness();

  @override
  void onWindowClose() => state.requestQuit();

  void _onState() {
    if (state.title != _title) {
      _title = state.title;
      windowManager.setTitle(_title);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dark = state.dark;
    return MaterialApp(
      title: 'writestuff',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(dark),
      home: Home(state: state),
    );
  }
}
