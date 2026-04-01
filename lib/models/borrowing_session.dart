// BORROWING SESSION MODEL
class BorrowingSessionModel {
  final int id;
  final String userId;
  final String? fullName; // ✅ ADD THIS
  final int bikeId;
  final int? applicationId;
  final String sessionType;
  final DateTime startTime;
  final DateTime? endTime;
  final int? durationMinutes;
  final double? startLocationLat;
  final double? startLocationLng;
  final double? endLocationLat;
  final double? endLocationLng;
  final String? destinationAddress;
  final String qrCodeData;
  final DateTime qrCodeGeneratedAt;
  final DateTime qrCodeExpiresAt;
  final bool qrCodeScanned;
  final String status;
  final double totalDistanceKm;
  final bool isParked;
  final DateTime? parkStartTime;
  final DateTime? parkEndTime;
  final DateTime? startDate;


  BorrowingSessionModel({
    required this.id,
    required this.userId,
    this.fullName,
    required this.bikeId,
    this.applicationId,
    required this.sessionType,
    required this.startTime,
    this.endTime,
    this.durationMinutes,
    this.startLocationLat,
    this.startLocationLng,
    this.endLocationLat,
    this.endLocationLng,
    this.destinationAddress,
    required this.qrCodeData,
    required this.qrCodeGeneratedAt,
    required this.qrCodeExpiresAt,
    this.qrCodeScanned = false,
    required this.status,
    this.totalDistanceKm = 0,
    this.isParked = false,
    this.parkStartTime,
    this.parkEndTime,
    this.startDate, // ✅ added
  });


  factory BorrowingSessionModel.fromJson(Map<String, dynamic> json) {
    return BorrowingSessionModel(
      id: json['id'],
      userId: json['user_id'],
      fullName: json['full_name'], // ✅ ADD THIS
      bikeId: json['bike_id'],
      applicationId: json['application_id'],
      sessionType: json['session_type'],
      startTime: DateTime.parse(json['start_time']),
      endTime: json['end_time'] != null
          ? DateTime.parse(json['end_time'])
          : null,
      durationMinutes: json['duration_minutes'],
      startLocationLat: json['start_location_lat']?.toDouble(),
      startLocationLng: json['start_location_lng']?.toDouble(),
      endLocationLat: json['end_location_lat']?.toDouble(),
      endLocationLng: json['end_location_lng']?.toDouble(),
      destinationAddress: json['destination_address'],
      qrCodeData: json['qr_code_data'],
      qrCodeGeneratedAt: DateTime.parse(json['qr_code_generated_at']),
      qrCodeExpiresAt: DateTime.parse(json['qr_code_expires_at']),
      qrCodeScanned: json['qr_code_scanned'] ?? false,
      status: json['status'],
      totalDistanceKm: json['total_distance_km']?.toDouble() ?? 0,
      isParked: json['is_parked'] ?? false,
      parkStartTime: json['park_start_time'] != null
          ? DateTime.parse(json['park_start_time'])
          : null,
      parkEndTime: json['park_end_time'] != null
          ? DateTime.parse(json['park_end_time'])
          : null,
      startDate:
          json['start_date'] !=
              null // ✅ added
          ? DateTime.parse(json['start_date'])
          : null,
    );
  }


  bool get isQRCodeExpired => DateTime.now().isAfter(qrCodeExpiresAt);


  Duration get rideDuration {
    final end = endTime ?? DateTime.now();
    return end.difference(startTime);
  }
}





