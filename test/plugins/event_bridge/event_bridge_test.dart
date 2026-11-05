// Unit tests for PlayerEvent.tryParse — covers all three event formats and
// guards against regressions of the broken "if (progress <= 1) *= 100"
// heuristic.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spovies/plugins/event_bridge/event_bridge.dart';

void main() {
  group('PlayerEvent.tryParse — PLAYER_EVENT format', () {
    test('parses standard timeupdate at 0-100 scale', () {
      final raw = jsonEncode({
        'type': 'PLAYER_EVENT',
        'data': {
          'event': 'timeupdate',
          'currentTime': 75.0,
          'duration': 150.0,
          'progress': 50.0,
        },
      });
      final ev = PlayerEvent.tryParse(raw);
      expect(ev, isNotNull);
      expect(ev!.eventType, 'timeupdate');
      expect(ev.currentTime, 75.0);
      expect(ev.duration, 150.0);
      // Critical: 50 stays 50, NOT 5000. The old downstream heuristic
      // mis-scaled values <= 1.0 by ×100.
      expect(ev.progress, 50.0);
    });

    test('computes progress when "progress" field is missing', () {
      final raw = jsonEncode({
        'type': 'PLAYER_EVENT',
        'data': {'event': 'timeupdate', 'currentTime': 30.0, 'duration': 120.0},
      });
      final ev = PlayerEvent.tryParse(raw)!;
      expect(ev.progress, 25.0);
    });

    test('treats a 1.0% reading as 1.0, never re-scaled to 100', () {
      // This is the exact case that broke the Next-Episode overlay before
      // the heuristic was removed: a real 1% progress that downstream
      // code multiplied to 100.
      final raw = jsonEncode({
        'type': 'PLAYER_EVENT',
        'data': {
          'event': 'timeupdate',
          'currentTime': 1.0,
          'duration': 100.0,
          'progress': 1.0,
        },
      });
      final ev = PlayerEvent.tryParse(raw)!;
      expect(ev.progress, 1.0);
    });
  });

  group('PlayerEvent.tryParse — flat channel format', () {
    test('parses channel + event + percent', () {
      final raw = jsonEncode({
        'channel': 'example-channel',
        'event': 'time',
        'time': 60.0,
        'duration': 200.0,
        'percent': 30.0,
      });
      final ev = PlayerEvent.tryParse(raw)!;
      expect(ev.eventType, 'timeupdate');
      expect(ev.currentTime, 60.0);
      expect(ev.duration, 200.0);
      expect(ev.progress, 30.0);
    });
  });

  group('PlayerEvent.tryParse — native time-event format', () {
    test('parses event/time/duration into 0-100 progress', () {
      final raw = jsonEncode({
        'event': 'time',
        'time': 50.0,
        'duration': 100.0,
      });
      final ev = PlayerEvent.tryParse(raw)!;
      expect(ev.eventType, 'timeupdate');
      expect(ev.progress, 50.0);
    });

    test('normalises userpause to "pause"', () {
      final raw = jsonEncode({
        'event': 'userpause',
        'time': 40.0,
        'duration': 80.0,
      });
      final ev = PlayerEvent.tryParse(raw)!;
      expect(ev.eventType, 'pause');
    });
  });

  group('PlayerEvent.tryParse — rejection', () {
    test('returns null for non-JSON gibberish', () {
      expect(PlayerEvent.tryParse('not json'), isNull);
    });

    test('returns null for unrecognised payload shape', () {
      expect(PlayerEvent.tryParse(jsonEncode({'foo': 'bar'})), isNull);
    });
  });
}
