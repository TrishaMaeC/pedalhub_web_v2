import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:ui' as ui;

class BikeTrackingMap extends StatefulWidget {
  const BikeTrackingMap({super.key});

  @override
  State<BikeTrackingMap> createState() => _BikeTrackingMapState();
}

class _BikeTrackingMapState extends State<BikeTrackingMap> {
  final supabase = Supabase.instance.client;

  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  List<LatLng> _historyPoints = [];
  Timer? _refreshTimer;

  static const LatLng _defaultPosition = LatLng(14.173183, 121.084274);
  static const int BIKE_ID = 12; // BIKE 1

  List<BikeLocation> _bikes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadData(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadBikeLocations(),
      _loadLocationHistory(),
    ]);
  }

  Future<void> _loadBikeLocations() async {
    try {
      final response = await supabase
          .from('bikes')
          .select('''
            id, 
            bike_number, 
            latitude, 
            longitude, 
            status, 
            last_location_update,
            total_distance_km,
            total_rides
          ''')
          .order('bike_number');

      final List bikesList = (response as List)
          .where((json) => json['latitude'] != null && json['longitude'] != null)
          .toList();

      if (mounted) {
        setState(() {
          _bikes = bikesList.map((json) => BikeLocation.fromJson(json)).toList();
          _isLoading = false;
        });
        await _updateMarkers();

        if (_bikes.isNotEmpty) {
          _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(
              LatLng(_bikes[0].latitude, _bikes[0].longitude),
              17.0,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error loading bike locations: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadLocationHistory() async {
  try {
    final response = await supabase
        .from('bike_locations')
        .select('latitude, longitude, created_at')
        .eq('bike_id', BIKE_ID)
        .order('created_at')
        .limit(100);

    if (mounted) {
      final newPoints = (response as List)
          .map((p) => LatLng(
                (p['latitude'] as num).toDouble(),
                (p['longitude'] as num).toDouble(),
              ))
          .toList();

      // Only update if may bagong points
      if (newPoints.length != _historyPoints.length) {
        setState(() {
          _historyPoints = newPoints;
          _updatePolyline();
        });
      }
    }
  } catch (e) {
    debugPrint('Error loading history: $e');
  }
}

  Future<void> _updateMarkers() async {
    Set<Marker> newMarkers = {};

    for (var bike in _bikes) {
      final bitmapDescriptor = await _createBikeMarker(bike.status);

      newMarkers.add(Marker(
        markerId: MarkerId('bike_${bike.id}'),
        position: LatLng(bike.latitude, bike.longitude),
        icon: bitmapDescriptor,
        infoWindow: InfoWindow(
          title: '🚲 ${bike.bikeNumber}',
          snippet: '${bike.status.toUpperCase()} • ${bike.totalDistanceKm} km • ${bike.totalRides} rides',
        ),
      ));
    }

    if (mounted) {
      setState(() => _markers = newMarkers);
    }
  }

  Future<BitmapDescriptor> _createBikeMarker(String status) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = Size(80, 80);

    // Background circle color based on status
    final color = status.toLowerCase() == 'available'
        ? Colors.green
        : status.toLowerCase() == 'in_use'
            ? Colors.orange
            : Colors.red;

    // Draw filled circle
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      36,
      Paint()..color = color,
    );

    // Draw white border
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      36,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    // Draw bike emoji
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '🚲',
        style: TextStyle(fontSize: 36),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size.width - textPainter.width) / 2,
        (size.height - textPainter.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      size.width.toInt(),
      size.height.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List());
  }

  void _updatePolyline() {
    if (_historyPoints.isEmpty) return;
    _polylines = {
      Polyline(
        polylineId: const PolylineId('bike_trail'),
        points: _historyPoints,
        color: Colors.blue,
        width: 4,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.pedal_bike, color: Colors.blue),
                const SizedBox(width: 12),
                const Text(
                  'Bike Tracking',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_historyPoints.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_historyPoints.length} pts',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadData,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),

          // Map
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _bikes.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_off, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No bike locations available',
                              style: TextStyle(fontSize: 16, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: _bikes.isNotEmpty
                              ? LatLng(_bikes[0].latitude, _bikes[0].longitude)
                              : _defaultPosition,
                          zoom: 17.0,
                        ),
                        markers: _markers,
                        polylines: _polylines,
                        onMapCreated: (controller) => _mapController = controller,
                        myLocationEnabled: false,
                        myLocationButtonEnabled: true,
                        zoomControlsEnabled: true,
                        mapToolbarEnabled: true,
                      ),
          ),

          // Info bar sa baba
          if (_bikes.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _infoChip(Icons.route, '${_bikes[0].totalDistanceKm} km', 'Distance'),
                  _infoChip(Icons.history, '${_historyPoints.length} pts', 'Trail'),
                  _infoChip(Icons.directions_bike, '${_bikes[0].totalRides}', 'Rides'),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoChip(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.blue),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }
}

// ================= MODEL =================
class BikeLocation {
  final int id;
  final String bikeNumber;
  final double latitude;
  final double longitude;
  final String status;
  final double totalDistanceKm;
  final int totalRides;
  final DateTime? lastLocationUpdate;

  BikeLocation({
    required this.id,
    required this.bikeNumber,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.totalDistanceKm,
    required this.totalRides,
    this.lastLocationUpdate,
  });

  factory BikeLocation.fromJson(Map<String, dynamic> json) {
    return BikeLocation(
      id: json['id'] as int,
      bikeNumber: json['bike_number'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      status: json['status'] as String,
      totalDistanceKm: (json['total_distance_km'] as num?)?.toDouble() ?? 0.0,
      totalRides: json['total_rides'] as int? ?? 0,
      lastLocationUpdate: json['last_location_update'] != null
          ? DateTime.parse(json['last_location_update'] as String)
          : null,
    );
  }
}