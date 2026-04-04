import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// BORROWING APPLICATION MODEL - VERSION 2
class BorrowingApplicationV2Model {
  final int id;
  final String userId;
  final String? controlNumber;
  final String lastName;
  final String firstName;
  final String? middleName;
  final String? idNo;
  final String? sex;
  final DateTime dateOfBirth;
  final String? phoneNumber;
  final String? emailAddress;
  final String? collegeOffice;
  final String? houseNo;
  final String? streetName;
  final String? barangay;
  final String? municipality;
  final String? province;
  final double? familyIncome;
  final double? distanceFromCampus;
  final String? intended;
  final String? durationOfUse;
  final String? eSignatureUrl;
  final DateTime? dateSigned;
  final String? applicationPdfUrl;
  final String status;
  final String? userType;
  final String? campus;
  final String? hrmoOsdSignature;
  final String? hrmoOsdName;
  final DateTime? hrmoOsdDateSigned;
  final int? medicalAppointmentId;
  final String? viceSignatureUrl;
  final String? viceOfficerName;
  final DateTime? viceDateSigned;
  final String? gsoSignatureUrl;
  final String? gsoOfficerName;
  final DateTime? gsoDateSigned;
  final int? financialNeedScore;
  final int? distanceScore;
  final int? fcfsStudentScore;
  final int? assignedBikeId;
  final String? assignedBikeNumber;
  final double? finalPenalty;
  final int? workCategoryRating;
  final int? fcfsPersonnelScore;
  final String? osdHrmoPdfUrl;
  final String? finalApplicantSignatureUrl;
  final String? renewalPdfUrl;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;
  
  // REASSESSMENT FIELDS
  final bool? reassessmentRequested;
  final DateTime? reassessmentRequestDate;
  final bool? reassessmentApproved;
  final String? reassessmentReviewedBy;
  final DateTime? reassessmentReviewedAt;
  final String? reassessmentRemarks;

  // ✅ NEW AUTOMATED SYSTEM FIELDS
  final String? decisionSource; // 'SYSTEM' or 'MANUAL' or null
  final double? weightedScore;  // Computed ranking score (nullable - null means no ranking was needed)

  BorrowingApplicationV2Model({
    required this.id,
    required this.userId,
    this.controlNumber,
    required this.lastName,
    required this.firstName,
    this.middleName,
    this.idNo,
    this.sex,
    required this.dateOfBirth,
    this.phoneNumber,
    this.emailAddress,
    this.collegeOffice,
    this.houseNo,
    this.streetName,
    this.barangay,
    this.municipality,
    this.province,
    this.familyIncome,
    this.distanceFromCampus,
    this.intended,
    this.durationOfUse,
    this.eSignatureUrl,
    this.dateSigned,
    this.applicationPdfUrl,
    required this.status,
    this.userType,
    this.campus,
    this.hrmoOsdSignature,
    this.hrmoOsdName,
    this.hrmoOsdDateSigned,
    this.medicalAppointmentId,
    this.viceSignatureUrl,
    this.viceOfficerName,
    this.viceDateSigned,
    this.gsoSignatureUrl,
    this.gsoOfficerName,
    this.gsoDateSigned,
    this.financialNeedScore,
    this.distanceScore,
    this.fcfsStudentScore,
    this.assignedBikeId,
    this.assignedBikeNumber,
    this.finalPenalty,
    this.workCategoryRating,
    this.fcfsPersonnelScore,
    this.osdHrmoPdfUrl,
    this.finalApplicantSignatureUrl,
    this.renewalPdfUrl,
    this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
    this.reassessmentRequested,
    this.reassessmentRequestDate,
    this.reassessmentApproved,
    this.reassessmentReviewedBy,
    this.reassessmentReviewedAt,
    this.reassessmentRemarks,
    // New fields
    this.decisionSource,
    this.weightedScore,
  });

  // ─────────────────────────────────────────────
  // HELPER: Determine applicant type
  // ─────────────────────────────────────────────
  bool get isStudent => userType?.toLowerCase() == 'student';
  bool get isPersonnel => userType?.toLowerCase() == 'personnel';

  // ─────────────────────────────────────────────
  // HELPER: Check if processed by automated system
  // ─────────────────────────────────────────────
  bool get isSystemProcessed => decisionSource == 'SYSTEM';
  bool get wasRanked => weightedScore != null;

