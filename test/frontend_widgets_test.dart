import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nebula/core/enums/track_source.dart';
import 'package:nebula/features/player/domain/entities/track.dart';
import 'package:nebula/shared/widgets/widgets.dart';

void main() {
  group('NebulaInput Widget Tests', () {
    testWidgets('Emits onChanged and onSubmitted callbacks correctly', (tester) async {
      final controller = TextEditingController();
      String? changedValue;
      String? submittedValue;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NebulaInput(
              label: 'TEST INPUT',
              controller: controller,
              onChanged: (val) => changedValue = val,
              onSubmitted: (val) => submittedValue = val,
            ),
          ),
        ),
      );

      expect(find.text('TEST INPUT'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'cyberpunk');
      expect(changedValue, 'cyberpunk');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      expect(submittedValue, 'cyberpunk');
    });
  });

  group('NebulaTrackTile Widget Tests', () {
    final testTrack = Track(
      id: 'test_track_1',
      title: 'Neon Nights',
      artist: 'Synthwave Boy',
      thumbnailUrl: '',
      duration: const Duration(minutes: 3),
      source: TrackSource.youtube,
    );

    testWidgets('Renders track title, artist, and index correctly', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NebulaTrackTile(
              track: testTrack,
              indexNumber: '01',
              isCurrentTrack: false,
              isPlaying: false,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('NEON NIGHTS'), findsOneWidget);
      expect(find.text('SYNTHWAVE BOY'), findsOneWidget);
      expect(find.text('01'), findsOneWidget);

      await tester.tap(find.text('NEON NIGHTS'));
      expect(tapped, isTrue);
    });

    testWidgets('Shows equalizer icon when active and playing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NebulaTrackTile(
              track: testTrack,
              isCurrentTrack: true,
              isPlaying: true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.equalizer), findsOneWidget);
    });

    testWidgets('Shows loading indicator when isLoading is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NebulaTrackTile(
              track: testTrack,
              isLoading: true,
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
