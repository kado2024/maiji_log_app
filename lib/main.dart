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
  final store = SpotStore();
  final reminders = SpotReminders();
  await Future.wait([store.load(), reminders.init()]);
  // Keep the daily schedule fresh (time zone changes, app updates).
  if (reminders.enabled) await reminders.reschedule(store.spots);
  // Re-schedule whenever a spot is added, removed, renamed or moved.
  var sig = spotSignature(store);
  store.addListener(() {
    final now = spotSignature(store);
    if (now == sig) return;
    sig = now;
    reminders.reschedule(store.spots);
  });
  runApp(OnajiApp(store: store, reminders: reminders));
}

String spotSignature(SpotStore s) => s.spots.map((x) => '${x.id}:${x.minute}:${x.name}').join('|');

class OnajiApp extends StatelessWidget {
  const OnajiApp({super.key, required this.store, required this.reminders, this.clock});
  final SpotStore store;
  final SpotReminders reminders;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppName,
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
