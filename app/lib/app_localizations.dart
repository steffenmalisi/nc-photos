import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations_en.dart';
import 'package:logging/logging.dart';
import 'package:nc_photos/widget/my_app.dart';

/// Simplify localized string access
class L10n {
  static AppLocalizations global() => AppLocalizations.of(MyApp.globalContext)!;

  static AppLocalizations of(Locale locale) {
    try {
      return lookupAppLocalizations(locale);
    } on FlutterError catch (_) {
      // unsupported locale, use default (en)
      return AppLocalizationsEn();
    } catch (e, stackTrace) {
      _log.shout("[of] Failed while lookupAppLocalizations", e, stackTrace);
      return AppLocalizationsEn();
    }
  }

  static final _log = Logger("app_localizations.L10n");
}
