import 'dart:math';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:logging/logging.dart';
import 'package:nc_photos/account.dart';
import 'package:nc_photos/api/api.dart';
import 'package:nc_photos/api/api_util.dart' as api_util;
import 'package:nc_photos/entity/album.dart';
import 'package:nc_photos/entity/file.dart';
import 'package:nc_photos/exception.dart';
import 'package:nc_photos/exception_util.dart' as exception_util;
import 'package:nc_photos/k.dart' as k;
import 'package:nc_photos/mobile/platform.dart'
    if (dart.library.html) 'package:nc_photos/web/platform.dart' as platform;
import 'package:nc_photos/snack_bar_manager.dart';
import 'package:nc_photos/theme.dart';
import 'package:nc_photos/use_case/remove.dart';
import 'package:nc_photos/widget/cached_network_image_mod.dart' as mod;
import 'package:nc_photos/widget/viewer_detail_pane.dart';

class ViewerArguments {
  ViewerArguments(this.account, this.streamFiles, this.startIndex);

  final Account account;
  final List<File> streamFiles;
  final int startIndex;
}

class Viewer extends StatefulWidget {
  static const routeName = "/viewer";

  Viewer({
    Key key,
    @required this.account,
    @required this.streamFiles,
    @required this.startIndex,
  }) : super(key: key);

  Viewer.fromArgs(ViewerArguments args, {Key key})
      : this(
          key: key,
          account: args.account,
          streamFiles: args.streamFiles,
          startIndex: args.startIndex,
        );

  @override
  createState() => _ViewerState();

  final Account account;
  final List<File> streamFiles;
  final int startIndex;
}

class _ViewerState extends State<Viewer> with TickerProviderStateMixin {
  @override
  void initState() {
    super.initState();
    _pageController = PageController(
        initialPage: widget.startIndex,
        viewportFraction: 1.05,
        keepPage: false);
    _pageFocus.requestFocus();
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
    Widget content = Listener(
      onPointerDown: (event) {
        ++_finger;
        if (_finger >= 2 && _canZoom()) {
          _setIsZooming(true);
        }
      },
      onPointerUp: (event) {
        --_finger;
        if (_finger < 2) {
          _setIsZooming(false);
        }
        _prevFingerPosition = event.position;
      },
      child: GestureDetector(
        onTap: () {
          setState(() {
            _setShowActionBar(!_isShowAppBar);
          });
        },
        onDoubleTap: () {
          if (_canZoom()) {
            if (_isZoomed()) {
              // restore transformation
              _autoZoomOut();
            } else {
              _autoZoomIn();
            }
          }
        },
        child: Stack(
          children: [
            Container(color: Colors.black),
            if (!_pageController.hasClients ||
                !_pageStates[_pageController.page.round()].hasPreloaded)
              Align(
                alignment: Alignment.center,
                child: const CircularProgressIndicator(),
              ),
            PageView.builder(
              controller: _pageController,
              itemCount: widget.streamFiles.length,
              itemBuilder: _buildPage,
              physics: _canSwitchPage()
                  ? null
                  : const NeverScrollableScrollPhysics(),
            ),
            _buildBottomAppBar(context),
            _buildAppBar(context),
          ],
        ),
      ),
    );

    // support switching pages with keyboard on web
    if (kIsWeb) {
      content = RawKeyboardListener(
        onKey: (ev) {
          if (!_canSwitchPage()) {
            return;
          }
          toPrevPage() => _pageController.previousPage(
              duration: k.animationDurationNormal, curve: Curves.easeInOut);
          toNextPage() => _pageController.nextPage(
              duration: k.animationDurationNormal, curve: Curves.easeInOut);
          if (ev.isKeyPressed(LogicalKeyboardKey.arrowLeft)) {
            if (Directionality.of(context) == TextDirection.ltr) {
              toPrevPage();
            } else {
              toNextPage();
            }
          } else if (ev.isKeyPressed(LogicalKeyboardKey.arrowRight)) {
            if (Directionality.of(context) == TextDirection.ltr) {
              toNextPage();
            } else {
              toPrevPage();
            }
          }
        },
        focusNode: _pageFocus,
        child: content,
      );
    }

    return content;
  }

