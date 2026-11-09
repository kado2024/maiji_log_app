import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'model.dart';

/// Text of the daily reminder for a spot.
({String title, String body}) reminderText(Spot s) =>
    (title: '${s.timeLabel}「${s.name}」の時間です', body: '前回と同じ構図で、今日の${s.name}を2秒だけ残しましょう。');

/// One daily local notification per spot, exactly at the spot's time.
class SpotReminders extends ChangeNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool enabled = false;
  bool _ready = false;

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      tz.setLocalLocation(tz.getLocation('Asia/Tokyo'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    final p = await SharedPreferences.getInstance();
    enabled = p.getBool('spotNotify') ?? false;
    _ready = true;
    notifyListeners();
  }

  /// Asks for permission (first time only) and turns reminders on.
  Future<bool> enable(List<Spot> spots) async {
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final ok = await ios?.requestPermissions(alert: true, sound: true, badge: false) ?? false;
    enabled = ok;
    await _persist();
    await reschedule(spots);
    return ok;
  }

  Future<void> disable() async {
    enabled = false;
    await _persist();
    if (_ready) await _plugin.cancelAll();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('spotNotify', enabled);
    notifyListeners();
  }

  Future<void> reschedule(List<Spot> spots) async {
    if (!_ready) return;
    await _plugin.cancelAll();
    if (!enabled) return;
    final now = tz.TZDateTime.now(tz.local);
    for (final s in spots) {
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, s.hour, s.minute % 60);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      final t = reminderText(s);
      await _plugin.zonedSchedule(
        id: s.id,
        scheduledDate: at,
        title: t.title,
        body: t.body,
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }
}
