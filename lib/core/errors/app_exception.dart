/// Exception aplikasi dengan pesan yang aman ditampilkan ke pengguna.
/// Stack trace tidak pernah ditampilkan di UI.
class AppException implements Exception {
  const AppException(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() => 'AppException(${code ?? '-'}): $message';
}

class StorageException extends AppException {
  const StorageException(super.message, {super.code, super.cause});
}

class InsufficientStorageException extends StorageException {
  const InsufficientStorageException(
      [String message = 'Storage tidak cukup untuk membuat clip.'])
      : super(message, code: 'insufficient_storage');
}