  Widget _buildAppBar(BuildContext context) {
    return Wrap(
      children: [
        AnimatedOpacity(
          opacity: _isShowAppBar ? 1.0 : 0.0,
          duration: k.animationDurationNormal,
          onEnd: () {
            if (!_isShowAppBar) {
              setState(() {
                _isAppBarActive = false;
              });
            }
          },
          child: Visibility(
            visible: _isAppBarActive,
            child: Stack(
              children: [
                Container(
                  // + status bar height
                  height: kToolbarHeight + MediaQuery.of(context).padding.top,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: const Alignment(0, -1),
                      end: const Alignment(0, 1),
                      colors: [
                        Color.fromARGB(192, 0, 0, 0),
                        Color.fromARGB(0, 0, 0, 0),
                      ],
                    ),
                  ),
                ),
                AppBar(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  brightness: Brightness.dark,
                  iconTheme:
                      Theme.of(context).iconTheme.copyWith(color: Colors.white),
                  actionsIconTheme:
                      Theme.of(context).iconTheme.copyWith(color: Colors.white),
                  actions: [
                    if (!_isDetailPaneActive && _canOpenDetailPane())
                      IconButton(
                        icon: const Icon(Icons.more_vert),
                        tooltip: AppLocalizations.of(context).detailsTooltip,
                        onPressed: _onDetailsPressed,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomAppBar(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedOpacity(
          opacity: _isShowAppBar ? 1.0 : 0.0,
          duration: k.animationDurationNormal,
          child: Visibility(
            visible: _isAppBarActive && !_isDetailPaneActive,
            child: Container(
              height: kToolbarHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: const Alignment(0, -1),
                  end: const Alignment(0, 1),
                  colors: [
                    Color.fromARGB(0, 0, 0, 0),
                    Color.fromARGB(192, 0, 0, 0),
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: <Widget>[
                  Expanded(
                    flex: 1,
                    child: IconButton(
                      icon: const Icon(Icons.download_outlined,
                          color: Colors.white),
                      tooltip: AppLocalizations.of(context).downloadTooltip,
                      onPressed: () => _onDownloadPressed(context),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: IconButton(
                      icon: const Icon(Icons.delete_outlined,
                          color: Colors.white),
                      tooltip: AppLocalizations.of(context).deleteTooltip,
                      onPressed: () => _onDeletePressed(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(BuildContext context, int index) {
    if (_pageStates[index] == null) {
      _onCreateNewPage(context, index);
    } else if (!_pageStates[index].scrollController.hasClients) {
      // the page has been moved out of view and is now coming back
      _log.fine("[_buildPage] Recreating page#$index");
      _onRecreatePageAfterMovedOut(context, index);
    }

    if (kDebugMode) {
      _log.info("[_buildPage] $index");
    }

    return FractionallySizedBox(
      widthFactor: 1 / _pageController.viewportFraction,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notif) => _onPageContentScrolled(notif, index),
        child: SingleChildScrollView(
          controller: _pageStates[index].scrollController,
          physics:
              _isDetailPaneActive ? null : const NeverScrollableScrollPhysics(),
          child: Stack(
            children: [
              _buildItemView(context, index),
              Visibility(
                visible: _isDetailPaneActive,
                child: AnimatedOpacity(
                  opacity: _isShowDetailPane ? 1 : 0,
                  duration: k.animationDurationNormal,
                  onEnd: () {
                    if (!_isShowDetailPane) {
                      setState(() {
                        _isDetailPaneActive = false;
                      });
                    }
                  },
                  child: Container(
                    alignment: Alignment.topLeft,
                    constraints: BoxConstraints(
                        minHeight: MediaQuery.of(context).size.height),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: const BorderRadius.vertical(
                          top: const Radius.circular(4)),
                    ),
                    margin: EdgeInsets.only(top: _calcDetailPaneOffset(index)),
                    child: ViewerDetailPane(
                      account: widget.account,
                      file: widget.streamFiles[index],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemView(BuildContext context, int index) {
    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 3.0,
      transformationController: _transformationController,
      panEnabled: _canZoom(),
      scaleEnabled: _canZoom(),
      // allow the image to be zoomed to fill the whole screen
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.height,
        alignment: Alignment.center,
        child: NotificationListener<SizeChangedLayoutNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_pageStates[index].key.currentContext != null) {
                _updateItemHeight(
                    index, _pageStates[index].key.currentContext.size.height);
              }
            });
            return false;
          },
          child: SizeChangedLayoutNotifier(
            child: mod.CachedNetworkImage(
              key: _pageStates[index].key,
              imageUrl: _getImageUrl(widget.account, widget.streamFiles[index]),
              httpHeaders: {
                "Authorization":
                    Api.getAuthorizationHeaderValue(widget.account),
              },
              fit: BoxFit.contain,
              fadeInDuration: const Duration(),
              filterQuality: FilterQuality.high,
              imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
              imageBuilder: (context, child, imageProvider) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _onItemLoaded(index);
                });
                SizeChangedLayoutNotification().dispatch(context);
                return child;
              },
            ),
          ),
        ),
      ),
    );
  }

  bool _onPageContentScrolled(ScrollNotification notification, int index) {
    if (!_canOpenDetailPane()) {
      return false;
    }
    if (notification is ScrollEndNotification) {
      final scrollPos = _pageStates[index].scrollController.position;
      if (scrollPos.pixels == 0) {
        setState(() {
          _onDetailPaneClosed();
        });
      } else if (scrollPos.pixels <
          _calcDetailPaneOpenedScrollPosition(index) - 1) {
        if (scrollPos.userScrollDirection == ScrollDirection.reverse) {
          // upward, open the pane to its minimal size
          Future.delayed(Duration.zero, () {
            setState(() {
              _openDetailPane(_pageController.page.toInt(),
                  shouldAnimate: true);
            });
          });
        } else if (scrollPos.userScrollDirection == ScrollDirection.forward) {
          // downward, close the pane
          Future.delayed(Duration.zero, () {
            _closeDetailPane(_pageController.page.toInt(), shouldAnimate: true);
          });
        }
      }
    }
    return false;
  }

  void _onItemLoaded(int index) {
    // currently pageview doesn't pre-load pages, we do it manually
    // don't pre-load if user already navigated away
    if (_pageController.page.round() == index &&
        !_pageStates[index].hasPreloaded) {
      _log.info("[_onItemLoaded] Pre-loading nearby items");
      if (index > 0) {
        DefaultCacheManager().getFileStream(
          _getImageUrl(widget.account, widget.streamFiles[index - 1]),
          headers: {
            "Authorization": Api.getAuthorizationHeaderValue(widget.account),
          },
        );
      }
      if (index + 1 < widget.streamFiles.length) {
        DefaultCacheManager().getFileStream(
          _getImageUrl(widget.account, widget.streamFiles[index + 1]),
          headers: {
            "Authorization": Api.getAuthorizationHeaderValue(widget.account),
          },
        );
      }
      setState(() {
        _pageStates[index].hasPreloaded = true;
      });
    }
  }

  /// Called when the page is being built for the first time
  void _onCreateNewPage(BuildContext context, int index) {
    _pageStates[index] = _PageState(ScrollController(
        initialScrollOffset: _isShowDetailPane && !_isClosingDetailPane
            ? _calcDetailPaneOpenedScrollPosition(index)
            : 0));
  }

  /// Called when the page is being built after previously moved out of view
  void _onRecreatePageAfterMovedOut(BuildContext context, int index) {
    if (_isShowDetailPane && !_isClosingDetailPane) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageStates[index].itemHeight != null) {
          setState(() {
            _openDetailPane(index);
          });
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _pageStates[index].scrollController.jumpTo(0);
      });
    }
  }

  void _onDetailsPressed() {
    if (!_isDetailPaneActive) {
      setState(() {
        _openDetailPane(_pageController.page.toInt(), shouldAnimate: true);
      });
    }
  }

  void _onDownloadPressed(BuildContext context) async {
    final file = widget.streamFiles[_pageController.page.round()];
    _log.info("[_onDownloadPressed] Downloading file: ${file.path}");
    var controller = SnackBarManager().showSnackBar(SnackBar(
      content:
          Text(AppLocalizations.of(context).downloadProcessingNotification),
      duration: k.snackBarDurationShort,
    ));
    controller?.closed?.whenComplete(() {
      controller = null;
    });
    try {
      await platform.Downloader().downloadFile(widget.account, file);
      controller?.close();
      SnackBarManager().showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).downloadSuccessNotification),
        duration: k.snackBarDurationShort,
      ));
    } on PermissionException catch (_) {
      _log.warning("[_onDownloadPressed] Permission not granted");
      controller?.close();
      SnackBarManager().showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)
            .downloadFailureNoPermissionNotification),
        duration: k.snackBarDurationNormal,
      ));
    } catch (e, stacktrace) {
      _log.severe(
          "[_onDownloadPressed] Failed while downloadFile", e, stacktrace);
      controller?.close();
      SnackBarManager().showSnackBar(SnackBar(
        content:
            Text("${AppLocalizations.of(context).downloadFailureNotification}: "
                "${exception_util.toUserString(e, context)}"),
        duration: k.snackBarDurationNormal,
      ));
    }
  }

  void _onDeletePressed(BuildContext context) async {
    final file = widget.streamFiles[_pageController.page.round()];
    _log.info("[_onDeletePressed] Removing file: ${file.path}");
    var controller = SnackBarManager().showSnackBar(SnackBar(
      content: Text(AppLocalizations.of(context).deleteProcessingNotification),
      duration: k.snackBarDurationShort,
    ));
    controller?.closed?.whenComplete(() {
      controller = null;
    });
    try {
      await Remove(FileRepo(FileCachedDataSource()),
          AlbumRepo(AlbumCachedDataSource()))(widget.account, file);
      controller?.close();
      SnackBarManager().showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context).deleteSuccessNotification),
        duration: k.snackBarDurationNormal,
      ));
      Navigator.of(context).pop();
    } catch (e, stacktrace) {
      _log.severe("[_onDeletePressed] Failed while remove: ${file.path}", e,
          stacktrace);
      controller?.close();
      SnackBarManager().showSnackBar(SnackBar(
        content:
            Text("${AppLocalizations.of(context).deleteFailureNotification}: "
                "${exception_util.toUserString(e, context)}"),
        duration: k.snackBarDurationNormal,
      ));
    }
  }

