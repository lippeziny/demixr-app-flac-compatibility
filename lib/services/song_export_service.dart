import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../models/unmixed_song.dart';
import '../utils.dart';

/// Exports audio in FLAC. FLAC is a lossless codec for the 24-bit PCM data
/// produced by Demixr; the AI source-separation process itself is not reversible.
class SongExportService {
  Future<bool> exportOriginal(UnmixedSong song) => _exportFlac(
    File(song.mixture),
    '${sanitizeFilename(song.title)} - original.flac',
  );

  Future<bool> exportStem(UnmixedSong song, Stem stem) => _exportFlac(
    File(song.getStem(stem)),
    '${sanitizeFilename(song.title)} - ${stem.value}.flac',
  );

  Future<bool> exportRemix(UnmixedSong song, Map<Stem, double> volumes) async {
    final gains = <Stem, double>{
      for (final stem in song.stems) stem: (volumes[stem] ?? 1).clamp(0, 1),
    };
    final output = File(
      p.join(
        (await getTemporaryDirectory()).path,
        '${sanitizeFilename(song.title)}-remix-${DateTime.now().microsecondsSinceEpoch}.flac',
      ),
    );
    final inputs = <String>[];
    final labels = <String>[];
    for (var index = 0; index < song.stems.length; index++) {
      final stem = song.stems[index];
      inputs.add('-i ${_quote(song.getStem(stem))}');
      labels.add('[$index:a]');
    }
    final weights = song.stems
        .map((stem) => gains[stem]!.toStringAsFixed(4))
        .join(' ');
    final filter =
        '${labels.join()}amix=inputs=${song.stems.length}:weights='
        "'$weights':normalize=0:dropout_transition=0[out]";
    final session = await FFmpegKit.execute(
      '-y ${inputs.join(' ')} -filter_complex ${_quote(filter)} '
      '-map "[out]" -c:a flac -compression_level 8 '
      '-sample_fmt s32 -bits_per_raw_sample 24 ${_quote(output.path)}',
    );
    final returnCode = await session.getReturnCode();
    if (!ReturnCode.isSuccess(returnCode)) {
      await output.deleteIfExists();
      throw StateError('Could not render the FLAC remix.');
    }

    final profile = song.stems.map((stem) {
      final percentage = (gains[stem]! * 100).round();
      return '${stem.value}$percentage';
    }).join('-');
    try {
      return await _saveFile(
        output,
        '${sanitizeFilename(song.title)} - remix-$profile.flac',
      );
    } finally {
      await output.deleteIfExists();
    }
  }

  Future<bool> exportAllStems(UnmixedSong song) async {
    final tempDir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final output = File(
      p.join(
        tempDir.path,
        '${sanitizeFilename(song.title)}-stems-$stamp.zip',
      ),
    );
    final encodedFiles = <File>[];
    final encoder = ZipFileEncoder()..create(output.path);
    try {
      for (final stem in song.stems) {
        final flac = await _createFlac(
          File(song.getStem(stem)),
          outputPath: p.join(tempDir.path, 'demixr-$stamp-${stem.value}.flac'),
        );
        encodedFiles.add(flac);
        await encoder.addFile(flac, '${stem.value}.flac');
      }
      final original = await _createFlac(
        File(song.mixture),
        outputPath: p.join(tempDir.path, 'demixr-$stamp-original.flac'),
      );
      encodedFiles.add(original);
      await encoder.addFile(original, 'original.flac');
    } finally {
      await encoder.close();
      for (final file in encodedFiles) {
        await file.deleteIfExists();
      }
    }

    try {
      return await _saveFile(
        output,
        '${sanitizeFilename(song.title)} - stems.zip',
      );
    } finally {
      await output.deleteIfExists();
    }
  }

  Future<bool> _exportFlac(File input, String destinationName) async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final flac = await _createFlac(
      input,
      outputPath: p.join(
        (await getTemporaryDirectory()).path,
        'demixr-export-$stamp.flac',
      ),
    );
    try {
      return await _saveFile(flac, destinationName);
    } finally {
      await flac.deleteIfExists();
    }
  }

  /// Encodes PCM to FLAC. The FLAC stream preserves the 24-bit PCM samples;
  /// unlike MP3/AAC, FLAC does not add perceptual/lossy compression artifacts.
  Future<File> _createFlac(File source, {required String outputPath}) async {
    final output = File(outputPath);
    await output.deleteIfExists();
    final session = await FFmpegKit.execute(
      '-y -i ${_quote(source.path)} -map 0:a:0 -vn -c:a flac '
      '-compression_level 8 -sample_fmt s32 -bits_per_raw_sample 24 '
      '${_quote(output.path)}',
    );
    if (!ReturnCode.isSuccess(await session.getReturnCode()) ||
        !await output.exists() ||
        await output.length() == 0) {
      await output.deleteIfExists();
      throw StateError('Could not encode audio as FLAC.');
    }
    return output;
  }

  Future<bool> _saveFile(File source, String fileName) async {
    final path = await FilePicker.saveFile(
      dialogTitle: 'Export from Demixr',
      fileName: fileName,
      bytes: Platform.isAndroid || Platform.isIOS
          ? await source.readAsBytes()
          : null,
    );
    if (path == null) return false;
    if (!Platform.isAndroid && !Platform.isIOS) {
      if (p.equals(source.path, path)) return true;
      await source.copy(path);
    }
    return true;
  }

  String _quote(String value) => '"${value.replaceAll('"', '\\"')}"';
}
