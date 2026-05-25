/// 수업 1건 — 예약·실행·차감 모두 추적.
///
/// **Session vs SessionRecord 분리:**
///   - Session: 예약/상태 추적 (모든 sessions가 가짐)
///   - SessionRecord: 운동 내용 본문 (done 상태에서만 생성)
///   - 노쇼/취소된 수업은 Session만 있고 SessionRecord는 없음
///
/// 본 도메인은 잔여 횟수/재등록 계산만 다루므로 SessionRecord는 정의하지 않는다
/// (data 계층 모델로 충분 — 도메인 로직이 본문에 의존하지 않음).
///
/// 참고: docs/data_model.md §2.2 sessions / session_records 분리 이유.
library;

import 'enums.dart';

class Session {
  /// 수업 ID.
  final String id;

  /// 소속 계약 ID (FK: pt_contracts.id).
  final String contractId;

  /// 예약 일시 (실제 진행 시각이기도 함 — 변경되면 update).
  final DateTime scheduledAt;

  /// 현재 상태. 차감 여부는 `status.deducts` 로 판정.
  final SessionStatus status;

  /// 기록 완료 시각. status가 done일 때만 채워짐.
  final DateTime? recordedAt;

  /// 기록한 트레이너 ID. 대리 기록 추적용 (계약 트레이너와 다를 수 있음).
  final String? recordedByTrainerId;

  /// 상태 변경 메모 (예: 취소 사유). session_records의 본문과는 별개 영역.
  final String? statusMemo;

  /// 행 생성 시각.
  final DateTime createdAt;

  const Session({
    required this.id,
    required this.contractId,
    required this.scheduledAt,
    required this.status,
    required this.createdAt,
    this.recordedAt,
    this.recordedByTrainerId,
    this.statusMemo,
  });

  /// 잔여 횟수에서 차감되는 수업인가.
  /// `status.deducts` 와 동일하지만, Session 객체를 받아서 쓰는 측 코드 가독성용 단축.
  bool get isDeducted => status.deducts;

  /// 실제로 진행되어 기록까지 완료된 수업인가.
  bool get isCompleted => status.isCompleted;

  Session copyWith({
    String? id,
    String? contractId,
    DateTime? scheduledAt,
    SessionStatus? status,
    DateTime? recordedAt,
    String? recordedByTrainerId,
    String? statusMemo,
    DateTime? createdAt,
  }) {
    return Session(
      id: id ?? this.id,
      contractId: contractId ?? this.contractId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
      status: status ?? this.status,
      recordedAt: recordedAt ?? this.recordedAt,
      recordedByTrainerId: recordedByTrainerId ?? this.recordedByTrainerId,
      statusMemo: statusMemo ?? this.statusMemo,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Session &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          contractId == other.contractId &&
          scheduledAt == other.scheduledAt &&
          status == other.status &&
          recordedAt == other.recordedAt &&
          recordedByTrainerId == other.recordedByTrainerId &&
          statusMemo == other.statusMemo &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        id,
        contractId,
        scheduledAt,
        status,
        recordedAt,
        recordedByTrainerId,
        statusMemo,
        createdAt,
      );

  @override
  String toString() =>
      'Session(id: $id, contract: $contractId, '
      'scheduled: $scheduledAt, status: ${status.name})';
}
