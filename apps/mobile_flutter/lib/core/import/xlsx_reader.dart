import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// A small, dependency-light XLSX reader.
///
/// An .xlsx file is just a ZIP of XML parts, so we read it directly instead of
/// relying on a heavier package that throws on plenty of real-world exports
/// (the failure users hit as "Couldn't read this Excel file"). We handle what
/// spreadsheet exports actually contain: shared strings (incl. rich-text runs),
/// inline strings, plain numbers, and sparse rows/columns.
///
/// Note: dates arrive as Excel serial numbers; callers that need a date should
/// accept that or ask for ISO text.
class XlsxSheet {
  const XlsxSheet(this.name, this.rows);

  final String name;

  /// Data as strings, row-major. Short rows are padded so column indexes line up.
  final List<List<String>> rows;
}

/// True when [bytes] look like a ZIP (and therefore a real .xlsx). Legacy .xls
/// (BIFF) files do not start with "PK" and cannot be read by this reader.
bool looksLikeXlsx(List<int> bytes) =>
    bytes.length > 1 && bytes[0] == 0x50 && bytes[1] == 0x4B; // 'P','K'

/// Parse every sheet of an .xlsx. Throws if the bytes aren't a readable xlsx.
List<XlsxSheet> readXlsx(List<int> bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);

  ArchiveFile? find(String path) {
    final wanted = path.toLowerCase();
    for (final f in archive.files) {
      if (f.name.toLowerCase() == wanted) return f;
    }
    return null;
  }

  String text(ArchiveFile f) =>
      utf8.decode(f.content as List<int>, allowMalformed: true);

  // --- shared string table (most cell text lives here) ---
  final shared = <String>[];
  final sharedFile = find('xl/sharedStrings.xml');
  if (sharedFile != null) {
    final doc = XmlDocument.parse(text(sharedFile));
    for (final si in doc.findAllElements('si')) {
      // Concatenate <t> runs so rich text ("Par" + "le-G") comes back whole.
      shared.add(si.findAllElements('t').map((e) => e.innerText).join());
    }
  }

  // --- sheet name -> part path (via workbook rels) ---
  final relTargets = <String, String>{};
  final relsFile = find('xl/_rels/workbook.xml.rels');
  if (relsFile != null) {
    for (final rel in XmlDocument.parse(
      text(relsFile),
    ).findAllElements('Relationship')) {
      final id = rel.getAttribute('Id');
      final target = rel.getAttribute('Target');
      if (id != null && target != null) relTargets[id] = target;
    }
  }

  final sheets = <XlsxSheet>[];
  final workbookFile = find('xl/workbook.xml');
  if (workbookFile == null) return sheets;

  var fallbackIndex = 0;
  for (final sheetEl in XmlDocument.parse(
    text(workbookFile),
  ).findAllElements('sheet')) {
    fallbackIndex++;
    final name = sheetEl.getAttribute('name') ?? 'Sheet$fallbackIndex';
    final rid = sheetEl.getAttribute('r:id') ?? sheetEl.getAttribute('id');
    var target = rid == null ? null : relTargets[rid];

    ArchiveFile? part;
    if (target != null) {
      target = target.startsWith('/') ? target.substring(1) : 'xl/$target';
      part = find(target.replaceAll('xl/xl/', 'xl/'));
    }
    // Some writers omit/mismatch rels — fall back to positional sheetN.xml.
    part ??= find('xl/worksheets/sheet$fallbackIndex.xml');
    if (part == null) continue;

    sheets.add(XlsxSheet(name, _parseSheet(text(part), shared)));
  }
  return sheets;
}

List<List<String>> _parseSheet(String sheetXml, List<String> shared) {
  final doc = XmlDocument.parse(sheetXml);
  final rows = <List<String>>[];

  for (final rowEl in doc.findAllElements('row')) {
    final cells = <int, String>{};
    var maxCol = -1;

    for (final c in rowEl.findElements('c')) {
      final col = _columnIndex(c.getAttribute('r') ?? '');
      final type = c.getAttribute('t');
      String value;

      if (type == 'inlineStr') {
        value = c.findAllElements('t').map((e) => e.innerText).join();
      } else {
        final raw = c.getElement('v')?.innerText ?? '';
        if (type == 's') {
          final idx = int.tryParse(raw);
          value = (idx != null && idx >= 0 && idx < shared.length)
              ? shared[idx]
              : '';
        } else {
          value = raw;
        }
      }

      cells[col] = value.trim();
      if (col > maxCol) maxCol = col;
    }

    // Pad sparse rows so column positions stay aligned with the header.
    rows.add(List<String>.generate(maxCol + 1, (i) => cells[i] ?? ''));
  }
  return rows;
}

/// "B7" -> 1, "AA3" -> 26. Returns 0 when the ref is missing/odd.
int _columnIndex(String ref) {
  var index = 0;
  var sawLetter = false;
  for (final unit in ref.codeUnits) {
    final isUpper = unit >= 0x41 && unit <= 0x5A;
    final isLower = unit >= 0x61 && unit <= 0x7A;
    if (isUpper || isLower) {
      index = index * 26 + (unit - (isUpper ? 0x40 : 0x60));
      sawLetter = true;
    } else if (sawLetter) {
      break; // hit the row digits
    }
  }
  return index > 0 ? index - 1 : 0;
}
