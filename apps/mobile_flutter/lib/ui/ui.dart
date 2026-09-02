/// The design system every rebuilt screen is assembled from.
///
/// One import per screen:
///
/// ```dart
/// import '../../../ui/ui.dart';
/// ```
///
/// Replaces `features/shell/presentation/mobile_surface.dart`, which grew into
/// the de facto design system without ever being called one — 1,037 lines of
/// widgets living inside a feature folder, imported by 45 screens.
///
/// Two rules keep this layer honest:
///
/// 1. **No colour literals in screens.** Neutrals come from
///    `AppColors.of(context)`; anything semantic goes through `AppTone`.
/// 2. **No business logic here.** These widgets take formatted values and lay
///    them out. Anything that computes belongs in `core/`, with a test.
library;

export 'tokens.dart';
export 'tone.dart';
export 'widgets/app_card.dart';
export 'widgets/app_list_row.dart';
export 'widgets/app_screen.dart';
export 'widgets/app_tag.dart';
export 'widgets/money_text.dart';
