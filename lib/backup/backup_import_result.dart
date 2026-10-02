import '../persistence/keep_my_car_data_mapper.dart';

enum BackupImportIssue {
  notBackup,
  unsupportedVersion,
  invalidStructure,
  invalidContent,
}

sealed class BackupImportResult {
  const BackupImportResult();
}

/// A fully validated candidate, not a saved or adopted application state.
class BackupImportSuccess extends BackupImportResult {
  const BackupImportSuccess(this.data);

  final RestoredCarData data;
}

class BackupImportFailure extends BackupImportResult {
  const BackupImportFailure(this.issue);

  final BackupImportIssue issue;
}
