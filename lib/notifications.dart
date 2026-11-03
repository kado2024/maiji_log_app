import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'sky.dart';

/// Hourly "a new slot opened" reminders, scheduled as daily repeating
/// local notifications at hh:00 within the user's chosen hours.
class HourlyReminders extends ChangeNotifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool enabled = false;
  int startHour = 8;
  int endHour = 23; // inclusive

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
    enabled = p.getBool('notify') ?? false;
    startHour = p.getInt('notifyStart') ?? 8;
    endHour = p.getInt('notifyEnd') ?? 23;
    notifyListeners();
  }

  /// Asks for permission (first time only) and turns reminders on.
  Future<bool> enable() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    final ok = await ios?.requestPermissions(alert: true, sound: true, badge: false) ?? false;
    enabled = ok;
    await _persist();
    await reschedule();
    return ok;
  }

  Future<void> disable() async {
    enabled = false;
    await _persist();
    await _plugin.cancelAll();
  }

  Future<void> setRange(int start, int end) async {
    startHour = start;
    endHour = end;
    await _persist();
    await reschedule();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('notify', enabled);
    await p.setInt('notifyStart', startHour);
    await p.setInt('notifyEnd', endHour);
    notifyListeners();
  }

  Future<void> reschedule() async {
    await _plugin.cancelAll();
    if (!enabled) return;
    final now = tz.TZDateTime.now(tz.local);
    for (var h = startHour; h <= endHour; h++) {
      var at = tz.TZDateTime(tz.local, now.year, now.month, now.day, h);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      await _plugin.zonedSchedule(
        id: h,
        scheduledDate: at,
        title: '${two(h)}:00 の枠が開きました',
        body: 'この1時間の1コマを撮ろう。お題：${promptFor('notify', h)}',
        notificationDetails: const NotificationDetails(
          iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    }
  }
}
