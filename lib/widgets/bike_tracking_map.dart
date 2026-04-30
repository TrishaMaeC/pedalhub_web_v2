import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:http/http.dart' as http;

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


  static const int BIKE_ID = 12; // BIKE 1

  // ── GOOGLE MAPS API KEY ──────────────────────────────────────────────────
  static const String GOOGLE_MAPS_API_KEY = 'YOUR_API_KEY_HERE';
  // ────────────────────────────────────────────────────────────────────────

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
            last_location_update
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
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day).toIso8601String();

      final response = await supabase
          .from('bike_locations')
          .select('latitude, longitude, created_at')
          .eq('bike_id', BIKE_ID)
          .gte('created_at', todayStart)
          .order('created_at')
          .limit(100);

      if (mounted) {
        final newPoints = (response as List)
            .map((p) => LatLng(
                  (p['latitude'] as num).toDouble(),
                  (p['longitude'] as num).toDouble(),
                ))
            .toList();

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

  // ══════════════════════════════════════════════════════════════════════════
  // BORROWER INFO QUERY
  // ══════════════════════════════════════════════════════════════════════════
  Future<BorrowerInfo?> _loadBorrowerInfo(String bikeNumber) async {
    try {
      final response = await supabase
          .from('borrowing_applications_version2')
          .select('first_name, last_name, middle_name, contact_number, status')
          .eq('assigned_bike_number', bikeNumber)
          .inFilter('status', ['approved', 'active', 'borrowed'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      return BorrowerInfo(
        firstName: response['first_name'] as String? ?? '',
        lastName: response['last_name'] as String? ?? '',
        middleName: response['middle_name'] as String? ?? '',
        contactNumber: response['contact_number'] as String? ?? '',
        status: response['status'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('Error loading borrower info: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REVERSE GEOCODING — returns a readable address (street/area level)
  // ══════════════════════════════════════════════════════════════════════════
  Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=$lat,$lng'
        '&key=$GOOGLE_MAPS_API_KEY',
      );

      final response = await http.get(url);
      if (response.statusCode != 200) return 'Unknown location';

      final data = json.decode(response.body);
      if (data['status'] != 'OK' ||
          data['results'] == null ||
          (data['results'] as List).isEmpty) {
        return 'Unknown location';
      }

      // Return the first result's formatted address — human-readable full address
      final results = data['results'] as List;
      return results[0]['formatted_address'] as String? ?? 'Unknown location';
    } catch (e) {
      debugPrint('Error reverse geocoding: $e');
      return 'Unknown location';
    }
  }

  Future<void> _updateMarkers() async {
    Set<Marker> newMarkers = {};

    for (var bike in _bikes) {
      final bitmapDescriptor = await _createPinMarker(bike.status);

      newMarkers.add(Marker(
        markerId: MarkerId('bike_${bike.id}'),
        position: LatLng(bike.latitude, bike.longitude),
        icon: bitmapDescriptor,
        onTap: () => _showBikeDetailsDialog(bike),
        infoWindow: InfoWindow(
          title: '🚲 ${bike.bikeNumber}',
          snippet: bike.status.toUpperCase(),
        ),
      ));
    }

    if (mounted) {
      setState(() => _markers = newMarkers);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // CUSTOM DIALOG — shows borrower info + location only
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _showBikeDetailsDialog(BikeLocation bike) async {
    // Show loading dialog first
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    // Fetch borrower and location in parallel
    final results = await Future.wait([
      _loadBorrowerInfo(bike.bikeNumber),
      _reverseGeocode(bike.latitude, bike.longitude),
    ]);

    final borrowerInfo = results[0] as BorrowerInfo?;
    final address = results[1] as String;

    // Close loading dialog
    if (mounted) Navigator.of(context).pop();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.pedal_bike, color: Colors.blue, size: 28),
            const SizedBox(width: 8),
            Text('Bike ${bike.bikeNumber}'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Status Badge ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _getStatusColor(bike.status),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  bike.status.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── Current Location ──────────────────────────────────────────
              _dialogInfoRow(Icons.location_on, 'Current Location', address),

              if (bike.lastLocationUpdate != null) ...[
                const SizedBox(height: 8),
                _dialogInfoRow(
                  Icons.access_time,
                  'Last Update',
                  _formatDateTime(bike.lastLocationUpdate!),
                ),
              ],

              // ── Borrower Info ─────────────────────────────────────────────
              if (borrowerInfo != null) ...[
                const Divider(height: 24),
                const Text(
                  'Current Borrower',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                _dialogInfoRow(
                  Icons.person,
                  'Name',
                  '${borrowerInfo.firstName} ${borrowerInfo.middleName} ${borrowerInfo.lastName}',
                ),
                const SizedBox(height: 8),
                _dialogInfoRow(Icons.phone, 'Contact', borrowerInfo.contactNumber),
                const SizedBox(height: 8),
                _dialogInfoRow(Icons.info_outline, 'Status', borrowerInfo.status),
              ] else ...[
                const Divider(height: 24),
                const Row(
                  children: [
                    Icon(Icons.person_off, size: 18, color: Colors.grey),
                    SizedBox(width: 8),
                    Text(
                      'No active borrower',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _dialogInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'available':
        return Colors.green;
      case 'in_use':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<BitmapDescriptor> _createPinMarker(String status) async {
    const double w = 48.0;
    const double h = 64.0;

    final Color fillColor;
    switch (status.toLowerCase()) {
      case 'available':
        fillColor = const Color(0xFF2ECC71);
        break;
      case 'in_use':
        fillColor = const Color(0xFFF39C12);
        break;
      default:
        fillColor = const Color(0xFFE74C3C);
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    final paint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    const double r = w * 0.42;
    const double cx = w / 2;
    const double cy = r + 2;

    final path = Path();
    final double angle = math.asin((cx - 4) / r);
    final lx = cx - r * math.cos(angle);
    final ly = cy + r * math.sin(angle);
    final rx = cx + r * math.cos(angle);
    final ry = ly;

    path.moveTo(cx, h - 2);
    path.lineTo(lx, ly);
    path.arcTo(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      math.pi / 2 + angle,
      -(math.pi + 2 * angle),
      false,
    );
    path.lineTo(rx, ry);
    path.lineTo(cx, h - 2);
    path.close();

    canvas.save();
    canvas.translate(1, 2);
    canvas.drawPath(path, shadowPaint);
    canvas.restore();

    canvas.drawPath(path, paint);

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    canvas.drawCircle(
      Offset(cx, cy),
      r * 0.38,
      Paint()..color = Colors.white,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(w.toInt(), h.toInt());
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
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.pedal_bike, color: Colors.blue, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Bike Tracking',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  onPressed: _loadData,
                  tooltip: 'Refresh',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // ── Map ─────────────────────────────────────────────────────
          AspectRatio(
            aspectRatio: 16 / 7,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _bikes.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_off, size: 48, color: Colors.grey),
                            SizedBox(height: 12),
                            Text(
                              'No bike locations available',
                              style: TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(_bikes[0].latitude, _bikes[0].longitude),
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
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// MODELS
// ══════════════════════════════════════════════════════════════════════════
class BikeLocation {
  final int id;
  final String bikeNumber;
  final double latitude;
  final double longitude;
  final String status;
  final DateTime? lastLocationUpdate;

  BikeLocation({
    required this.id,
    required this.bikeNumber,
    required this.latitude,
    required this.longitude,
    required this.status,
    this.lastLocationUpdate,
  });

  factory BikeLocation.fromJson(Map<String, dynamic> json) {
    return BikeLocation(
      id: json['id'] as int,
      bikeNumber: json['bike_number'] as String,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      status: json['status'] as String,
      lastLocationUpdate: json['last_location_update'] != null
          ? DateTime.parse(json['last_location_update'] as String)
          : null,
    );
  }
}

class BorrowerInfo {
  final String firstName;
  final String lastName;
  final String middleName;
  final String contactNumber;
  final String status;

  BorrowerInfo({
    required this.firstName,
    required this.lastName,
    required this.middleName,
    required this.contactNumber,
    required this.status,
  });
}