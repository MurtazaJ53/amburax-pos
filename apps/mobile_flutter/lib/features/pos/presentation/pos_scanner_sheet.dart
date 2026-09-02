import 'package:flutter/material.dart';

import 'package:mobile_scanner/mobile_scanner.dart';

import '../../shell/presentation/mobile_surface.dart';
import '../../../ui/ui.dart';

class PosScannerSheet extends StatefulWidget {
  const PosScannerSheet({super.key});

  @override
  State<PosScannerSheet> createState() => _PosScannerSheetState();
}

class _PosScannerSheetState extends State<PosScannerSheet> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  final TextEditingController _manualCodeController = TextEditingController();
  bool _didResolve = false;

  @override
  void dispose() {
    _manualCodeController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _resolveCode(String rawCode) {
    final code = rawCode.trim();
    if (_didResolve || code.isEmpty || !mounted) {
      return;
    }
    _didResolve = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 420;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: compact ? 16 : 18,
          right: compact ? 16 : 18,
          top: compact ? 16 : 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const AppSheetHeader(
              eyebrow: 'Fast lookup',
              title: 'Scan barcode or exact code',
              subtitle:
                  'Point the camera at a barcode, QR code, or exact inventory code. You can also type the code manually below.',
              icon: Icons.qr_code_scanner_rounded,
              tone: AppTone.primary,
              tags: <Widget>[
                AppTag(
                  label: 'Camera ready',
                  icon: Icons.camera_alt_rounded,
                  tone: AppTone.success,
                ),
                AppTag(
                  label: 'Exact lookup',
                  icon: Icons.keyboard_alt_rounded,
                  tone: AppTone.info,
                ),
              ],
            ),
            const SizedBox(height: 16),
            MobileSheetSection(
              title: 'Scan live code',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(26),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF050A12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06),
                      ),
                    ),
                    child: MobileScanner(
                      controller: _controller,
                      onDetect: (capture) {
                        for (final barcode in capture.barcodes) {
                          final raw = barcode.rawValue;
                          if (raw != null && raw.trim().isNotEmpty) {
                            _resolveCode(raw);
                            break;
                          }
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            MobileSheetSection(
              title: 'Type code manually',
              child: TextField(
                controller: _manualCodeController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.keyboard_alt_rounded),
                  labelText: 'Manual code',
                  hintText: 'Enter SKU or barcode',
                ),
                onSubmitted: _resolveCode,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _resolveCode(_manualCodeController.text),
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Use code'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
