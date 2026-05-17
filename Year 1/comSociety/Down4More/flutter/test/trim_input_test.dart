import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:down4more/widgets/trim_input.dart';

void main() {
  group('formatDigitsAsTime — pure digit string', () {
    test('empty', () {
      expect(formatDigitsAsTime(''), '');
    });
    test('1 digit → 0:0X', () {
      expect(formatDigitsAsTime('5'), '0:05');
    });
    test('2 digits → 0:XX (no leading zero on minutes)', () {
      expect(formatDigitsAsTime('55'), '0:55');
    });
    test('3 digits → M:SS (no leading zero on minutes)', () {
      expect(formatDigitsAsTime('551'), '5:51');
    });
    test('4 digits → MM:SS', () {
      expect(formatDigitsAsTime('5512'), '55:12');
    });
    test('5 digits → H:MM:SS (no leading zero on hours)', () {
      expect(formatDigitsAsTime('55120'), '5:51:20');
    });
    test('6 digits → HH:MM:SS', () {
      expect(formatDigitsAsTime('551209'), '55:12:09');
    });
  });

  /// The spec from the test plan T3 is keystroke-driven: the user types
  /// digits one at a time and the field should land on the formats above.
  /// This exercises [DigitShiftFormatter.formatEditUpdate] which is what
  /// actually runs at runtime — pure [formatDigitsAsTime] doesn't catch
  /// regressions caused by the formatter re-feeding its own output back in
  /// (the leading-zero round-trip bug).
  group('DigitShiftFormatter — keystroke sequence', () {
    String type(String previousFormatted, String newKey) {
      // Simulate Flutter calling formatEditUpdate with the new keystroke
      // appended to the previously-formatted text (cursor at end).
      const formatter = DigitShiftFormatter();
      final newText = '$previousFormatted$newKey';
      final result = formatter.formatEditUpdate(
        TextEditingValue(text: previousFormatted),
        TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        ),
      );
      return result.text;
    }

    String backspace(String previousFormatted) {
      // Simulate a single backspace at the end of the field — Flutter
      // delivers a newValue with one less character.
      const formatter = DigitShiftFormatter();
      final newText = previousFormatted.isEmpty
          ? ''
          : previousFormatted.substring(0, previousFormatted.length - 1);
      final result = formatter.formatEditUpdate(
        TextEditingValue(text: previousFormatted),
        TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        ),
      );
      return result.text;
    }

    test('typing 5 5 1 2 0 9 lands on each spec state in turn', () {
      var v = '';
      v = type(v, '5');
      expect(v, '0:05', reason: 'after typing 5');
      v = type(v, '5');
      expect(v, '0:55', reason: 'after typing 5,5 (NOT 00:55)');
      v = type(v, '1');
      expect(v, '5:51', reason: 'after typing 5,5,1 (NOT 0:05:51)');
      v = type(v, '2');
      expect(v, '55:12', reason: 'after typing 5,5,1,2 (NOT 00:55:12)');
      v = type(v, '0');
      expect(v, '5:51:20', reason: 'after typing 5,5,1,2,0 (NOT 05:51:20)');
      v = type(v, '9');
      expect(v, '55:12:09', reason: 'after typing 5,5,1,2,0,9');
    });

    test('backspace removes one digit at a time', () {
      // Set up the field at 55:12:09 by typing all 6 digits.
      var v = '';
      for (final d in '551209'.split('')) {
        v = type(v, d);
      }
      expect(v, '55:12:09');

      v = backspace(v);
      expect(v, '5:51:20');
      v = backspace(v);
      expect(v, '55:12');
      v = backspace(v);
      expect(v, '5:51');
      v = backspace(v);
      expect(v, '0:55');
      v = backspace(v);
      expect(v, '0:05');
      v = backspace(v);
      expect(v, '');
    });

    test('non-digits are ignored', () {
      // Real keyboards filter non-digits via the platform input mode,
      // but a paste might deliver "abc". Verify we end up with empty/no
      // state.
      var v = '';
      v = type(v, 'a');
      expect(v, '');
      v = type(v, 'bc');
      expect(v, '');
    });

    test('caps at 6 digits (oldest digit drops off the front)', () {
      // After 7 keystrokes the field should still represent at most 6
      // digits — the leftmost (oldest) one falls off.
      var v = '';
      for (final d in '1234567'.split('')) {
        v = type(v, d);
      }
      // Final 6 digits = 234567 → 23:45:67 (well, 23:45:67 isn't a valid
      // time but the formatter is purely structural).
      expect(v, '23:45:67');
    });
  });
}
