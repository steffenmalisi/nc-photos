import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kiwi/kiwi.dart';
import 'package:logging/logging.dart';
import 'package:nc_photos/account.dart';
import 'package:nc_photos/app_localizations.dart';
import 'package:nc_photos/bloc/app_password_exchange.dart';
import 'package:nc_photos/ci_string.dart';
import 'package:nc_photos/di_container.dart';
import 'package:nc_photos/entity/file.dart';
import 'package:nc_photos/entity/file/data_source.dart';
import 'package:nc_photos/entity/file_util.dart' as file_util;
import 'package:nc_photos/exception.dart';
import 'package:nc_photos/exception_util.dart' as exception_util;
import 'package:nc_photos/help_utils.dart' as help_util;
import 'package:nc_photos/k.dart' as k;
import 'package:nc_photos/mobile/self_signed_cert_manager.dart';
import 'package:nc_photos/or_null.dart';
import 'package:nc_photos/platform/features.dart' as features;
import 'package:nc_photos/snack_bar_manager.dart';
import 'package:nc_photos/string_extension.dart';
import 'package:nc_photos/theme.dart';
import 'package:nc_photos/use_case/ls_single_file.dart';
import 'package:url_launcher/url_launcher.dart';

class ConnectArguments {
  ConnectArguments(this.account);

  final Account account;
}

class Connect extends StatefulWidget {
  static const routeName = "/connect";

  static Route buildRoute(ConnectArguments args) => MaterialPageRoute<Account>(
        builder: (context) => Connect.fromArgs(args),
      );

  const Connect({
    Key? key,
    required this.account,
  }) : super(key: key);

  Connect.fromArgs(ConnectArguments args, {Key? key})
      : this(
          key: key,
          account: args.account,
        );

  @override
  createState() => _ConnectState();

  final Account account;
}

class _ConnectState extends State<Connect> {
  @override
  initState() {
    super.initState();
    _initBloc();
  }

  @override
  build(BuildContext context) {
    return AppTheme(
      child: Scaffold(
        body:
            BlocListener<AppPasswordExchangeBloc, AppPasswordExchangeBlocState>(
          bloc: _bloc,
          listener: (context, state) => _onStateChange(context, state),
          child: Builder(builder: (context) => _buildContent(context)),
        ),
      ),
    );
  }

