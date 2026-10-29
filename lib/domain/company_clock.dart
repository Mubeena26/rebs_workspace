/// Company time as a fixed UTC offset.
// shortcut: fixed offset, no DST; switch to package:timezone for DST regions.
class CompanyClock {
  CompanyClock(this.offsetHours, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  int offsetHours;
  final DateTime Function() _now;

  DateTime nowUtc() => _now().toUtc();

  /// Wall-clock time in the company timezone (a UTC DateTime shifted by the offset).
  DateTime local(DateTime utc) => utc.toUtc().add(Duration(hours: offsetHours));

  String dateOf(DateTime utc) => local(utc).toIso8601String().substring(0, 10);

  String today() => dateOf(nowUtc());
}