  double _calcDetailPaneOffset(int index) {
    if (_pageStates[index]?.itemHeight == null) {
      return MediaQuery.of(context).size.height;
    } else {
      return _pageStates[index].itemHeight +
          (MediaQuery.of(context).size.height - _pageStates[index].itemHeight) /
              2 -
          4;
    }
  }

  double _calcDetailPaneOpenedScrollPosition(int index) {
    // distance of the detail pane from the top edge
    const distanceFromTop = 196;
    return max(_calcDetailPaneOffset(index) - distanceFromTop, 0);
  }

  void _updateItemHeight(int index, double height) {
    if (_pageStates[index].itemHeight != height) {
      _log.fine("[_updateItemHeight] New height of item#$index: $height");
      setState(() {
        _pageStates[index].itemHeight = height;
        if (_isDetailPaneActive) {
          _openDetailPane(index);
        }
      });
    }
  }

  void _setShowActionBar(bool flag) {
    _isShowAppBar = flag;
    if (flag) {
      _isAppBarActive = true;
    }
  }

  void _openDetailPane(int index, {bool shouldAnimate = false}) {
    if (!_canOpenDetailPane()) {
      _log.warning("[_openDetailPane] Can't open detail pane right now");
      return;
    }

    _isShowDetailPane = true;
    _isDetailPaneActive = true;
    if (shouldAnimate) {
      _pageStates[index].scrollController.animateTo(
          _calcDetailPaneOpenedScrollPosition(index),
          duration: k.animationDurationNormal,
          curve: Curves.easeOut);
    } else {
      _pageStates[index]
          .scrollController
          .jumpTo(_calcDetailPaneOpenedScrollPosition(index));
    }
  }

