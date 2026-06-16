/// 관리자 대시보드 집계(AdminDashboardRepository.aggregate) 단위 테스트.
///
/// 매출/노쇼율/활성 회원/만료 임박은 "어긋나면 베타 중단" 급 매출 직결 수치라
/// CLAUDE.md §5.1 에 따라 순수 함수로 분리해 시점 고정 테스트한다.
/// (Supabase 의존 없이 view 행 모델만으로 검증)
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:gyman/features/admin/dashboard/admin_dashboard_repository.dart';

void main() {
  // 모든 테스트의 "오늘" 고정 — 만료 임박/활성 판정의 기준일.
  final now = DateTime(2026, 6, 16);

  /// 테스트용 계약 행 빌더. 필요한 필드만 덮어쓰고 나머지는 무난한 기본값.
  AdminContractRow row({
    String contractId = 'c1',
    String memberId = 'm1',
    String memberName = '회원',
    String trainerId = 't1',
    String? trainerName = '트레이너',
    int total = 10,
    int used = 0,
    int remaining = 10,
    DateTime? start,
    DateTime? end,
    int? price = 100000,
    int done = 0,
    int noShow = 0,
  }) {
    return AdminContractRow(
      contractId: contractId,
      memberId: memberId,
      memberName: memberName,
      trainerId: trainerId,
      trainerName: trainerName,
      totalSessions: total,
      usedSessions: used,
      remainingSessions: remaining,
      startDate: start ?? DateTime(2026, 1, 1),
      endDate: end,
      price: price,
      doneCount: done,
      noShowCount: noShow,
    );
  }

  group('센터 요약', () {
    test('빈 입력 → 모든 지표 0, isEmpty', () {
      final data = AdminDashboardRepository.aggregate([], now);
      expect(data.summary.activeMemberCount, 0);
      expect(data.summary.activeContractCount, 0);
      expect(data.summary.totalRevenue, 0);
      expect(data.summary.noShowRate, 0);
      expect(data.isEmpty, isTrue);
    });

    test('매출은 모든 계약 price 합 (null price 는 0 취급)', () {
      final data = AdminDashboardRepository.aggregate([
        row(contractId: 'c1', price: 300000),
        row(contractId: 'c2', price: null),
        row(contractId: 'c3', price: 200000),
      ], now);
      expect(data.summary.totalRevenue, 500000);
    });

    test('노쇼율 = 노쇼 수 / 차감 수업(used) 합', () {
      final data = AdminDashboardRepository.aggregate([
        row(contractId: 'c1', used: 8, noShow: 2),
        row(contractId: 'c2', used: 12, noShow: 3),
      ], now);
      // (2+3) / (8+12) = 5/20 = 0.25
      expect(data.summary.noShowRate, closeTo(0.25, 1e-9));
    });

    test('차감 수업이 0이면 노쇼율 0 (0 나누기 방지)', () {
      final data = AdminDashboardRepository.aggregate([
        row(used: 0, noShow: 0),
      ], now);
      expect(data.summary.noShowRate, 0);
    });

    test('활성 회원 — 같은 회원의 활성 계약 2건은 1명으로 집계', () {
      final data = AdminDashboardRepository.aggregate([
        row(contractId: 'c1', memberId: 'm1', remaining: 5),
        row(contractId: 'c2', memberId: 'm1', remaining: 3),
      ], now);
      expect(data.summary.activeMemberCount, 1);
      expect(data.summary.activeContractCount, 2);
    });

    test('소진(잔여 0)·만료 지난 계약은 활성에서 제외', () {
      final data = AdminDashboardRepository.aggregate([
        row(contractId: 'c1', memberId: 'm1', remaining: 0), // 소진
        row(
          contractId: 'c2',
          memberId: 'm2',
          remaining: 5,
          end: DateTime(2026, 6, 1), // 오늘(6/16)보다 과거 → 만료
        ),
        row(contractId: 'c3', memberId: 'm3', remaining: 5), // 활성
      ], now);
      expect(data.summary.activeContractCount, 1);
      expect(data.summary.activeMemberCount, 1);
    });
  });

  group('트레이너별 성과', () {
    test('trainer_id 로 묶어 합산하고 매출 내림차순 정렬', () {
      final data = AdminDashboardRepository.aggregate([
        row(trainerId: 't1', trainerName: 'A', memberId: 'm1', price: 100000,
            done: 3, used: 4, noShow: 1),
        row(trainerId: 't1', trainerName: 'A', memberId: 'm2', price: 100000,
            done: 2, used: 2, noShow: 0),
        row(trainerId: 't2', trainerName: 'B', memberId: 'm3', price: 500000,
            done: 1, used: 1, noShow: 0),
      ], now);

      expect(data.trainerStats.length, 2);
      // 매출 큰 B(50만) 가 먼저.
      expect(data.trainerStats.first.trainerName, 'B');

      final a = data.trainerStats.firstWhere((s) => s.trainerId == 't1');
      expect(a.memberCount, 2); // m1, m2
      expect(a.doneCount, 5); // 3 + 2
      expect(a.revenue, 200000);
      // 노쇼 1 / 차감 6(4+2) ≈ 0.1667
      expect(a.noShowRate, closeTo(1 / 6, 1e-9));
    });
  });

  group('만료 임박', () {
    test('잔여 3회 이하 또는 만료 14일 이내만, 잔여 적은 순 정렬', () {
      final data = AdminDashboardRepository.aggregate([
        row(contractId: 'far', remaining: 8), // 제외: 잔여 많고 만료 미정
        row(contractId: 'low2', remaining: 2), // 포함: 잔여 적음
        row(contractId: 'low0', remaining: 0), // 포함: 소진
        row(
          contractId: 'soon',
          remaining: 9,
          end: DateTime(2026, 6, 20), // 4일 뒤 → 만료 임박
        ),
      ], now);

      final ids = data.expiring.map((r) => r.contractId).toList();
      expect(ids.contains('far'), isFalse);
      expect(ids.contains('low2'), isTrue);
      expect(ids.contains('low0'), isTrue);
      expect(ids.contains('soon'), isTrue);
      // 잔여 적은 순: low0(0) → low2(2) → soon(9)
      expect(ids, ['low0', 'low2', 'soon']);
    });

    test('이미 지난 만료일은 날짜 기준 임박에 안 잡힘(잔여 많으면 제외)', () {
      final data = AdminDashboardRepository.aggregate([
        row(contractId: 'expired', remaining: 9, end: DateTime(2026, 6, 1)),
      ], now);
      expect(data.expiring, isEmpty);
    });
  });
}
