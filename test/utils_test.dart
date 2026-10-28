import 'package:demixr_app/utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RemoveExtension', () {
    test('removes supported audio extensions case-insensitively', () {
      expect('track.flac'.removeExtension(), 'track');
      expect('track.FLAC'.removeExtension(), 'track');
      expect('track.mp3'.removeExtension(), 'track');
      expect('track.wav'.removeExtension(), 'track');
    });

    test('does not remove dots that are part of the title', () {
      expect('live.session.track.flac'.removeExtension(), 'live.session.track');
    });
  });
}
