// lib/models/physical_examination_model.dart

import 'package:flutter/material.dart';

class PhysicalExaminationModel {
  final int id;
  final int applicationId;
  
  // BMI Data
  final double weight;
  final double height;
  final double bmi;
  final String bmiCategory;
  
  // Vital Signs
  final String bloodPressure;
  final String heartRate;
  
  // Physical Examination Findings (true = normal)
  final bool balance;
  final bool musculoskeletal;
  final bool lungs;
  final bool heart;
  final bool extremities;
  final bool hearing;
  final bool vision;
  
  // Remarks
  final String? remarks;
  
  // Physician Details
  final String physicianName;
  final String physicianLicenseNumber;
  final String physicianSignatureUrl;
  final DateTime examinationDate;
  
  // Metadata
  final DateTime createdAt;
  final String? createdBy;
  final DateTime updatedAt;

  PhysicalExaminationModel({
    required this.id,
    required this.applicationId,
    required this.weight,
    required this.height,
    required this.bmi,
    required this.bmiCategory,
    required this.bloodPressure,
    required this.heartRate,
    required this.balance,
    required this.musculoskeletal,
    required this.lungs,
    required this.heart,
    required this.extremities,
    required this.hearing,
    required this.vision,
    this.remarks,
    required this.physicianName,
    required this.physicianLicenseNumber,
    required this.physicianSignatureUrl,
    required this.examinationDate,
    required this.createdAt,
    this.createdBy,
    required this.updatedAt,
  });

  // From JSON (from Supabase)
  factory PhysicalExaminationModel.fromJson(Map<String, dynamic> json) {
    return PhysicalExaminationModel(
      id: json['id'] as int,
      applicationId: json['application_id'] as int,
      weight: (json['weight'] as num).toDouble(),
      height: (json['height'] as num).toDouble(),
      bmi: (json['bmi'] as num).toDouble(),
      bmiCategory: json['bmi_category'] as String,
      bloodPressure: json['blood_pressure'] as String,
      heartRate: json['heart_rate'] as String,
      balance: json['balance'] as bool? ?? false,
      musculoskeletal: json['musculoskeletal'] as bool? ?? false,
      lungs: json['lungs'] as bool? ?? false,
      heart: json['heart'] as bool? ?? false,
      extremities: json['extremities'] as bool? ?? false,
      hearing: json['hearing'] as bool? ?? false,
      vision: json['vision'] as bool? ?? false,
      remarks: json['remarks'] as String?,
      physicianName: json['physician_name'] as String,
      physicianLicenseNumber: json['physician_license_number'] as String,
      physicianSignatureUrl: json['physician_signature_url'] as String,
      examinationDate: DateTime.parse(json['examination_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      createdBy: json['created_by'] as String?,
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  // To JSON (for Supabase)
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'application_id': applicationId,
      'weight': weight,
      'height': height,
      'bmi': bmi,
      'bmi_category': bmiCategory,
      'blood_pressure': bloodPressure,
      'heart_rate': heartRate,
      'balance': balance,
      'musculoskeletal': musculoskeletal,
      'lungs': lungs,
      'heart': heart,
      'extremities': extremities,
      'hearing': hearing,
      'vision': vision,
      'remarks': remarks,
      'physician_name': physicianName,
      'physician_license_number': physicianLicenseNumber,
      'physician_signature_url': physicianSignatureUrl,
      'examination_date': examinationDate.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'created_by': createdBy,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  // To JSON for INSERT (without id, created_at, updated_at - Supabase auto-generates these)
  Map<String, dynamic> toInsertJson() {
    return {
      'application_id': applicationId,
      'weight': weight,
      'height': height,
      'bmi': bmi,
      'bmi_category': bmiCategory,
      'blood_pressure': bloodPressure,
      'heart_rate': heartRate,
      'balance': balance,
      'musculoskeletal': musculoskeletal,
      'lungs': lungs,
      'heart': heart,
      'extremities': extremities,
      'hearing': hearing,
      'vision': vision,
      'remarks': remarks,
      'physician_name': physicianName,
      'physician_license_number': physicianLicenseNumber,
      'physician_signature_url': physicianSignatureUrl,
      'examination_date': examinationDate.toIso8601String(),
      'created_by': createdBy,
    };
  }

  // Copy with method for easy updates
  PhysicalExaminationModel copyWith({
    int? id,
    int? applicationId,
    double? weight,
    double? height,
    double? bmi,
    String? bmiCategory,
    String? bloodPressure,
    String? heartRate,
    bool? balance,
    bool? musculoskeletal,
    bool? lungs,
    bool? heart,
    bool? extremities,
    bool? hearing,
    bool? vision,
    String? remarks,
    String? physicianName,
    String? physicianLicenseNumber,
    String? physicianSignatureUrl,
    DateTime? examinationDate,
    DateTime? createdAt,
    String? createdBy,
    DateTime? updatedAt,
  }) {
    return PhysicalExaminationModel(
      id: id ?? this.id,
      applicationId: applicationId ?? this.applicationId,
      weight: weight ?? this.weight,
      height: height ?? this.height,
      bmi: bmi ?? this.bmi,
      bmiCategory: bmiCategory ?? this.bmiCategory,
      bloodPressure: bloodPressure ?? this.bloodPressure,
      heartRate: heartRate ?? this.heartRate,
      balance: balance ?? this.balance,
      musculoskeletal: musculoskeletal ?? this.musculoskeletal,
      lungs: lungs ?? this.lungs,
      heart: heart ?? this.heart,
      extremities: extremities ?? this.extremities,
      hearing: hearing ?? this.hearing,
      vision: vision ?? this.vision,
      remarks: remarks ?? this.remarks,
      physicianName: physicianName ?? this.physicianName,
      physicianLicenseNumber: physicianLicenseNumber ?? this.physicianLicenseNumber,
      physicianSignatureUrl: physicianSignatureUrl ?? this.physicianSignatureUrl,
      examinationDate: examinationDate ?? this.examinationDate,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Check if all examination findings are normal
  bool get isAllNormal {
    return balance && 
           musculoskeletal && 
           lungs && 
           heart && 
           extremities && 
           hearing && 
           vision;
  }

  // Get list of abnormal findings
  List<String> get abnormalFindings {
    final List<String> abnormal = [];
    if (!balance) abnormal.add('Balance');
    if (!musculoskeletal) abnormal.add('Musculo-Skeletal');
    if (!lungs) abnormal.add('Lungs');
    if (!heart) abnormal.add('Heart');
    if (!extremities) abnormal.add('Extremities');
    if (!hearing) abnormal.add('Hearing');
    if (!vision) abnormal.add('Vision');
    return abnormal;
  }

  // Get BMI status color
  Color getBMIColor() {
    if (bmi < 18.5) return const Color(0xFFFF9800); // Orange - Underweight
    if (bmi < 25.0) return const Color(0xFF4CAF50); // Green - Healthy
    if (bmi < 30.0) return const Color(0xFFFF9800); // Orange - Overweight
    return const Color(0xFFF44336); // Red - Obesity
  }

  @override
  String toString() {
    return 'PhysicalExaminationModel(id: $id, applicationId: $applicationId, bmi: $bmi, bmiCategory: $bmiCategory, physician: $physicianName)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
  
    return other is PhysicalExaminationModel &&
      other.id == id &&
      other.applicationId == applicationId;
  }

  @override
  int get hashCode => id.hashCode ^ applicationId.hashCode;
}