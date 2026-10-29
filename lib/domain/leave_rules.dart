import 'models.dart';

/// Inclusive calendar days (weekends and holidays count).
int leaveDays(String start, String end) => DateTime.parse(end).difference(DateTime.parse(start)).inDays + 1;

bool overlaps(String start, String end, LeaveRequest r) => start.compareTo(r.endDate) <= 0 && end.compareTo(r.startDate) >= 0;

/// Returns the first validation error, or null when the request is valid.
/// Dates are company-local YYYY-MM-DD strings, so string order is date order.
String? validateLeave({
  required LeaveType? type,
  required String? start,
  required String? end,
  required String reason,
  required String today,
  required Map<LeaveType, int> available,
  required List<LeaveRequest> existing,
}) {
  if (type == null) return 'Choose a leave type.';
  if (start == null || end == null) return 'Choose start and end dates.';
  if (start.compareTo(today) < 0) return 'Start date cannot be before today ($today).';
  if (end.compareTo(start) < 0) return 'End date cannot be before the start date.';
  if (reason.replaceAll(RegExp(r'\s'), '').length < 10) return 'Reason must contain at least 10 non-whitespace characters.';
  final days = leaveDays(start, end);
  final balance = available[type] ?? 0;
  if (days > balance) return 'You requested $days days but only $balance ${type.name} days are available.';
  final clash = existing.where((r) => r.status != LeaveStatus.rejected && overlaps(start, end, r)).firstOrNull;
  if (clash != null) return 'Dates overlap your ${clash.status.name} request ${clash.startDate} – ${clash.endDate}.';
  return null;
}