  void _closeDetailPane(int index, {bool shouldAnimate = false}) {
    _isClosingDetailPane = true;
    if (shouldAnimate) {
      _pageStates[index].scrollController.animateTo(0,
          duration: k.animationDurationNormal, curve: Curves.easeOut);
    }
  }

  void _onDetailPaneClosed() {
    _isShowDetailPane = false;
    _isClosingDetailPane = false;
  }

  void _setIsZooming(bool flag) {
    _isZooming = flag;
    final next = _isZoomed();
    if (next != _wasZoomed) {
      _wasZoomed = next;
      setState(() {
        _log.info("[_setIsZooming] Is zoomed: $next");
      });
    }
  }

  bool _isZoomed() {
    return _isZooming ||
        _transformationController.value.getMaxScaleOnAxis() != 1.0;
  }

  /// Called when double tapping the image to zoom in to the default level
  void _autoZoomIn() {
    final animController =
        AnimationController(duration: k.animationDurationShort, vsync: this);
    final originX = -_prevFingerPosition.dx / 2;
    final originY = -_prevFingerPosition.dy / 2;
    final anim = Matrix4Tween(
            begin: Matrix4.identity(),
            end: Matrix4.identity()
              ..scale(2.0)
              ..translate(originX, originY))
        .animate(animController);
    animController
      ..addListener(() {
        _transformationController.value = anim.value;
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _setIsZooming(false);
        }
      })
      ..forward();
    _setIsZooming(true);
  }

  /// Called when double tapping the zoomed image to zoom out
  void _autoZoomOut() {
    final animController =
        AnimationController(duration: k.animationDurationShort, vsync: this);
    final anim = Matrix4Tween(
            begin: _transformationController.value, end: Matrix4.identity())
        .animate(animController);
    animController
      ..addListener(() {
        _transformationController.value = anim.value;
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _setIsZooming(false);
        }
      })
      ..forward();
    _setIsZooming(true);
  }

  bool _canSwitchPage() => !_isZoomed();
  bool _canOpenDetailPane() => !_isZoomed();
  bool _canZoom() => !_isDetailPaneActive;

  String _getImageUrl(Account account, File file) => api_util.getFilePreviewUrl(
        account,
        file,
        width: 1080,
        height: 1080,
        a: true,
      );

  var _isShowAppBar = true;
  var _isAppBarActive = true;

  var _isShowDetailPane = false;
  var _isDetailPaneActive = false;
  var _isClosingDetailPane = false;

  var _isZooming = false;
  var _wasZoomed = false;
  final _transformationController = TransformationController();

  int _finger = 0;
  Offset _prevFingerPosition;

  PageController _pageController;
  final _pageStates = <int, _PageState>{};

  /// used to gain focus on web for keyboard support
  final _pageFocus = FocusNode();

  static final _log = Logger("widget.viewer._ViewerState");
}

class _PageState {
  _PageState(this.scrollController);

  ScrollController scrollController;
  double itemHeight;
  bool hasPreloaded = false;
  GlobalKey key = GlobalKey();
}
