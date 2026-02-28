import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void test() {
  PolylineAnnotationOptions(
    geometry: LineString(
      coordinates: [Position(121.0, 14.0), Position(121.1, 14.1)],
    ),
    lineColor: 0xFFFFC0CB,
    lineWidth: 4.0,
  );
}
