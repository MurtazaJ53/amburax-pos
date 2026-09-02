import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The visual rule, held in place by a test because it is a rule about what
/// screens are allowed to do, and every screen is written weeks apart.
///
/// The app looked heavy next to the web while sharing an identical palette.
/// The difference was never the colours: it was that screens painted white
/// text on dark fills, which the web had already tried four times and
/// abandoned. Its palette file records why — white text forces a dark fill to
/// stay legible, so the fix is to stop using white text and let ink sit on a
/// pale ground instead.
///
/// A lint cannot express that, so this does.
List<File> _dartFilesUnder(List<String> dirs) {
  return <File>[
    for (final dir in dirs)
      if (Directory(dir).existsSync())
        ...Directory(dir)
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
  ];
}

String _name(File file) => file.path.split(RegExp(r'[/\\]')).last;

/// Places where white genuinely is the right answer, with a count.
///
/// The first version of this allowlisted whole files, which is how four solid
/// blue buttons with white labels survived the pass that was meant to remove
/// them: the POS file was exempt for its cart bar, so nothing else in its
/// 3,400 lines was ever checked. Counting means an exemption covers only what
/// was actually reviewed, and the next one added has to be argued for.
const Map<String, ({int allowed, String reason})>
_allowedWhite = <String, ({int allowed, String reason})>{
  // A QR code is read by a camera. It has to be dark on white to scan.
  'upi_qr_view.dart': (allowed: 1, reason: 'a QR must be dark on white'),
  // A camera viewfinder is not a surface the palette applies to.
  'pos_scanner_sheet.dart': (allowed: 1, reason: 'live camera overlay'),
  // A small brand mark carrying a single glyph, like the web logo.
  'auth_gate_screen.dart': (allowed: 1, reason: 'the logo badge'),
  // The cart bar is deliberately solid at 8.24:1, and the stock badges match
  // the orange pills the web puts on the same cards.
  'pos_screen_v3.dart': (allowed: 8, reason: 'cart bar and stock badges'),
  'variant_product_sheet.dart': (allowed: 1, reason: 'badge on a solid tone'),
};

void main() {
  final files = _dartFilesUnder(<String>['lib/features', 'lib/core/widgets']);

  test('the source tree was actually found', () {
    expect(
      files.length,
      greaterThan(20),
      reason: 'Run this from apps/mobile_flutter, or the guard proves nothing.',
    );
  });

  test('no screen paints a gradient', () {
    final offenders = <String>[
      for (final file in files)
        if (file.readAsStringSync().contains('LinearGradient')) _name(file),
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'Gradients went out with Phase 2.6. Two of them ran between colours '
          'two shades apart and repainted the whole screen to do it; the rest '
          'were navy slabs carrying white text. Use a flat surface with a '
          'hairline border, or a tone background from toneColorsOf().',
    );
  });

  test('no screen writes white text except where white is the medium', () {
    final offenders = <String>[];

    for (final file in files) {
      final name = _name(file);
      final count = 'Colors.white'.allMatches(file.readAsStringSync()).length;
      final allowance = _allowedWhite[name];

      if (allowance == null) {
        if (count > 0) offenders.add('$name ($count)');
      } else if (count > allowance.allowed) {
        offenders.add(
          '$name has $count, only ${allowance.allowed} reviewed '
          '(${allowance.reason})',
        );
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'White text forces a dark fill to stay legible, and a dark fill is '
          'what made this app look heavy beside the web on the same palette. '
          'Use toneColorsOf(context, tone) — .foreground is ink, .background '
          'is the pale ground it reads on. If white really is the medium, '
          'raise the count for that file here and say why.',
    );
  });
}