  void _initBloc() {
    _log.info("[_initBloc] Initialize bloc");
    _connect();
  }

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Center(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud,
              size: 128,
              color: Theme.of(context).colorScheme.primary,
            ),
            Text(
              L10n.global().connectingToServer(widget.account.url),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headline6,
            )
          ],
        ),
      ),
    );
  }

  void _onStateChange(
      BuildContext context, AppPasswordExchangeBlocState state) {
    if (state is AppPasswordExchangeBlocSuccess) {
      final newAccount = widget.account.copyWith(password: state.password);
      _log.info("[_onStateChange] Password exchanged: $newAccount");
      _checkWebDavUrl(context, newAccount);
    } else if (state is AppPasswordExchangeBlocFailure) {
      if (features.isSupportSelfSignedCert &&
          state.exception is HandshakeException) {
        _onSelfSignedCert(context);
      } else if (state.exception is ApiException &&
          (state.exception as ApiException).response.statusCode == 401) {
        SnackBarManager().showSnackBar(SnackBar(
          content: Text(L10n.global().errorWrongPassword),
          duration: k.snackBarDurationNormal,
        ));
        Navigator.of(context).pop(null);
      } else {
        SnackBarManager().showSnackBar(SnackBar(
          content: Text(exception_util.toUserString(state.exception)),
          duration: k.snackBarDurationNormal,
        ));
        Navigator.of(context).pop(null);
      }
    }
  }

  void _onSelfSignedCert(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(L10n.global().serverCertErrorDialogTitle),
        content: Text(L10n.global().serverCertErrorDialogContent),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text(MaterialLocalizations.of(context).closeButtonLabel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(true);
            },
            child: Text(L10n.global().advancedButtonLabel),
          ),
        ],
      ),
    ).then((value) {
      if (value != true) {
        Navigator.of(context).pop(null);
        return;
      }
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(L10n.global().whitelistCertDialogTitle),
          content: Text(L10n.global().whitelistCertDialogContent(
              SelfSignedCertManager().getLastBadCertHost(),
              SelfSignedCertManager().getLastBadCertFingerprint())),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: Text(L10n.global().whitelistCertButtonLabel),
            ),
          ],
        ),
      ).then((value) {
        if (value != true) {
          Navigator.of(context).pop(null);
          return;
        }
        SelfSignedCertManager().whitelistLastBadCert().then((value) {
          Navigator.of(context).pop(null);
        });
      });
    });
  }

  void _connect() {
    _bloc.add(AppPasswordExchangeBlocConnect(widget.account));
  }

  Future<void> _onCheckWebDavUrlFailed(
      BuildContext context, Account account) async {
    final altHomeDir = await _askWebDavUrl(context, account);
    if (altHomeDir != null) {
      final newAccount = account.copyWith(
        altHomeDir: OrNull(altHomeDir.toCi()),
      );
      return _checkWebDavUrl(context, newAccount);
    }
  }

  Future<void> _checkWebDavUrl(BuildContext context, Account account) async {
    // check the WebDAV URL
    try {
      final c = KiwiContainer().resolve<DiContainer>().copyWith(
            fileRepo: OrNull(const FileRepo(FileWebdavDataSource())),
          );
      await LsSingleFile(c)(account, file_util.unstripPath(account, ""));
      _log.info("[_checkWebDavUrl] Account is good: $account");
      Navigator.of(context).pop(account);
    } on ApiException catch (e) {
      if (e.response.statusCode == 404) {
        return _onCheckWebDavUrlFailed(context, account);
      }
      SnackBarManager().showSnackBar(SnackBar(
        content: Text(exception_util.toUserString(e)),
        duration: k.snackBarDurationNormal,
      ));
      Navigator.of(context).pop(null);
    } on StateError catch (_) {
      // Nextcloud for some reason doesn't return HTTP error when listing home
      // dir of other users
      return _onCheckWebDavUrlFailed(context, account);
    } catch (e, stackTrace) {
      _log.shout("[_checkWebDavUrl] Failed", e, stackTrace);
      SnackBarManager().showSnackBar(SnackBar(
        content: Text(exception_util.toUserString(e)),
        duration: k.snackBarDurationNormal,
      ));
      Navigator.of(context).pop(null);
    }
  }

  Future<String?> _askWebDavUrl(BuildContext context, Account account) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _WebDavUrlDialog(account: account),
    );
  }

  final _bloc = AppPasswordExchangeBloc();

  static final _log = Logger("widget.connect._ConnectState");
}

class _WebDavUrlDialog extends StatefulWidget {
  const _WebDavUrlDialog({
    Key? key,
    required this.account,
  }) : super(key: key);

  @override
  createState() => _WebDavUrlDialogState();

  final Account account;
}

class _WebDavUrlDialogState extends State<_WebDavUrlDialog> {
  @override
  build(BuildContext context) {
    return AlertDialog(
      title: Text(L10n.global().homeFolderNotFoundDialogTitle),
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(L10n.global().homeFolderNotFoundDialogContent),
            const SizedBox(height: 16),
            Text("${widget.account.url}/remote.php/dav/files/"),
            TextFormField(
              validator: (value) {
                if (value?.trimAny("/").isNotEmpty == true) {
                  return null;
                }
                return L10n.global().homeFolderInputInvalidEmpty;
              },
              onSaved: (value) {
                _formValue.altHomeDir = value!.trimAny("/");
              },
              initialValue: widget.account.homeDir.toString(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _onHelpPressed,
          child: Text(L10n.global().helpButtonLabel),
        ),
        TextButton(
          onPressed: _onOkPressed,
          child: Text(MaterialLocalizations.of(context).okButtonLabel),
        ),
      ],
    );
  }

  void _onOkPressed() {
    if (_formKey.currentState?.validate() == true) {
      _formKey.currentState!.save();
      Navigator.of(context).pop(_formValue.altHomeDir);
    }
  }

  void _onHelpPressed() {
    launch(help_util.homeFolderNotFoundUrl);
  }

  final _formKey = GlobalKey<FormState>();
  final _formValue = _FormValue();
}

class _FormValue {
  late String altHomeDir;
}