  // ─────────────────────────────────────────────
  // HELPER: Get full address
  // ─────────────────────────────────────────────
  String get fullAddress {
    final parts = [
      houseNo,
      streetName,
      barangay,
      municipality,
      province,
    ].where((s) => s != null && s.isNotEmpty).toList();

    return parts.join(', ');
  }

  String get presentAddress {
    return fullAddress;
  }

  // ─────────────────────────────────────────────
  // HELPER: Get full name
  // ─────────────────────────────────────────────
  String get fullName {
    if (middleName != null && middleName!.isNotEmpty) {
      return '$firstName ${middleName![0]}. $lastName';
    }
    return '$firstName $lastName';
  }

  factory BorrowingApplicationV2Model.fromJson(Map<String, dynamic> json) {
    return BorrowingApplicationV2Model(
      id: json['id'] as int,
      userId: (json['user_id'] as String?) ?? '',
      controlNumber: json['control_number'] as String?,
      lastName: (json['last_name'] as String?) ?? '',
      firstName: (json['first_name'] as String?) ?? '',
      middleName: json['middle_name'] as String?,
      idNo: json['id_no'] as String?,
      sex: json['sex'] as String?,
      dateOfBirth: json['date_of_birth'] != null
          ? DateTime.tryParse(json['date_of_birth'] as String) ?? DateTime.now()
          : DateTime.now(),
      phoneNumber: json['phone_number'] as String?,
      emailAddress: json['email_address'] as String?,
      collegeOffice: json['college_office'] as String?,
      houseNo: json['house_no'] as String?,
      streetName: json['street_name'] as String?,
      barangay: json['barangay'] as String?,
      municipality: json['municipality'] as String?,
      province: json['province'] as String?,
      familyIncome: json['family_income'] != null
          ? (json['family_income'] as num).toDouble()
          : null,
      distanceFromCampus: json['distance_from_campus'] != null
          ? (json['distance_from_campus'] as num).toDouble()
          : null,
      intended: json['intended'] as String?,
      durationOfUse: json['duration_of_use'] as String?,
      eSignatureUrl: json['e_signature_url'] as String?,
      dateSigned: json['date_signed'] != null
          ? DateTime.tryParse(json['date_signed'] as String)
          : null,
      applicationPdfUrl: json['application_pdf_url'] as String?,
      status: (json['status'] as String?) ?? 'pending_application',
      userType: json['user_type'] as String?,
      campus: json['campus'] as String?,
      hrmoOsdSignature: json['hrmo_osd_signature'] as String?,
      hrmoOsdName: json['hrmo_osd_name'] as String?,
      hrmoOsdDateSigned: json['hrmo_osd_date_signed'] != null
          ? DateTime.tryParse(json['hrmo_osd_date_signed'] as String)
          : null,
      medicalAppointmentId: json['medical_appointment_id'] as int?,
      viceSignatureUrl: json['vice_signature_url'] as String?,
      viceOfficerName: json['vice_officer_name'] as String?,
      viceDateSigned: json['vice_date_signed'] != null
          ? DateTime.tryParse(json['vice_date_signed'] as String)
          : null,
      gsoSignatureUrl: json['gso_signature_url'] as String?,
      gsoOfficerName: json['gso_officer_name'] as String?,
      gsoDateSigned: json['gso_date_signed'] != null
          ? DateTime.tryParse(json['gso_date_signed'] as String)
          : null,
      financialNeedScore: json['financial_need_score'] as int?,
      distanceScore: json['distance_score'] as int?,
      fcfsStudentScore: json['fcfs_student_score'] as int?,
      assignedBikeId: json['assigned_bike_id'] as int?,
      assignedBikeNumber: json['assigned_bike_number'] as String?,
      finalPenalty: json['final_penalty'] != null
          ? (json['final_penalty'] as num).toDouble()
          : null,
      workCategoryRating: json['work_category_rating'] as int?,
      fcfsPersonnelScore: json['fcfs_personnel_score'] as int?,
      osdHrmoPdfUrl: json['osd_hrmo_pdf_url'] as String?,
      finalApplicantSignatureUrl: json['final_applicant_signature_url'] as String?,
      renewalPdfUrl: json['renewal_pdf_url'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String) ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now(),
      reassessmentRequested: json['reassessment_requested'] as bool?,
      reassessmentRequestDate: json['reassessment_request_date'] != null
          ? DateTime.tryParse(json['reassessment_request_date'] as String)
          : null,
      reassessmentApproved: json['reassessment_approved'] as bool?,
      reassessmentReviewedBy: json['reassessment_reviewed_by'] as String?,
      reassessmentReviewedAt: json['reassessment_reviewed_at'] != null
          ? DateTime.tryParse(json['reassessment_reviewed_at'] as String)
          : null,
      reassessmentRemarks: json['reassessment_remarks'] as String?,
      // New automated system fields
      decisionSource: json['decision_source'] as String?,
      weightedScore: json['weighted_score'] != null
          ? (json['weighted_score'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'control_number': controlNumber,
      'last_name': lastName,
      'first_name': firstName,
      'middle_name': middleName,
      'id_no': idNo,
      'sex': sex,
      'date_of_birth': dateOfBirth.toIso8601String().split('T')[0],
      'phone_number': phoneNumber,
      'email_address': emailAddress,
      'college_office': collegeOffice,
      'house_no': houseNo,
      'street_name': streetName,
      'barangay': barangay,
      'municipality': municipality,
      'province': province,
      'family_income': familyIncome,
      'distance_from_campus': distanceFromCampus,
      'intended': intended,
      'duration_of_use': durationOfUse,
      'e_signature_url': eSignatureUrl,
      'date_signed': dateSigned?.toIso8601String(),
      'application_pdf_url': applicationPdfUrl,
      'status': status,
      'user_type': userType,
      'campus': campus,
      'hrmo_osd_signature': hrmoOsdSignature,
      'hrmo_osd_name': hrmoOsdName,
      'hrmo_osd_date_signed': hrmoOsdDateSigned?.toIso8601String(),
      'medical_appointment_id': medicalAppointmentId,
      'vice_signature_url': viceSignatureUrl,
      'vice_officer_name': viceOfficerName,
      'vice_date_signed': viceDateSigned?.toIso8601String(),
      'gso_signature_url': gsoSignatureUrl,
      'gso_officer_name': gsoOfficerName,
      'gso_date_signed': gsoDateSigned?.toIso8601String(),
      'financial_need_score': financialNeedScore,
      'distance_score': distanceScore,
      'fcfs_student_score': fcfsStudentScore,
      'assigned_bike_id': assignedBikeId,
      'assigned_bike_number': assignedBikeNumber,
      'final_penalty': finalPenalty,
      'work_category_rating': workCategoryRating,
      'fcfs_personnel_score': fcfsPersonnelScore,
      'osd_hrmo_pdf_url': osdHrmoPdfUrl,
      'final_applicant_signature_url': finalApplicantSignatureUrl,
      'renewal_pdf_url': renewalPdfUrl,
      'rejection_reason': rejectionReason,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'reassessment_requested': reassessmentRequested,
      'reassessment_request_date': reassessmentRequestDate?.toIso8601String(),
      'reassessment_approved': reassessmentApproved,
      'reassessment_reviewed_by': reassessmentReviewedBy,
      'reassessment_reviewed_at': reassessmentReviewedAt?.toIso8601String(),
      'reassessment_remarks': reassessmentRemarks,
      // New automated system fields
      'decision_source': decisionSource,
      'weighted_score': weightedScore,
    };
  }

  // ─────────────────────────────────────────────
  // STATUS HELPERS
  // ─────────────────────────────────────────────
  String getStatusText() {
    switch (status) {
      case 'pending_application':
        return 'Application Pending';
      case 'hrmo_approved':
        return 'HRMO Approved';
      case 'osd_approved':
        return 'OSD Approved';
      case 'medical_scheduled':
        return 'Medical Appointment Scheduled';
      case 'fit_to_use':
        return 'Fit to Use - Awaiting Automated System';
      case 'vice_pending':
        return 'Automated Ranking in Progress';
      case 'for_release':
        return 'Auto-Approved - For Release';
      case 'vice_rejected':
        return 'Not Selected by Ranking System';
      case 'health_rejected':
        return 'Health Rejected';
      case 'for_reassessment':
        return 'For Reassessment';
      case 'active':
        return 'Active Borrower';
      case 'completed':
        return 'Borrowing Completed';
      case 'overdue':
        return 'Overdue';
      case 'terminated':
        return 'Terminated';
      case 'cancelled':
        return 'Application Cancelled';
      case 'renewal_pending':
        return 'Renewal Pending';
      case 'renewal_approved':
        return 'Renewal Approved';
      default:
        return status.replaceAll('_', ' ').toUpperCase();
    }
  }

  Color getStatusColor() {
    switch (status) {
      case 'for_release':
      case 'active':
      case 'renewal_approved':
        return Colors.green;
      case 'fit_to_use':
      case 'vice_pending':
      case 'medical_scheduled':
      case 'hrmo_approved':
      case 'osd_approved':
      case 'pending_application':
      case 'renewal_pending':
        return Colors.orange;
      case 'vice_rejected':
      case 'health_rejected':
      case 'cancelled':
        return Colors.red;
      case 'overdue':
        return const Color(0xFFE64A19);
      case 'terminated':
        return const Color(0xFF424242);
      case 'completed':
        return Colors.blue;
      case 'for_reassessment':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  // ─────────────────────────────────────────────
  // SCORE BREAKDOWN — handles both student & personnel
  // ─────────────────────────────────────────────
  String get scoreBreakdown {
    if (isStudent) {
      if (financialNeedScore == null && distanceScore == null && fcfsStudentScore == null) {
        return 'Not yet scored';
      }
      return 'Financial: ${financialNeedScore ?? '-'}/5 · '
          'Distance: ${distanceScore ?? '-'}/5 · '
          'FCFS: ${fcfsStudentScore ?? '-'}/5';
    } else if (isPersonnel) {
      if (workCategoryRating == null && fcfsPersonnelScore == null) {
        return 'Not yet scored';
      }
      return 'Work Category: ${workCategoryRating ?? '-'}/5 · '
          'FCFS: ${fcfsPersonnelScore ?? '-'}/5';
    }
    return 'Unknown applicant type';
  }

  // ─────────────────────────────────────────────
  // AUTOMATED SYSTEM SCORE BREAKDOWN
  // ─────────────────────────────────────────────
  String get automatedScoreBreakdown {
    if (!isSystemProcessed) {
      return 'Not processed by automated system';
    }

    if (!wasRanked) {
      return 'Auto-approved (No ranking needed - applicants ≤ bikes)';
    }

    if (isStudent) {
      final financial = financialNeedScore ?? 0;
      final distance = distanceScore ?? 0;
      return 'Financial Need: $financial/3 · Distance: $distance/3 · Total: ${weightedScore?.toStringAsFixed(2) ?? '0.00'}/6';
    } else if (isPersonnel) {
      final workCategory = workCategoryRating ?? 0;
      final distance = distanceScore ?? 0;
      return 'Work Category: $workCategory/3 · Distance: $distance/3 · Total: ${weightedScore?.toStringAsFixed(2) ?? '0.00'}/6';
    }

    return 'Score: ${weightedScore?.toStringAsFixed(2) ?? 'N/A'}';
  }

  // ─────────────────────────────────────────────
  // FORMATTERS
  // ─────────────────────────────────────────────
  String get formattedIncome {
    if (familyIncome == null) return 'N/A';
    final formatter = NumberFormat.simpleCurrency(name: 'PHP', decimalDigits: 0);
    return formatter.format(familyIncome);
  }

  String get formattedDistance {
    if (distanceFromCampus == null) return 'N/A';
    return '${distanceFromCampus!.toStringAsFixed(2)} km';
  }

  String get formattedPenalty {
    if (finalPenalty == null) return 'N/A';
    final formatter = NumberFormat.simpleCurrency(name: 'PHP', decimalDigits: 2);
    return formatter.format(finalPenalty);
  }

  // ─────────────────────────────────────────────
  // COPY WITH METHOD
  // ─────────────────────────────────────────────
  BorrowingApplicationV2Model copyWith({
    int? id,
    String? userId,
    String? controlNumber,
    String? lastName,
    String? firstName,
    String? middleName,
    String? idNo,
    String? sex,
    DateTime? dateOfBirth,
    String? phoneNumber,
    String? emailAddress,
    String? collegeOffice,
    String? houseNo,
    String? streetName,
    String? barangay,
    String? municipality,
    String? province,
    double? familyIncome,
    double? distanceFromCampus,
    String? intended,
    String? durationOfUse,
    String? eSignatureUrl,
    DateTime? dateSigned,
    String? applicationPdfUrl,
    String? status,
    String? userType,
    String? campus,
    String? hrmoOsdSignature,
    String? hrmoOsdName,
    DateTime? hrmoOsdDateSigned,
    int? medicalAppointmentId,
    String? viceSignatureUrl,
    String? viceOfficerName,
    DateTime? viceDateSigned,
    String? gsoSignatureUrl,
    String? gsoOfficerName,
    DateTime? gsoDateSigned,
    int? financialNeedScore,
    int? distanceScore,
    int? fcfsStudentScore,
    int? assignedBikeId,
    String? assignedBikeNumber,
    double? finalPenalty,
    int? workCategoryRating,
    int? fcfsPersonnelScore,
    String? osdHrmoPdfUrl,
    String? finalApplicantSignatureUrl,
    String? renewalPdfUrl,
    String? rejectionReason,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? reassessmentRequested,
    DateTime? reassessmentRequestDate,
    bool? reassessmentApproved,
    String? reassessmentReviewedBy,
    DateTime? reassessmentReviewedAt,
    String? reassessmentRemarks,
    String? decisionSource,
    double? weightedScore,
  }) {
    return BorrowingApplicationV2Model(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      controlNumber: controlNumber ?? this.controlNumber,
      lastName: lastName ?? this.lastName,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      idNo: idNo ?? this.idNo,
      sex: sex ?? this.sex,
      dateOfBirth: dateOfBirth ?? this.dateOfBirth,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      emailAddress: emailAddress ?? this.emailAddress,
      collegeOffice: collegeOffice ?? this.collegeOffice,
      houseNo: houseNo ?? this.houseNo,
      streetName: streetName ?? this.streetName,
      barangay: barangay ?? this.barangay,
      municipality: municipality ?? this.municipality,
      province: province ?? this.province,
      familyIncome: familyIncome ?? this.familyIncome,
      distanceFromCampus: distanceFromCampus ?? this.distanceFromCampus,
      intended: intended ?? this.intended,
      durationOfUse: durationOfUse ?? this.durationOfUse,
      eSignatureUrl: eSignatureUrl ?? this.eSignatureUrl,
      dateSigned: dateSigned ?? this.dateSigned,
      applicationPdfUrl: applicationPdfUrl ?? this.applicationPdfUrl,
      status: status ?? this.status,
      userType: userType ?? this.userType,
      campus: campus ?? this.campus,
      hrmoOsdSignature: hrmoOsdSignature ?? this.hrmoOsdSignature,
      hrmoOsdName: hrmoOsdName ?? this.hrmoOsdName,
      hrmoOsdDateSigned: hrmoOsdDateSigned ?? this.hrmoOsdDateSigned,
      medicalAppointmentId: medicalAppointmentId ?? this.medicalAppointmentId,
      viceSignatureUrl: viceSignatureUrl ?? this.viceSignatureUrl,
      viceOfficerName: viceOfficerName ?? this.viceOfficerName,
      viceDateSigned: viceDateSigned ?? this.viceDateSigned,
      gsoSignatureUrl: gsoSignatureUrl ?? this.gsoSignatureUrl,
      gsoOfficerName: gsoOfficerName ?? this.gsoOfficerName,
      gsoDateSigned: gsoDateSigned ?? this.gsoDateSigned,
      financialNeedScore: financialNeedScore ?? this.financialNeedScore,
      distanceScore: distanceScore ?? this.distanceScore,
      fcfsStudentScore: fcfsStudentScore ?? this.fcfsStudentScore,
      assignedBikeId: assignedBikeId ?? this.assignedBikeId,
      assignedBikeNumber: assignedBikeNumber ?? this.assignedBikeNumber,
      finalPenalty: finalPenalty ?? this.finalPenalty,
      workCategoryRating: workCategoryRating ?? this.workCategoryRating,
      fcfsPersonnelScore: fcfsPersonnelScore ?? this.fcfsPersonnelScore,
      osdHrmoPdfUrl: osdHrmoPdfUrl ?? this.osdHrmoPdfUrl,
      finalApplicantSignatureUrl: finalApplicantSignatureUrl ?? this.finalApplicantSignatureUrl,
      renewalPdfUrl: renewalPdfUrl ?? this.renewalPdfUrl,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reassessmentRequested: reassessmentRequested ?? this.reassessmentRequested,
      reassessmentRequestDate: reassessmentRequestDate ?? this.reassessmentRequestDate,
      reassessmentApproved: reassessmentApproved ?? this.reassessmentApproved,
      reassessmentReviewedBy: reassessmentReviewedBy ?? this.reassessmentReviewedBy,
      reassessmentReviewedAt: reassessmentReviewedAt ?? this.reassessmentReviewedAt,
      reassessmentRemarks: reassessmentRemarks ?? this.reassessmentRemarks,
      decisionSource: decisionSource ?? this.decisionSource,
      weightedScore: weightedScore ?? this.weightedScore,
    );
  }

  @override
  String toString() => 'BorrowingApplicationV2Model(id: $id, name: $fullName, status: $status)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BorrowingApplicationV2Model &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          userId == other.userId &&
          status == other.status;

  @override
  int get hashCode => id.hashCode ^ userId.hashCode ^ status.hashCode;
}