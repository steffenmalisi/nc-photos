import 'package:flutter/material.dart';
import 'package:kiwi/kiwi.dart';
import 'package:logging/logging.dart';
import 'package:nc_photos/account.dart';
import 'package:nc_photos/app_localizations.dart';
import 'package:nc_photos/ci_string.dart';
import 'package:nc_photos/di_container.dart';
import 'package:nc_photos/entity/file_util.dart' as file_util;
import 'package:nc_photos/exception.dart';
import 'package:nc_photos/exception_util.dart' as exception_util;
import 'package:nc_photos/help_utils.dart' as help_util;
import 'package:nc_photos/k.dart' as k;
import 'package:nc_photos/snack_bar_manager.dart';
import 'package:nc_photos/string_extension.dart';
import 'package:nc_photos/theme.dart';
import 'package:nc_photos/url_launcher_util.dart';
import 'package:nc_photos/use_case/ls_single_file.dart';
import 'package:webview_flutter/webview_flutter.dart';

class ConnectArguments {
  ConnectArguments(this.url);

  final Uri url;
}

class Connect extends StatefulWidget {
  static const routeName = "/connect";

  static Route buildRoute(ConnectArguments args) => MaterialPageRoute<Account>(
        builder: (context) => Connect.fromArgs(args),
      );

  const Connect({
    Key? key,
    required this.url,
  }) : super(key: key);

  Connect.fromArgs(ConnectArguments args, {Key? key})
      : this(
          key: key,
          url: args.url,
        );

  @override
  createState() => _ConnectState();

  final Uri url;
}

class _ConnectState extends State<Connect> {
  final _key = UniqueKey();

  @override
  initState() {
    super.initState();
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
    return Column(
      children: [
        Expanded(
            child: WebView(
                key: _key,
                userAgent: 'nc-photos',
                javascriptMode: JavascriptMode.unrestricted,
                onWebViewCreated: (WebViewController webViewController) {
                  Map<String, String> headers = {
                    "OCS-APIREQUEST": "true",
                    "ACCEPT_LANGUAGE": "de",
                  };
                  webViewController.loadUrl(
                      "${widget.url}/index.php/login/flow",
                      headers: headers);
                },
                navigationDelegate: (NavigationRequest request) {
                  if (request.url.startsWith('nc://login/')) {
                    _onCredentialsReceived(request.url);
                    return NavigationDecision.prevent;
                  }
                  return NavigationDecision.navigate;
                }))
      ],
    );
  }

  static final _log = Logger("widget.connect._ConnectState");

  void _onCredentialsReceived(String url) {
    _log.info("[_onCredentialsReceived] App credentials received");
    final callbackUrlRegex =
        RegExp(r'nc:\/\/login\/server:([^&]+)&user:([^&]+)&password:(.*)');
    final match = callbackUrlRegex.firstMatch(url);
    if (match == null) {
      _log.shout(
          "[_onCredentialsReceived] callbackUrlRegex does not match url: $url");
      SnackBarManager().showSnackBar(SnackBar(
        content: Text(exception_util.toUserString(null)),
        duration: k.snackBarDurationNormal,
      ));
      Navigator.of(context).pop(null);
      return;
    }
    final newAccount = Account(
        Account.newId(),
        widget.url.scheme,
        widget.url.host,
        match.group(2).toString().toCi(),
        match.group(2)!,
        match.group(3)!,
        [""]);

    _log.fine("[_onCredentialsReceived] This is the new account: $newAccount");

    _checkWebDavUrl(context, newAccount);
  }

  Future<void> _onCheckWebDavUrlFailed(
      BuildContext context, Account account) async {
    final userId = await _askWebDavUrl(context, account);
    if (userId != null) {
      final newAccount = account.copyWith(
        userId: userId.toCi(),
      );
      return _checkWebDavUrl(context, newAccount);
    }
  }

  Future<void> _checkWebDavUrl(BuildContext context, Account account) async {
    // check the WebDAV URL
    try {
      final c = KiwiContainer().resolve<DiContainer>();
      await LsSingleFile(c.withRemoteFileRepo())(
          account, file_util.unstripPath(account, ""));
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
                _formValue.userId = value!.trimAny("/");
              },
              initialValue: widget.account.userId.toString(),
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
      Navigator.of(context).pop(_formValue.userId);
    }
  }

  void _onHelpPressed() {
    launch(help_util.homeFolderNotFoundUrl);
  }

  final _formKey = GlobalKey<FormState>();
  final _formValue = _FormValue();
}

class _FormValue {
  late String userId;
}
