/// One gate per formal state, shared by JSON and ZIP transfers. This never
/// locks ordinary editing while a picker/confirmation/worker is pending.
class BackupOperationGate {
  Object? _owner;
  bool acquire(Object owner) {
    if (_owner != null) return false;
    _owner = owner;
    return true;
  }

  void release(Object owner) {
    if (identical(_owner, owner)) _owner = null;
  }
}
