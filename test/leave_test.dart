import 'package:flutter_test/flutter_test.dart';
import 'package:rebs_workspace/domain/leave_rules.dart';
import 'package:rebs_workspace/domain/models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support.dart';

void main() {
  const existing = [
    LeaveRequest(id: '1', type: LeaveType.casual, startDate: '2026-11-10', endDate: '2026-11-12', reason: 'Family trip abroad', status: LeaveStatus.pending),
    LeaveRequest(id: '2', type: LeaveType.sick, startDate: '2026-11-20', endDate: '2026-11-20', reason: 'Medical checkup', status: LeaveStatus.rejected),
  ];

  String? validate(String start, String end, {String reason = 'Visiting family', int balance = 10}) => validateLeave(
      type: LeaveType.casual, start: start, end: end, reason: reason, today: '2026-11-01',
      available: {LeaveType.casual: balance}, existing: existing);

  test('overlapping a pending or approved request is rejected', () {
    expect(validate('2026-11-12', '2026-11-14'), contains('overlap'));
    expect(validate('2026-11-08', '2026-11-10'), contains('overlap'));
    expect(validate('2026-11-13', '2026-11-14'), isNull); // adjacent is fine
    expect(validate('2026-11-20', '2026-11-20'), isNull); // rejected requests do not block
  });

  test('other leave rules', () {
    expect(validate('2026-10-31', '2026-11-02'), contains('before today'));
    expect(validate('2026-11-05', '2026-11-04'), contains('End date'));
    expect(validate('2026-11-05', '2026-11-05', reason: ' a b c d e f g h i '), contains('10 non-whitespace'));
    expect(validate('2026-11-01', '2026-11-03', balance: 2), contains('only 2'));
  });

  test('server validation error is surfaced even when local validation passes', () async {
    SharedPreferences.resetStatic();
    SharedPreferences.setMockInitialValues({});
    final backend = testBackend();
    final c = await makeController(backendClient(backend));
    await c.refresh();
    backend.scenario = 'leave_reject';
    final today = c.clock.today();
    final error = await c.submitLeave(requestId: 'r1', type: LeaveType.sick, start: today, end: today, reason: 'Fever and headache');
    expect(error, contains('pre-approval'));

    backend.scenario = 'ok';
    expect(await c.submitLeave(requestId: 'r1', type: LeaveType.sick, start: today, end: today, reason: 'Fever and headache'), isNull);
    expect(c.leaves.first.status, LeaveStatus.pending);
  });
}
