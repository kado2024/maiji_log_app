import 'sky.dart';

/// A "定点時刻": one fixed time of day the user records every day.
class Spot {
  final int id;
  final String name;
  final int minute; // minutes since midnight, 0..1439

  const Spot({required this.id, required this.name, required this.minute});

  int get hour => minute ~/ 60;
  String get timeLabel => clockLabel(minute);

  /// Fractional hour, used for the sky color.
  double get skyHour => minute / 60;

  Spot copyWith({String? name, int? minute}) => Spot(id: id, name: name ?? this.name, minute: minute ?? this.minute);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'minute': minute};

  factory Spot.fromJson(Map<String, dynamic> j) =>
      Spot(id: j['id'] as int, name: (j['name'] as String?) ?? '', minute: (j['minute'] as int) % 1440);
}

/// The one short clip recorded for a spot on a given day.
class DayClip {
  final int spotId;
  final String date; // yyyy-MM-dd (the day the time slot belongs to)
  final String video; // file name inside the store folder ('' for sample frames)
  final String thumb; // file name inside the store folder ('' if none)
  final int createdAt;
  final int? sampleMonth; // 1..12, set only for the built-in sample

  const DayClip({
    required this.spotId,
    required this.date,
    required this.video,
    required this.thumb,
    required this.createdAt,
    this.sampleMonth,
  });

  String get id => '${spotId}_$date';
  bool get isSample => sampleMonth != null;

  Map<String, dynamic> toJson() => {
        'spot': spotId,
        'date': date,
        'video': video,
        'thumb': thumb,
        'createdAt': createdAt,
      };

  factory DayClip.fromJson(Map<String, dynamic> j) => DayClip(
        spotId: j['spot'] as int,
        date: j['date'] as String,
        video: j['video'] as String,
        thumb: (j['thumb'] as String?) ?? '',
        createdAt: (j['createdAt'] as int?) ?? 0,
      );
}

const kMaxSpots = 3;

/// Built-in example: the window at 6:30, once a month for a year.
const kSampleSpot = Spot(id: -1, name: '見本：6:30の窓', minute: 6 * 60 + 30);

final List<DayClip> sampleClips = [
  for (var m = 1; m <= 12; m++)
    DayClip(
      spotId: kSampleSpot.id,
      date: '2025-${two(m)}-15',
      video: '',
      thumb: '',
      createdAt: 0,
      sampleMonth: m,
    ),
];

/// Name ideas shown when adding a spot.
const kSpotNameIdeas = ['窓の外', 'ベランダの植物', '朝の鏡', '机の上', 'いつもの帰り道', '寝る前の部屋'];
