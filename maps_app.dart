import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geolocator_linux/geolocator_linux.dart';
import 'package:flutter_map_location_marker/flutter_map_location_marker.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:google_places_flutter/model/prediction.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:open_route_service/open_route_service.dart';

class MapsApp extends StatefulWidget {
  const MapsApp({super.key});

  @override
  _MapsAppState createState() => _MapsAppState();
}

class _MapsAppState extends State<MapsApp> {
  late FollowOnLocationUpdate _followOnLocationUpdate;
  late StreamController<double?> _followCurrentLocationStreamController;
  final TextEditingController _searchController = TextEditingController();
  late final MapController _mapController;
  late final destinationMarker = <Marker>[];
  final OpenRouteService client = OpenRouteService(
      apiKey: '5b3ce3597851110001cf6248ed7cd847b2184aa0af0762fe45552eb6');

  List<dynamic> segments = [];

  bool _showGoButton = false;
  bool _showSearchBar = true;
  bool _inRoute = false;

  double routeDistance = 0;
  double routeDuration = 0;

  String appBarText = "Maps";

  LatLng _currentLocation = LatLng(33.2114, -87.5401);
  LatLng _destinationLocation = LatLng(33.2114, -87.5401);
  late LatLngBounds _mapBounds;

  Future<List<LatLng>> getRoute(
      LatLng currentLocation, LatLng destinationLocation) async {
    final List<ORSCoordinate> routeCoordinates =
        await client.directionsRouteCoordsGet(
      profileOverride: ORSProfile.drivingCar,
      startCoordinate: ORSCoordinate(
          latitude: currentLocation.latitude,
          longitude: currentLocation.longitude),
      endCoordinate: ORSCoordinate(
          latitude: destinationLocation.latitude,
          longitude: destinationLocation.longitude),
    );

    List<LatLng> route = [];
    routeCoordinates.forEach((element) {
      route.add(LatLng(element.latitude, element.longitude));
    });

    final GeoJsonFeatureCollection response =
        await client.directionsRouteGeoJsonGet(
      profileOverride: ORSProfile.drivingCar,
      startCoordinate: ORSCoordinate(
          latitude: currentLocation.latitude,
          longitude: currentLocation.longitude),
      endCoordinate: ORSCoordinate(
          latitude: destinationLocation.latitude,
          longitude: destinationLocation.longitude),
    );

    final GeoJsonFeature feature = response.features[0];

    final Map<String, dynamic> summary = feature.properties['summary'];
    routeDistance = summary['distance'] * 0.000621371;
    routeDuration = summary['duration'] / 60;

    //get route steps for each segment
    final List<dynamic> segments = feature.properties['segments'];
    for (var segment in segments) {
      final double segmentDistance = segment['distance'];

      final List<dynamic> steps = segment['steps'];
      for (var step in steps) {
        final double stepDistance = step['distance'];
        final double stepDuration = step['duration'];
        final int stepType = step['type'];
        final String stepInstruction = step['instruction'];
        final String stepName = step['name'];
      }
    }

    return route;
  }

  List<Polyline> polylines = [];

  Marker buildPin(LatLng point) => Marker(
        point: point,
        child: const Icon(Icons.location_pin, size: 30, color: Colors.grey),
        width: 60,
        height: 60,
      );

