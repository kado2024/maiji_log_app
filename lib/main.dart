import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'notifications.dart';
import 'screens/home.dart';
import 'store.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final store = ClipStore();
  final reminders = HourlyReminders();
  await Future.wait([store.load(), reminders.init()]);
  // Keep the daily schedule fresh (time zone changes, app updates).
  if (reminders.enabled) reminders.reschedule();
  runApp(MaijiLogApp(store: store, reminders: reminders));
}

class MaijiLogApp extends StatelessWidget {
  const MaijiLogApp({super.key, required this.store, required this.reminders, this.clock});
  final ClipStore store;
  final HourlyReminders reminders;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '毎時ログ',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('ja'),
      supportedLocales: const [Locale('ja')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: HomeScreen(store: store, reminders: reminders, clock: clock ?? DateTime.now),
    );
  }
}
