import 'package:business_hub_mobile/core/region/gst_states.dart';
import 'package:flutter_test/flutter_test.dart';

/// The phone and the website must offer the same GST state codes.
///
/// This code decides CGST+SGST versus IGST on every bill. If the two platforms
/// disagreed about which codes exist, a shop registered on one could be taxed
/// differently from the same shop registered on the other.
void main() {
  group('kGstStates', () {
    test('every code keeps its leading zero', () {
      for (final s in kGstStates) {
        expect(s.code, matches(RegExp(r'^\d{2}$')), reason: s.name);
      }
    });

    test('no duplicate codes', () {
      final codes = kGstStates.map((s) => s.code).toList();
      expect(codes.toSet().length, codes.length);
    });

    test('matches the website list, count and contents', () {
      // 37 entries, same as apps/admin_web/src/lib/gst-states.ts. If one side
      // gains a state the other must too.
      expect(kGstStates, hasLength(37));
      final byCode = {for (final s in kGstStates) s.code: s.name};
      expect(byCode['24'], 'Gujarat');
      expect(byCode['27'], 'Maharashtra');
      expect(byCode['07'], 'Delhi');
    });

    test('omits codes that were never assigned', () {
      final codes = kGstStates.map((s) => s.code);
      expect(codes, isNot(contains('25')));
      expect(codes, isNot(contains('28')));
    });
  });

  group('gstinStateMismatch', () {
    test('silent when the GSTIN agrees with the chosen state', () {
      expect(gstinStateMismatch('24', '24AAAAA0000A1Z5'), isNull);
    });

    test('names the state the GSTIN belongs to', () {
      expect(gstinStateMismatch('24', '27AAAAA0000A1Z5'), contains('Maharashtra'));
    });

    test('silent while either field is empty', () {
      expect(gstinStateMismatch('24', ''), isNull);
      expect(gstinStateMismatch('', '27AAAAA0000A1Z5'), isNull);
    });

    test('silent for a prefix that is not a state', () {
      expect(gstinStateMismatch('24', '99AAAAA0000A1Z5'), isNull);
    });
  });
}
