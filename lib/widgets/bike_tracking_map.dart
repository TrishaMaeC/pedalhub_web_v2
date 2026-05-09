import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  List<DateTime> _historyTimestamps = []; 

  RealtimeChannel? _locationChannel;

  static const int BIKE_ID = 12;

  static const String GOOGLE_MAPS_API_KEY = 'AIzaSyB8_MlXbJKFGO73LhDFqqhxX_gHEziHUA0';

  List<BikeLocation> _bikes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToLocationUpdates();
  }

  @override
  void dispose() {
    _locationChannel?.unsubscribe();
    _mapController?.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REALTIME SUBSCRIPTION
  // ══════════════════════════════════════════════════════════════════════════
void _subscribeToLocationUpdates() {
  debugPrint('🚀 Setting up realtime subscription...');
  
  _locationChannel = supabase
      .channel('bike_locations_channel')
      .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'bike_locations',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'bike_id',
          value: BIKE_ID,
        ),
        callback: (payload) async {
          debugPrint('🔥🔥🔥 REALTIME FIRED! 🔥🔥🔥');
          debugPrint('Payload: $payload');
          
          final newRecord = payload.newRecord;
          final lat = (newRecord['latitude'] as num).toDouble();
          final lng = (newRecord['longitude'] as num).toDouble();

          debugPrint('📍 New coordinates: $lat, $lng');

          if (lat == 0.0 && lng == 0.0) {
            debugPrint('⚠️ Invalid coordinates (0,0), skipping...');
            return;
          }

          final newPoint = LatLng(lat, lng);
          final newTimestamp = DateTime.now();

          if (!mounted) {
            debugPrint('⚠️ Widget not mounted, skipping...');
            return;
          }

          debugPrint('✅ Updating state...');
          
          setState(() {
            _historyPoints.add(newPoint);
            _historyTimestamps.add(newTimestamp);
            _updatePolyline();
          });

          debugPrint('✅ History updated. Points: ${_historyPoints.length}');

          debugPrint('🔄 Reloading bike locations...');
          await _loadBikeLocations();
          
          debugPrint('✅ Bike locations reloaded. Bikes count: ${_bikes.length}');

          debugPrint('📹 Animating camera to new position...');
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(newPoint),
          );
          
          debugPrint('✅ Camera animated!');
        },
      )
      .subscribe((status, error) {
        debugPrint('📡 Channel status: $status');
        if (error != null) {
          debugPrint('❌ Channel error: $error');
        }
        
        // Print kung anong event ang naka-subscribe
        if (status == RealtimeSubscribeStatus.subscribed) {
          debugPrint('✅ Successfully subscribed to bike_locations!');
          debugPrint('👂 Listening for bike_id: $BIKE_ID');
        } else if (status == RealtimeSubscribeStatus.channelError) {
          debugPrint('❌ Channel error! Realtime might not work.');
        } else if (status == RealtimeSubscribeStatus.timedOut) {
          debugPrint('⏱️ Subscription timed out!');
        } else if (status == RealtimeSubscribeStatus.closed) {
          debugPrint('🚪 Channel closed!');
        }
      });
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
      await _updateMarkers(); // Ito yung nag-uupdate ng marker

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

  // ══════════════════════════════════════════════════════════════════════════
  // LOCATION HISTORY — Option 1 + 2 + 3 combined
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _loadLocationHistory() async {
  try {
    // Kunin lahat ng points from last 30 minutes
    final cutoff = DateTime.now()
        .subtract(const Duration(minutes: 30))
        .toIso8601String();

    final response = await supabase
        .from('bike_locations')
        .select('latitude, longitude, created_at')
        .eq('bike_id', BIKE_ID)
        .gte('created_at', cutoff)
        .order('created_at');
        // REMOVED .limit(100) - ito yung nagpapawala ng polyline!

    if (!mounted) return;

    final List<LatLng> newPoints = [];
    final List<DateTime> newTimestamps = [];
    for (final p in (response as List)) {
      final lat = (p['latitude'] as num).toDouble();
      final lng = (p['longitude'] as num).toDouble();
      if (lat == 0.0 && lng == 0.0) continue;
      newPoints.add(LatLng(lat, lng));
      newTimestamps.add(DateTime.parse(p['created_at'] as String));
    }

    // Clear polyline kung walang points
    if (newPoints.isEmpty) {
      setState(() {
        _historyPoints = [];
        _polylines = {};
      });
      return;
    }

    // Update kung may changes
    // Update kung may changes
    if (newPoints.length != _historyPoints.length) {
      setState(() {
        _historyPoints = newPoints;
        _historyTimestamps = newTimestamps;
        _updatePolyline();
      });
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
          .select('first_name, last_name, middle_name, phone_number, status')
          .eq('assigned_bike_number', bikeNumber)
          .inFilter('status', ['in_use'])
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      return BorrowerInfo(
        firstName: response['first_name'] as String? ?? '',
        lastName: response['last_name'] as String? ?? '',
        middleName: response['middle_name'] as String? ?? '',
        phoneNumber: response['phone_number'] as String? ?? '',
        status: response['status'] as String? ?? '',
      );
    } catch (e) {
      debugPrint('Error loading borrower info: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // REVERSE GEOCODING
  // ══════════════════════════════════════════════════════════════════════════
  Future<String> _reverseGeocode(double lat, double lng) async {
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=$lat,$lng'
        '&key=$GOOGLE_MAPS_API_KEY',
      );

      final response = await http.get(url);

      if (response.statusCode != 200) {
        return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      }

      final data = json.decode(response.body);

      if (data['status'] != 'OK') {
        return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      }

      final results = data['results'] as List;
      if (results.isEmpty) {
        return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      }

      final components = results[0]['address_components'] as List;

      String? barangay;
      String? city;

      for (var c in components) {
        final types = List<String>.from(c['types']);

        if (types.contains('sublocality') ||
            types.contains('sublocality_level_1') ||
            types.contains('neighborhood')) {
          barangay = c['long_name'];
        }

        if (types.contains('locality')) {
          city = c['long_name'];
        }
      }

      if (barangay != null && city != null) {
        return '$barangay, $city';
      } else if (city != null) {
        return city;
      } else {
        final fallback = results[0]['formatted_address'];
        return fallback ?? '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
      }
    } catch (e) {
      debugPrint('Reverse geocode error: $e');
      return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
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
  // BIKE DETAILS DIALOG
  // ══════════════════════════════════════════════════════════════════════════
  Future<void> _showBikeDetailsDialog(BikeLocation bike) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    final BorrowerInfo? borrowerInfo = await _loadBorrowerInfo(bike.bikeNumber);
    final String address = await _reverseGeocode(bike.latitude, bike.longitude);

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
            Text(' ${bike.bikeNumber}'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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

              _dialogInfoRow(Icons.location_on, 'Current Location', address),

              if (bike.lastLocationUpdate != null) ...[
                const SizedBox(height: 8),
                _dialogInfoRow(
                  Icons.access_time,
                  'Last Update',
                  _formatDateTime(bike.lastLocationUpdate!),
                ),
              ],

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
                _dialogInfoRow(Icons.phone, 'Contact', borrowerInfo.phoneNumber),
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
  final local = dt.toLocal();
  
  final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  
  // Convert to 12-hour format
  final hour12 = local.hour > 12 ? local.hour - 12 : (local.hour == 0 ? 12 : local.hour);
  final period = local.hour >= 12 ? 'PM' : 'AM';
  
  return '${months[local.month - 1]} ${local.day}, ${local.year} '
         '${hour12.toString().padLeft(2, '0')}:'
         '${local.minute.toString().padLeft(2, '0')} $period';
}

  Future<BitmapDescriptor> _createPinMarker(String status) async {
  return await BitmapDescriptor.fromAssetImage(
    const ImageConfiguration(size: Size(45, 45)),
    'assets/images/bike_marker.png',
  );
}

 void _updatePolyline() {
  if (_historyPoints.isEmpty) {
    _polylines = {};
    return;
  }

  // Kailangan natin ng timestamps para malaman yung gap
  // So gagawa tayo ng bagong version na may timestamps
  _updatePolylineWithGaps();
}

void _updatePolylineWithGaps() {
  if (_historyPoints.isEmpty || _historyTimestamps.isEmpty) {
    _polylines = {};
    return;
  }

  if (_historyPoints.length == 1) {
    _polylines = {};
    return;
  }

  Set<Polyline> newPolylines = {};
  List<LatLng> currentSolidSegment = [_historyPoints[0]];
  int segmentIndex = 0;

  for (int i = 1; i < _historyPoints.length; i++) {
    final timeDiff = _historyTimestamps[i].difference(_historyTimestamps[i - 1]);
    final gapInMinutes = timeDiff.inMinutes;

    if (gapInMinutes >= 3) {
      // MAY GAP!
      
      // 1. Save yung current solid segment (kung may laman)
      if (currentSolidSegment.length > 1) {
        newPolylines.add(Polyline(
          polylineId: PolylineId('solid_$segmentIndex'),
          points: List.from(currentSolidSegment),
          color: Colors.blue,
          width: 4,
        ));
        segmentIndex++;
      }

      // 2. Gawa ng dashed line connecting the gap
      newPolylines.add(Polyline(
        polylineId: PolylineId('dashed_$segmentIndex'),
        points: [_historyPoints[i - 1], _historyPoints[i]],
        color: Colors.blue.withOpacity(0.6),
        width: 4,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ));
      segmentIndex++;

      // 3. Start new solid segment from current point
      currentSolidSegment = [_historyPoints[i]];
      
    } else {
      // WALANG GAP - ituloy yung solid segment
      currentSolidSegment.add(_historyPoints[i]);
    }
  }

  // Save yung last solid segment
  if (currentSolidSegment.length > 1) {
    newPolylines.add(Polyline(
      polylineId: PolylineId('solid_$segmentIndex'),
      points: currentSolidSegment,
      color: Colors.blue,
      width: 4,
    ));
  }

  _polylines = newPolylines;
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
  final String phoneNumber;
  final String status;

  BorrowerInfo({
    required this.firstName,
    required this.lastName,
    required this.middleName,
    required this.phoneNumber,
    required this.status,
  });
}