import '../../database/models/project.dart';

String projectStatusLabel(ProjectStatus status) {
  switch (status) {
    case ProjectStatus.created:
      return 'Baru';
    case ProjectStatus.videoAdded:
      return 'Video siap';
    case ProjectStatus.transcribing:
      return 'Transcribing';
    case ProjectStatus.transcribed:
      return 'Transcript siap';
    case ProjectStatus.analyzing:
      return 'Menganalisis';
    case ProjectStatus.analyzed:
      return 'Kandidat siap';
    case ProjectStatus.rendering:
      return 'Rendering';
    case ProjectStatus.completed:
      return 'Selesai';
    case ProjectStatus.failed:
      return 'Gagal';
  }
}
