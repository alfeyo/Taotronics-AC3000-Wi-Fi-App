const zoneIndexByOffset = {
  '-12:00': 0,
  '-11:00': 1,
  '-10:00': 2,
  '-09:30': 4,
  '-09:00': 5,
  '-08:00': 7,
  '-07:00': 10,
  '-06:00': 13,
  '-05:00': 18,
  '-04:00': 24,
  '-03:30': 31,
  '-03:00': 32,
  '-02:00': 40,
  '-01:00': 42,
  '+00:00': 45,
  '+01:00': 48,
  '+02:00': 54,
  '+03:00': 66,
  '+03:30': 72,
  '+04:00': 73,
  '+04:30': 80,
  '+05:00': 81,
  '+05:30': 84,
  '+05:45': 86,
  '+06:00': 87,
  '+06:30': 90,
  '+07:00': 91,
  '+08:00': 97,
  '+08:30': 103,
  '+08:45': 104,
  '+09:00': 105,
  '+09:30': 109,
  '+10:00': 111,
  '+10:30': 116,
  '+11:00': 117,
  '+12:00': 123,
  '+12:45': 128,
  '+13:00': 129,
  '+14:00': 131,
};

int timeZoneIndexForOffset(Duration offset) {
  final hours = offset.inMilliseconds / 3600000.0;
  final whole = hours.truncate();
  final minutes = ((hours - whole).abs() * 60).round();
  final sign = whole < 0 ? '-' : '+';
  final hh = whole.abs().toString().padLeft(2, '0');
  final withMinutes =
      zoneIndexByOffset['$sign$hh:${minutes.toString().padLeft(2, '0')}'];
  if (withMinutes != null) return withMinutes;
  final wholeHour = zoneIndexByOffset['$sign$hh:00'];
  if (wholeHour != null) return wholeHour;
  return 0;
}

const countryCodeByLocale = {
  'us': 0,
  'en': 1,
  'cn': 2,
  'zh': 3,
  'ca': 4,
  'de': 5,
  'gb': 6,
  'ja': 7,
  'jp': 8,
  'jpn': 9,
};

int countryCodeForLocaleName(String localeName) {
  final parts = localeName.split(RegExp('[_-]'));
  if (parts.length > 1) {
    final country = parts.last.toLowerCase();
    final mapped = countryCodeByLocale[country];
    if (mapped != null) return mapped;
  }
  final language = parts.first.toLowerCase();
  return countryCodeByLocale[language] ?? -1;
}
