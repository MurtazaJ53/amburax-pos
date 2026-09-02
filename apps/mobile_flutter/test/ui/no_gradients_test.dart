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

/// Places where white genuinely is the right answer, each for a reason that
/// is about the medium rather than the design.
const Map<String, String> _allowedWhite = <String, String>{
  // A QR code is read by a camera. It has to be dark on white to scan.
  'upi_qr_view.dart': 'a QR code must be dark on white to scan',
  // A camera viewfinder is not a surface the palette applies to.
  'pos_scanner_sheet.dart': 'an overlay on a live camera preview',
  // A small brand mark carrying a single glyph, like the web logo.
  'auth_gate_screen.dart': 'the logo badge, a solid brand mark',
  // The one deliberate solid surface: the control the till exists to reach.
  'pos_screen_v3.dart': 'the cart bar, deliberately solid at 8.24:1',
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
    final offenders = <String>[
      for (final file in files)
        if (file.readAsStringSync().contains('Colors.white') &&
            !_allowedWhite.containsKey(_name(file)))
          _name(file),
    ];

    expect(
      offenders,
      isEmpty,
      reason:
          'White text forces a dark fill to stay legible, and a dark fill is '
          'what made this app look heavy beside the web on the same palette. '
          'Use toneColorsOf(context, tone) — .foreground is ink, .background '
          'is the pale ground it reads on. If white really is the medium '
          '(a QR code, a camera overlay), add the file to _allowedWhite with '
          'the reason.',
    );
  });
}
