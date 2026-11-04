import 'package:flutter/foundation.dart';

import '../../core/errors/app_exception.dart';
import '../../core/utils/app_logger.dart';
import '../../database/models/clip_candidate.dart';
import '../../database/repositories/clip_candidate_repository.dart';
import 'clip_range.dart';

/// State layar review kandidat clip. Semua data dari SQLite lokal.
class ClipReviewController extends ChangeNotifier {
  ClipReviewController({
    required ClipCandidateRepository repository,
    required this.projectId,
    required this.videoDurationMs,
  }) : _repo = repository;

  final ClipCandidateRepository _repo;
  final int projectId;
  final int videoDurationMs;

  List<ClipCandidate> _items = const [];
  bool _loading = true;
  String? _error;

  List<ClipCandidate> get items => _items;
  bool get loading => _loading;
  String? get error => _error;

  int _count(CandidateStatus s) => _items.where((c) => c.status == s).length;
  int get acceptedCount => _count(CandidateStatus.accepted);
  int get rejectedCount => _count(CandidateStatus.rejected);
  int get pendingCount => _count(CandidateStatus.pending);

  Future<void> load() async {
    try {
      _items = await _repo.getByProject(projectId);
      _error = null;
    } catch (e, st) {
      AppLogger.e('Gagal memuat kandidat', e, st);
      _error = 'Kandidat clip tidak dapat dimuat.';
    }
    _loading = false;
    notifyListeners();
  }

  /// Menetapkan status. Memilih status yang sama lagi mengembalikannya ke
  /// `pending` (toggle). Kandidat `generated` tidak dapat diubah.
  Future<void> setStatus(ClipCandidate c, CandidateStatus status) async {
    if (c.status == CandidateStatus.generated) return;
    final next = c.status == status ? CandidateStatus.pending : status;
    await _repo.updateStatus(c.id!, next);
    await load();
  }

  Future<void> setAll(CandidateStatus status) async {
    await _repo.setStatusForProject(projectId, status);
    await load();
  }

  /// Menyimpan hasil edit. Melempar [AppException] bila tidak valid.
  Future<void> saveEdit(
    ClipCandidate c, {
    required int startMs,
    required int endMs,
    required String title,
  }) async {
    final t = title.trim();
    if (t.isEmpty) {
      throw const AppException('Judul tidak boleh kosong.', code: 'empty_title');
    }
    final r = normalizeRange(
      startMs: startMs,
      endMs: endMs,
      videoDurationMs: videoDurationMs,
    );
    await _repo.updateDetails(c.id!,
        startMs: r.startMs, endMs: r.endMs, title: t);
    await load();
  }
}