  void _getCurrentLocation() async {
    Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation);
    setState(() {
      _currentLocation = LatLng(position.latitude, position.longitude);
    });
  }

  void fitMap(LatLng currentLocation, LatLng destinationLocation) {
    _mapBounds = LatLngBounds(_currentLocation, _destinationLocation);
    CameraFit.bounds(bounds: _mapBounds, padding: const EdgeInsets.all(50));
  }

  @override
  void initState() {
    super.initState();
    _followOnLocationUpdate = FollowOnLocationUpdate.always;
    _followCurrentLocationStreamController = StreamController<double?>();
    _mapController = MapController();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _followCurrentLocationStreamController.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
          title: Text(appBarText)),
      body: Stack(children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
              onMapReady: () {
                _mapController.mapEventStream.listen((evt) {});
              },
              initialCenter: _currentLocation,
              initialZoom: 15.0,
              onPositionChanged: (MapPosition position, bool hasGesture) {
                if (hasGesture &&
                    _followOnLocationUpdate != FollowOnLocationUpdate.never) {
                  setState(() =>
                      _followOnLocationUpdate = FollowOnLocationUpdate.never);
                }
              }),
          children: [
            TileLayer(
              urlTemplate:
                  'https://api.mapbox.com/styles/v1/dszurek/clgqubrcl000m01pabold0i4s/tiles/256/{z}/{x}/{y}@2x?access_token=pk.eyJ1IjoiZHN6dXJlayIsImEiOiJjbGVpdG4zODYwNG9rM3ByMGpxZjh3dmR6In0.BsJeNSZ_unOyKTFqunvknw', //mapbox Tiles key
              userAgentPackageName: 'infotainment',
            ),
            CurrentLocationLayer(
                positionStream: const LocationMarkerDataStreamFactory()
                    .fromGeolocatorPositionStream(
                  stream: Geolocator.getPositionStream(
                    locationSettings: const LocationSettings(
                      accuracy: LocationAccuracy.bestForNavigation,
                      distanceFilter: 50,
                      timeLimit: Duration(minutes: 1),
                    ),
                  ),
                ),
                followOnLocationUpdate: FollowOnLocationUpdate.always,
                turnOnHeadingUpdate: TurnOnHeadingUpdate.never,
                style: const LocationMarkerStyle(
                  marker: DefaultLocationMarker(
                      color: Colors.blueGrey,
                      child: Icon(Icons.assistant_navigation,
                          color: Colors.white)),
                  markerSize: Size(30, 30),
                  markerDirection: MarkerDirection.heading,
                )),
            MarkerLayer(markers: destinationMarker),
            PolylineLayer(
              polylines: polylines,
            ),
            Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: FloatingActionButton(
                        onPressed: () {
                          setState(() => _followOnLocationUpdate =
                              FollowOnLocationUpdate.always);
                          _followCurrentLocationStreamController.add(10);
                        },
                        child: const Icon(Icons.my_location,
                            color: Colors.white)))),
            const RichAttributionWidget(attributions: [
              TextSourceAttribution(
                'MapBox Tiles, Google Places, Open Route Service', //Copyright/attribution text
              ),
            ]),
          ],
        ),
        Padding(
            padding: const EdgeInsets.all(10.0),
            child: Visibility(
                visible: _showSearchBar,
                child: Container(
                    width: 300,
                    height: 65,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                            child: GooglePlaceAutoCompleteTextField(
                          boxDecoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          textEditingController: _searchController,
                          googleAPIKey:
                              "AIzaSyBLf5FhDKK_9Ln3svx1JsrMu0JszZkumZs", //google Places API key
                          inputDecoration: InputDecoration(
                            hintText: "Search",
                            fillColor: Colors.white,
                            filled: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                          debounceTime: 400,
                          isLatLngRequired: true,
                          getPlaceDetailWithLatLng:
                              (Prediction prediction) async {
                            // this method will move camera to selected location
                            _mapController.move(
                                LatLng(double.parse(prediction.lat!),
                                    double.parse(prediction.lng!)),
                                13.0);
                            _destinationLocation = LatLng(
                                double.parse(prediction.lat!),
                                double.parse(prediction.lng!));
                            List<LatLng> route = await getRoute(
                                _currentLocation, _destinationLocation);

                            Polyline routePolyline = Polyline(
                              points: route,
                              strokeWidth: 3.0,
                              color: Colors.blue,
                            );
                            Marker destinationPin =
                                buildPin(_destinationLocation);
                            fitMap(_currentLocation, _destinationLocation);

                            setState(() {
                              _showGoButton = true;

                              destinationMarker.clear();
                              destinationMarker.add(destinationPin);

                              polylines.clear();
                              polylines.add(routePolyline);
                            });
                          }, // this callback is called when isLatLngRequired is true
                          itemClick: (Prediction prediction) {
                            _searchController.text =
                                prediction.description ?? "";
                            _searchController.selection =
                                TextSelection.fromPosition(TextPosition(
                                    offset:
                                        prediction.description?.length ?? 0));
                          },

                          seperatedBuilder: Divider(),
                          itemBuilder: (context, index, Prediction prediction) {
                            return Container(
                              padding: EdgeInsets.all(10),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on,
                                      color: Colors.grey),
                                  const SizedBox(
                                    width: 7,
                                  ),
                                  Expanded(
                                    child: Text(prediction.description ?? ""),
                                  )
                                ],
                              ),
                            );
                          },
                          // want to show close icon
                          isCrossBtnShown: false,
                        )),
                        IconButton(
                          icon: _searchController.text.isNotEmpty
                              ? Icon(Icons.clear)
                              : Icon(Icons.search),
                          color: Colors.grey,
                          onPressed: _searchController.text.isNotEmpty
                              ? () {
                                  setState(() {
                                    _searchController.clear();
                                    destinationMarker.clear();
                                    polylines.clear();
                                    _showGoButton = false;
                                  });
                                }
                              : null,
                        )
                      ],
                    )))),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(15.0),
            child: Visibility(
              visible: _showGoButton,
              child: ElevatedButton(
                onPressed: () {
                  /* zoom in on current location, hide search bar, show cancel icon */
                  setState(() {
                    _mapController.move(_currentLocation, 17.0);
                    _showGoButton = false;
                    _showSearchBar = false;
                    _inRoute = true;
                  });
                  setState(() =>
                      _followOnLocationUpdate = FollowOnLocationUpdate.always);
                  _followCurrentLocationStreamController.add(10);
                  TurnOnHeadingUpdate.always;
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20.0),
                    ),
                    padding:
                        EdgeInsets.symmetric(horizontal: 50, vertical: 20)),
                child: Text('Go'),
              ),
            ),
          ),
        ),
        Align(
            alignment: Alignment.topRight,
            child: Padding(
                padding: const EdgeInsets.all(15.0),
                child: Visibility(
                    visible: _inRoute,
                    child: ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _inRoute = false;
                            _showSearchBar = true;
                            _showGoButton = false;
                            destinationMarker.clear();
                            polylines.clear();
                            _mapController.move(_currentLocation, 15.0);
                          });
                        },
                        child: Text('Cancel Route'))))),
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(15.0),
            child: Visibility(
              visible: _inRoute,
              child: Container(
                height: 45,
                width: 300,
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20)),
                child: Column(
                  children: [
                    Text(
                      'Distance: ${routeDistance.toStringAsFixed(2)} miles',
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Duration: ' +
                          (routeDuration >= 60
                              ? '${(routeDuration / 60).floor()} hour(s), ${(routeDuration % 60).toStringAsFixed(0)} minute(s)'
                              : '${routeDuration.toStringAsFixed(0)} minute(s)'),
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
        )
      ]),
    );
  }
}
