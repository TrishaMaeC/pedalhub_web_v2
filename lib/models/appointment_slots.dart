import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AppointmentSlot {
  final int id;
  final DateTime appointmentDate;
  final TimeOfDay appointmentTime;
  final bool isAvailable;
  final int maxSlots;
  final int bookedSlots;
  final DateTime createdAt;

  AppointmentSlot({
    required this.id,
    required this.appointmentDate,
    required this.appointmentTime,
    required this.isAvailable,
    required this.maxSlots,
    required this.bookedSlots,
    required this.createdAt,
  });

  factory AppointmentSlot.fromJson(Map<String, dynamic> json) {
    final timeString = json['appointment_time'] as String;
    final timeParts = timeString.split(':');
    
    return AppointmentSlot(
      id: json['id'] as int,
      appointmentDate: DateTime.parse(json['appointment_date'] as String),
      appointmentTime: TimeOfDay(
        hour: int.parse(timeParts[0]),
        minute: int.parse(timeParts[1]),
      ),
      isAvailable: json['is_available'] as bool? ?? true,
      maxSlots: json['max_slots'] as int? ?? 1,
      bookedSlots: json['booked_slots'] as int? ?? 0,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'appointment_date': appointmentDate.toIso8601String().split('T')[0],
      'appointment_time': '${appointmentTime.hour.toString().padLeft(2, '0')}:${appointmentTime.minute.toString().padLeft(2, '0')}:00',
      'is_available': isAvailable,
      'max_slots': maxSlots,
      'booked_slots': bookedSlots,
      'created_at': createdAt.toIso8601String(),
    };
  }

  // Computed properties
  int get availableSlots => maxSlots - bookedSlots;
  
  bool get isFull => bookedSlots >= maxSlots;
  
  String get formattedDate => DateFormat('MMM dd, yyyy').format(appointmentDate);
  
  String get formattedTime {
    final hour = appointmentTime.hour > 12 
        ? appointmentTime.hour - 12 
        : appointmentTime.hour == 0 ? 12 : appointmentTime.hour;
    final period = appointmentTime.hour >= 12 ? 'PM' : 'AM';
    final minute = appointmentTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  String get formattedDateTime => '$formattedDate at $formattedTime';

  // Status helper
  Color getStatusColor() {
    if (!isAvailable) return Colors.grey;
    if (isFull) return Colors.orange;
    return Colors.green;
  }

  String getStatusText() {
    if (!isAvailable) return 'Disabled';
    if (isFull) return 'Full';
    return 'Available';
  }

  // Helper to check if slot is in the past
  bool get isPast {
    final now = DateTime.now();
    final slotDateTime = DateTime(
      appointmentDate.year,
      appointmentDate.month,
      appointmentDate.day,
      appointmentTime.hour,
      appointmentTime.minute,
    );
    return slotDateTime.isBefore(now);
  }

  // Helper to check if slot is today
  bool get isToday {
    final now = DateTime.now();
    return appointmentDate.year == now.year &&
           appointmentDate.month == now.month &&
           appointmentDate.day == now.day;
  }

  // Copy with method for updates
  AppointmentSlot copyWith({
    int? id,
    DateTime? appointmentDate,
    TimeOfDay? appointmentTime,
    bool? isAvailable,
    int? maxSlots,
    int? bookedSlots,
    DateTime? createdAt,
  }) {
    return AppointmentSlot(
      id: id ?? this.id,
      appointmentDate: appointmentDate ?? this.appointmentDate,
      appointmentTime: appointmentTime ?? this.appointmentTime,
      isAvailable: isAvailable ?? this.isAvailable,
      maxSlots: maxSlots ?? this.maxSlots,
      bookedSlots: bookedSlots ?? this.bookedSlots,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}