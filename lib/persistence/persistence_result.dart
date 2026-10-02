import 'keep_my_car_data_mapper.dart';

enum PersistenceStage {
  busy,
  encode,
  prepare,
  writeTemp,
  verifyTemp,
  readCurrent,
  readBackup,
  backupCurrent,
  promoteTemp,
  verifyCurrent,
  rollback,
  discard,
}

/// Stage plus the original exception distinguish I/O, JSON/version and domain
/// validation failures without losing platform-specific diagnostics.
class PersistenceIssue {
  const PersistenceIssue(this.stage, this.cause, this.stackTrace);
  final PersistenceStage stage;
  final Object cause;
  final StackTrace stackTrace;
}

sealed class LoadResult {
  const LoadResult();
}

class NoData extends LoadResult {
  const NoData();
}

class Loaded extends LoadResult {
  const Loaded(this.data);
  final RestoredCarData data;
}

class Recovered extends LoadResult {
  const Recovered(this.data, {this.currentIssue});
  final RestoredCarData data;
  // Null when current was absent, otherwise why it could not be used.
  final PersistenceIssue? currentIssue;
}

class LoadFailure extends LoadResult {
  LoadFailure(List<PersistenceIssue> issues)
    : issues = List.unmodifiable(issues);
  final List<PersistenceIssue> issues;
}

sealed class SaveResult {
  const SaveResult();
}

class Saved extends SaveResult {
  const Saved();
}

class SaveFailure extends SaveResult {
  SaveFailure(this.issue, {List<PersistenceIssue> rollbackIssues = const []})
    : rollbackIssues = List.unmodifiable(rollbackIssues);
  final PersistenceIssue issue;
  final List<PersistenceIssue> rollbackIssues;
}
