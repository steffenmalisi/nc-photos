// ignore: avoid_web_libraries_in_flutter
import 'dart:html';

import 'package:/nc_photos/mobile/ui_hack.dart' if (dart.library.html) 'dart:ui'
    as ui;
import 'package:flutter/widgets.dart';
import 'package:tuple/tuple.dart';

class Map extends StatefulWidget {
  const Map({
    Key? key,
    required this.center,
    required this.zoom,
    this.onTap,
  }) : super(key: key);

  @override
  createState() => _MapState();

  /// A pair of latitude and longitude coordinates, stored as degrees
  final Tuple2<double, double> center;
  final double zoom;
  final void Function()? onTap;
}

class _MapState extends State<Map> {
  @override
  initState() {
    super.initState();
    final iframe = IFrameElement()
      ..src = "https://www.google.com/maps/embed/v1/place?key=$_apiKey"
          "&q=${widget.center.item1},${widget.center.item2}"
          "&zoom=${widget.zoom}"
      ..style.border = "none";
    ui.platformViewRegistry.registerViewFactory(viewType, (viewId) => iframe);
  }

  @override
  build(BuildContext context) {
    return HtmlElementView(
      viewType: viewType,
    );
  }

  static const _apiKey = "";

  String get viewType =>
      "mapIframe(${widget.center.item1},${widget.center.item2})";
}
