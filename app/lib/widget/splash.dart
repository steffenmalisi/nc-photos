import 'dart:async';

import 'package:flutter/material.dart';
import 'package:logging/logging.dart';
import 'package:nc_photos/app_localizations.dart';
import 'package:nc_photos/k.dart' as k;
import 'package:nc_photos/mobile/android/activity.dart';
import 'package:nc_photos/platform/k.dart' as platform_k;
import 'package:nc_photos/pref.dart';
import 'package:nc_photos/theme.dart';
import 'package:nc_photos/use_case/compat/v29.dart';
import 'package:nc_photos/widget/changelog.dart';
import 'package:nc_photos/widget/home.dart';
import 'package:nc_photos/widget/setup.dart';
import 'package:nc_photos/widget/sign_in.dart';

class Splash extends StatefulWidget {
  static const routeName = "/splash";

  const Splash({
    Key? key,
  }) : super(key: key);

  @override
  createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  @override
  initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _doWork();
    });
  }

  Future<void> _doWork() async {
    if (Pref().getFirstRunTime() == null) {
      await Pref().setFirstRunTime(DateTime.now().millisecondsSinceEpoch);
    }
    if (_shouldUpgrade()) {
      setState(() {
        _isUpgrading = true;
      });
      await _handleUpgrade();
      setState(() {
        _isUpgrading = false;
      });
    }
    _exit();
  }

  @override
  build(BuildContext context) {
    return AppTheme(
      child: Scaffold(
        body: Builder(builder: (context) => _buildContent(context)),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud,
                  size: 96,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 8),
                Text(
                  L10n.global().appTitle,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headline4,
                ),
              ],
            ),
            if (_isUpgrading)
              Positioned(
                left: 0,
                right: 0,
                bottom: 64,
                child: Column(
                  children: const [
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(),
                    ),
                    SizedBox(height: 8),
                    Text("Updating"),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _exit() async {
    _log.info("[_exit]");
    final account = Pref().getCurrentAccount();
    if (isNeedSetup()) {
      Navigator.pushReplacementNamed(context, Setup.routeName);
    } else if (account == null) {
      Navigator.pushReplacementNamed(context, SignIn.routeName);
    } else {
      Navigator.pushReplacementNamed(context, Home.routeName,
          arguments: HomeArguments(account));
      if (platform_k.isAndroid) {
        final initialRoute = await Activity.consumeInitialRoute();
        if (initialRoute != null) {
          Navigator.pushNamed(context, initialRoute);
        }
      }
    }
  }

  bool _shouldUpgrade() {
    final lastVersion = Pref().getLastVersionOr(k.version);
    return lastVersion < k.version;
  }

  Future<void> _handleUpgrade() async {
    try {
      final lastVersion = Pref().getLastVersionOr(k.version);
      _showChangelogIfAvailable(lastVersion);
      // begin upgrade while showing the changelog
      try {
        _log.info("[_handleUpgrade] Upgrade: $lastVersion -> ${k.version}");
        await _upgrade(lastVersion);
        _log.info("[_handleUpgrade] Upgrade done");
      } finally {
        // ensure user has closed the changelog
        await _changelogCompleter.future;
      }
    } catch (e, stackTrace) {
      _log.shout("[_handleUpgrade] Failed while upgrade", e, stackTrace);
    } finally {
      await Pref().setLastVersion(k.version);
    }
  }

  Future<void> _upgrade(int lastVersion) async {
    if (lastVersion < 290) {
      await _upgrade29(lastVersion);
    }
  }

  Future<void> _upgrade29(int lastVersion) async {
    try {
      _log.info("[_upgrade29] clearDefaultCache");
      await CompatV29.clearDefaultCache();
    } catch (e, stackTrace) {
      _log.shout("[_upgrade29] Failed while clearDefaultCache", e, stackTrace);
      // just leave the cache then
    }
  }

  Future<void> _showChangelogIfAvailable(int lastVersion) async {
    if (Changelog.hasContent(lastVersion)) {
      try {
        await Navigator.of(context).pushNamed(Changelog.routeName,
            arguments: ChangelogArguments(lastVersion));
      } catch (e, stackTrace) {
        _log.severe(
            "[_showChangelogIfAvailable] Uncaught exception", e, stackTrace);
      } finally {
        _changelogCompleter.complete();
      }
    } else {
      _changelogCompleter.complete();
    }
  }

  final _changelogCompleter = Completer();
  var _isUpgrading = false;

  static final _log = Logger("widget.splash._SplashState");
}
