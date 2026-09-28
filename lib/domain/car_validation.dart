enum CarNameError { required, tooLong, invalidCharacters }

/// Shared normalization and validation for the editor and formal app update.
({String name, CarNameError? error}) validateCarName(String input) {
  final name = input.trim();
  return (
    name: name,
    error: RegExp(r'[\r\n\t]').hasMatch(input)
        ? CarNameError.invalidCharacters
        : name.isEmpty
        ? CarNameError.required
        : name.runes.length > 40
        ? CarNameError.tooLong
        : null,
  );
}
