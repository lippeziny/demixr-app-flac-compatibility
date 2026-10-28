import 'package:dartz/dartz.dart';
import 'package:demixr_app/models/failure/failure.dart';
import 'package:demixr_app/models/failure/no_song_selected.dart';
import 'package:file_picker/file_picker.dart';

class SongLoader {
  Future<Either<Failure, PlatformFile>> getFromDevice() async {
    FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac'],
      // Keep a byte fallback for Android's Storage Access Framework, where
      // some providers (cloud drives and document providers) do not expose a
      // stable filesystem path.
      withData: true,
    );

    if (result == null) return Left(NoSongSelected());

    PlatformFile file = result.files.single;
    return Right(file);
  }
}
