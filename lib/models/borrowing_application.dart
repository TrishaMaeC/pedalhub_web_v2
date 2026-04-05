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

  // ── NEW-APPLICATION REASSESSMENT FIELDS (kept for non-renewal flow) ──────
  final bool? reassessmentRequested;
  final DateTime? reassessmentRequestDate;
  final bool? reassessmentApproved;
  final String? reassessmentReviewedBy;
  final DateTime? reassessmentReviewedAt;
  final String? reassessmentRemarks;

  // ── AUTOMATED SYSTEM FIELDS ───────────────────────────────────────────────
  final String? decisionSource;
  final double? weightedScore;

  // ── RENEWAL GENERAL ───────────────────────────────────────────────────────
  final DateTime? renewalAppliedAt;        // renewal_applied_at
  final int renewalCount;                  // renewal_count
  final int suspensionCount;               // suspension_count

  // ── RENEWAL HRMO/OSD APPROVAL ─────────────────────────────────────────────
  final String? renewalHrmoOsdRejectionReason;  // renewal_hrmo_osd_rejection_reason
  final String? renewalHrmoOsdSignatoryName;    // renewal_hrmo_osd_signatory_name
  final String? renewalHrmoOsdSignatureUrl;     // renewal_hrmo_osd_signature_url
  final String? renewalHrmoOsdPdfUrl;           // renewal_hrmo_osd_pdf_url

  // ── RENEWAL HEALTH — MEDICAL EVALUATION ──────────────────────────────────
  final String? renewalMedicalRemarks;          // renewal_medical_remarks
  final String? renewalMedicalSignatoryName;    // renewal_medical_signatory_name
  final String? renewalMedicalSignatureUrl;     // renewal_medical_signature_url

  // ── RENEWAL HEALTH — REASSESSMENT ────────────────────────────────────────
  final DateTime? renewalReassessmentRequestedAt;  // renewal_reassessment_requested_at
  final String? renewalReassessmentReason;         // renewal_reassessment_reason
  final bool? renewalReassessmentApproved;         // renewal_reassessment_approved
  final DateTime? renewalReassessmentReviewedAt;   // renewal_reassessment_reviewed_at
  final String? renewalReassessmentRemarks;        // renewal_reassessment_remarks

  // ── RENEWAL GSO — BIKE HANDLING ───────────────────────────────────────────
  final int? renewalGsoBikeId;           // renewal_gso_bike_id
  final String? renewalGsoBikeNumber;    // renewal_gso_bike_number
  final String? renewalGsoCheckedBy;     // renewal_gso_checked_by
  final String? renewalGsoSignatureUrl;  // renewal_gso_signature_url

  // ── RENEWAL GSO — BIKE DAMAGE ─────────────────────────────────────────────
  final String? renewalGsoDamageRemarks;    // renewal_gso_damage_remarks
  final String? renewalGsoDamagePhotoUrl;   // renewal_gso_damage_photo_url
  final int? renewalGsoDamageReportId;      // renewal_gso_damage_report_id

  // ── RENEWAL DISCIPLINE/HRMO — PENALTIES ──────────────────────────────────
  final String? renewalForwardedBy;          // renewal_forwarded_by
  final String? renewalForwardedRemarks;     // renewal_forwarded_remarks
  final DateTime? renewalSuspendedUntil;     // renewal_suspended_until
  final DateTime? renewalTerminatedAt;       // renewal_terminated_at
  final String? renewalTerminatedBy;         // renewal_terminated_by
  final String? renewalTerminatedRemarks;    // renewal_terminated_remarks

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
    // New-application reassessment
    this.reassessmentRequested,
    this.reassessmentRequestDate,
    this.reassessmentApproved,
    this.reassessmentReviewedBy,
    this.reassessmentReviewedAt,
    this.reassessmentRemarks,
    // Automated system
    this.decisionSource,
    this.weightedScore,
    // Renewal general
    this.renewalAppliedAt,
    this.renewalCount = 0,
    this.suspensionCount = 0,
    // Renewal HRMO/OSD
    this.renewalHrmoOsdRejectionReason,
    this.renewalHrmoOsdSignatoryName,
    this.renewalHrmoOsdSignatureUrl,
    this.renewalHrmoOsdPdfUrl,
    // Renewal medical evaluation
    this.renewalMedicalRemarks,
    this.renewalMedicalSignatoryName,
    this.renewalMedicalSignatureUrl,
    // Renewal reassessment
    this.renewalReassessmentRequestedAt,
    this.renewalReassessmentReason,
    this.renewalReassessmentApproved,
    this.renewalReassessmentReviewedAt,
    this.renewalReassessmentRemarks,
    // Renewal GSO bike handling
    this.renewalGsoBikeId,
    this.renewalGsoBikeNumber,
    this.renewalGsoCheckedBy,
    this.renewalGsoSignatureUrl,
    // Renewal GSO bike damage
    this.renewalGsoDamageRemarks,
    this.renewalGsoDamagePhotoUrl,
    this.renewalGsoDamageReportId,
    // Renewal penalties
    this.renewalForwardedBy,
    this.renewalForwardedRemarks,
    this.renewalSuspendedUntil,
    this.renewalTerminatedAt,
    this.renewalTerminatedBy,
    this.renewalTerminatedRemarks,
  });

  // ─────────────────────────────────────────────
  // HELPERS
  // ─────────────────────────────────────────────
  bool get isStudent => userType?.toLowerCase() == 'student';
  bool get isPersonnel => userType?.toLowerCase() == 'personnel';
  bool get isRenewal => status.startsWith('renewal_');
  bool get isSystemProcessed => decisionSource == 'SYSTEM';
  bool get wasRanked => weightedScore != null;

  String get fullAddress {
    final parts = [houseNo, streetName, barangay, municipality, province]
        .where((s) => s != null && s.isNotEmpty)
        .toList();
    return parts.join(', ');
  }

  String get presentAddress => fullAddress;

  String get fullName {
    if (middleName != null && middleName!.isNotEmpty) {
      return '$firstName ${middleName![0]}. $lastName';
    }
    return '$firstName $lastName';
  }

  // ─────────────────────────────────────────────
  // fromJson
  // ─────────────────────────────────────────────
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
      finalApplicantSignatureUrl:
          json['final_applicant_signature_url'] as String?,
      renewalPdfUrl: json['renewal_pdf_url'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at'] as String) ?? DateTime.now(),
      updatedAt:
          DateTime.tryParse(json['updated_at'] as String) ?? DateTime.now(),
      // New-application reassessment
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
      // Automated system
      decisionSource: json['decision_source'] as String?,
      weightedScore: json['weighted_score'] != null
          ? (json['weighted_score'] as num).toDouble()
          : null,
      // Renewal general
      renewalAppliedAt: json['renewal_applied_at'] != null
          ? DateTime.tryParse(json['renewal_applied_at'] as String)
          : null,
      renewalCount: (json['renewal_count'] as int?) ?? 0,
      suspensionCount: (json['suspension_count'] as int?) ?? 0,
      // Renewal HRMO/OSD
      renewalHrmoOsdRejectionReason:
          json['renewal_hrmo_osd_rejection_reason'] as String?,
      renewalHrmoOsdSignatoryName:
          json['renewal_hrmo_osd_signatory_name'] as String?,
      renewalHrmoOsdSignatureUrl:
          json['renewal_hrmo_osd_signature_url'] as String?,
      renewalHrmoOsdPdfUrl: json['renewal_hrmo_osd_pdf_url'] as String?,
      // Renewal medical evaluation
      renewalMedicalRemarks: json['renewal_medical_remarks'] as String?,
      renewalMedicalSignatoryName:
          json['renewal_medical_signatory_name'] as String?,
      renewalMedicalSignatureUrl:
          json['renewal_medical_signature_url'] as String?,
      // Renewal reassessment
      renewalReassessmentRequestedAt:
          json['renewal_reassessment_requested_at'] != null
              ? DateTime.tryParse(
                  json['renewal_reassessment_requested_at'] as String)
              : null,
      renewalReassessmentReason:
          json['renewal_reassessment_reason'] as String?,
      renewalReassessmentApproved:
          json['renewal_reassessment_approved'] as bool?,
      renewalReassessmentReviewedAt:
          json['renewal_reassessment_reviewed_at'] != null
              ? DateTime.tryParse(
                  json['renewal_reassessment_reviewed_at'] as String)
              : null,
      renewalReassessmentRemarks:
          json['renewal_reassessment_remarks'] as String?,
      // Renewal GSO bike handling
      renewalGsoBikeId: json['renewal_gso_bike_id'] as int?,
      renewalGsoBikeNumber: json['renewal_gso_bike_number'] as String?,
      renewalGsoCheckedBy: json['renewal_gso_checked_by'] as String?,
      renewalGsoSignatureUrl: json['renewal_gso_signature_url'] as String?,
      // Renewal GSO bike damage
      renewalGsoDamageRemarks: json['renewal_gso_damage_remarks'] as String?,
      renewalGsoDamagePhotoUrl:
          json['renewal_gso_damage_photo_url'] as String?,
      renewalGsoDamageReportId: json['renewal_gso_damage_report_id'] as int?,
      // Renewal penalties
      renewalForwardedBy: json['renewal_forwarded_by'] as String?,
      renewalForwardedRemarks: json['renewal_forwarded_remarks'] as String?,
      renewalSuspendedUntil: json['renewal_suspended_until'] != null
          ? DateTime.tryParse(json['renewal_suspended_until'] as String)
          : null,
      renewalTerminatedAt: json['renewal_terminated_at'] != null
          ? DateTime.tryParse(json['renewal_terminated_at'] as String)
          : null,
      renewalTerminatedBy: json['renewal_terminated_by'] as String?,
      renewalTerminatedRemarks:
          json['renewal_terminated_remarks'] as String?,
    );
  }

  // ─────────────────────────────────────────────
  // toJson
  // ─────────────────────────────────────────────
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
      // New-application reassessment
      'reassessment_requested': reassessmentRequested,
      'reassessment_request_date': reassessmentRequestDate?.toIso8601String(),
      'reassessment_approved': reassessmentApproved,
      'reassessment_reviewed_by': reassessmentReviewedBy,
      'reassessment_reviewed_at': reassessmentReviewedAt?.toIso8601String(),
      'reassessment_remarks': reassessmentRemarks,
      // Automated system
      'decision_source': decisionSource,
      'weighted_score': weightedScore,
      // Renewal general
      'renewal_applied_at': renewalAppliedAt?.toIso8601String(),
      'renewal_count': renewalCount,
      'suspension_count': suspensionCount,
      // Renewal HRMO/OSD
      'renewal_hrmo_osd_rejection_reason': renewalHrmoOsdRejectionReason,
      'renewal_hrmo_osd_signatory_name': renewalHrmoOsdSignatoryName,
      'renewal_hrmo_osd_signature_url': renewalHrmoOsdSignatureUrl,
      'renewal_hrmo_osd_pdf_url': renewalHrmoOsdPdfUrl,
      // Renewal medical evaluation
      'renewal_medical_remarks': renewalMedicalRemarks,
      'renewal_medical_signatory_name': renewalMedicalSignatoryName,
      'renewal_medical_signature_url': renewalMedicalSignatureUrl,
      // Renewal reassessment
      'renewal_reassessment_requested_at':
          renewalReassessmentRequestedAt?.toIso8601String(),
      'renewal_reassessment_reason': renewalReassessmentReason,
      'renewal_reassessment_approved': renewalReassessmentApproved,
      'renewal_reassessment_reviewed_at':
          renewalReassessmentReviewedAt?.toIso8601String(),
      'renewal_reassessment_remarks': renewalReassessmentRemarks,
      // Renewal GSO bike handling
      'renewal_gso_bike_id': renewalGsoBikeId,
      'renewal_gso_bike_number': renewalGsoBikeNumber,
      'renewal_gso_checked_by': renewalGsoCheckedBy,
      'renewal_gso_signature_url': renewalGsoSignatureUrl,
      // Renewal GSO bike damage
      'renewal_gso_damage_remarks': renewalGsoDamageRemarks,
      'renewal_gso_damage_photo_url': renewalGsoDamagePhotoUrl,
      'renewal_gso_damage_report_id': renewalGsoDamageReportId,
      // Renewal penalties
      'renewal_forwarded_by': renewalForwardedBy,
      'renewal_forwarded_remarks': renewalForwardedRemarks,
      'renewal_suspended_until': renewalSuspendedUntil?.toIso8601String(),
      'renewal_terminated_at': renewalTerminatedAt?.toIso8601String(),
      'renewal_terminated_by': renewalTerminatedBy,
      'renewal_terminated_remarks': renewalTerminatedRemarks,
    };
  }

  // ─────────────────────────────────────────────
  // STATUS TEXT
  // ─────────────────────────────────────────────
  String getStatusText() {
    switch (status) {
      // ── Original statuses ──────────────────────────────────────────────
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
      case 'cancelled':
        return 'Application Cancelled';
      // ── Renewal statuses ───────────────────────────────────────────────
      case 'renewal_applied':
        return 'Renewal Applied';
      case 'renewal_osd_approved':
        return 'Renewal OSD Approved';
      case 'renewal_osd_rejected':
        return 'Renewal OSD Rejected';
      case 'renewal_hrmo_approved':
        return 'Renewal HRMO Approved';
      case 'renewal_hrmo_rejected':
        return 'Renewal HRMO Rejected';
      case 'renewal_medical_scheduled':
        return 'Renewal Medical Scheduled';
      case 'renewal_medical_approved':
        return 'Renewal Medical Approved';
      case 'renewal_medical_rejected':
        return 'Renewal Medical Rejected';
      case 'renewal_medical_reassessment':
        return 'Renewal Reassessment Requested';
      case 'renewal_medical_reassessment_approved':
        return 'Renewal Reassessment Approved';
      case 'renewal_pending_next_sem':
        return 'Renewal Pending Next Semester';
      case 'renewal_bike_checked':
        return 'Renewal Bike Checked';
      case 'renewal_bike_damage_reported':
        return 'Renewal Bike Damage Reported';
      case 'renewal_bike_damaged':
        return 'Renewal Bike Damaged';
      case 'forwarded_discipline':
        return 'Forwarded to Discipline Office';
      case 'forwarded_hrmo':
        return 'Forwarded to HRMO';
      case 'suspended_1_semester':
        return 'Suspended (1 Semester)';
      case 'terminated':
        return 'Terminated';
      case 'active_renewal':
        return 'Active (Renewal)';
      default:
        return status.replaceAll('_', ' ').toUpperCase();
    }
  }

  // ─────────────────────────────────────────────
  // STATUS COLOR
  // ─────────────────────────────────────────────
  Color getStatusColor() {
    switch (status) {
      // Green — approved / active / passed
      case 'for_release':
      case 'active':
      case 'active_renewal':
      case 'renewal_osd_approved':
      case 'renewal_hrmo_approved':
      case 'renewal_medical_approved':
      case 'renewal_medical_reassessment_approved':
      case 'renewal_bike_checked':
        return Colors.green;

      // Orange — in-progress / scheduled / pending
      case 'fit_to_use':
      case 'vice_pending':
      case 'medical_scheduled':
      case 'hrmo_approved':
      case 'osd_approved':
      case 'pending_application':
      case 'renewal_applied':
      case 'renewal_medical_scheduled':
      case 'renewal_pending_next_sem':
        return Colors.orange;

      // Purple — reassessment
      case 'for_reassessment':
      case 'renewal_medical_reassessment':
        return Colors.purple;

      // Red — rejected / failed / damage
      case 'vice_rejected':
      case 'health_rejected':
      case 'cancelled':
      case 'renewal_osd_rejected':
      case 'renewal_hrmo_rejected':
      case 'renewal_medical_rejected':
      case 'renewal_bike_damage_reported':
      case 'renewal_bike_damaged':
        return Colors.red;

      // Deep orange — overdue / forwarded
      case 'overdue':
      case 'forwarded_discipline':
      case 'forwarded_hrmo':
        return const Color(0xFFE64A19);

      // Dark grey — suspended / terminated
      case 'suspended_1_semester':
      case 'terminated':
        return const Color(0xFF424242);

      // Blue — completed
      case 'completed':
        return Colors.blue;

      default:
        return Colors.grey;
    }
  }

  // ─────────────────────────────────────────────
  // SCORE BREAKDOWNS
  // ─────────────────────────────────────────────
  String get scoreBreakdown {
    if (isStudent) {
      if (financialNeedScore == null &&
          distanceScore == null &&
          fcfsStudentScore == null) return 'Not yet scored';
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

  String get automatedScoreBreakdown {
    if (!isSystemProcessed) return 'Not processed by automated system';
    if (!wasRanked) {
      return 'Auto-approved (No ranking needed - applicants ≤ bikes)';
    }
    if (isStudent) {
      return 'Financial Need: ${financialNeedScore ?? 0}/3 · '
          'Distance: ${distanceScore ?? 0}/3 · '
          'Total: ${weightedScore?.toStringAsFixed(2) ?? '0.00'}/6';
    } else if (isPersonnel) {
      return 'Work Category: ${workCategoryRating ?? 0}/3 · '
          'Distance: ${distanceScore ?? 0}/3 · '
          'Total: ${weightedScore?.toStringAsFixed(2) ?? '0.00'}/6';
    }
    return 'Score: ${weightedScore?.toStringAsFixed(2) ?? 'N/A'}';
  }

  // ─────────────────────────────────────────────
  // FORMATTERS
  // ─────────────────────────────────────────────
  String get formattedIncome {
    if (familyIncome == null) return 'N/A';
    return NumberFormat.simpleCurrency(name: 'PHP', decimalDigits: 0)
        .format(familyIncome);
  }

  String get formattedDistance {
    if (distanceFromCampus == null) return 'N/A';
    return '${distanceFromCampus!.toStringAsFixed(2)} km';
  }

  String get formattedPenalty {
    if (finalPenalty == null) return 'N/A';
    return NumberFormat.simpleCurrency(name: 'PHP', decimalDigits: 2)
        .format(finalPenalty);
  }

  // ─────────────────────────────────────────────
  // copyWith
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
    DateTime? renewalAppliedAt,
    int? renewalCount,
    int? suspensionCount,
    String? renewalHrmoOsdRejectionReason,
    String? renewalHrmoOsdSignatoryName,
    String? renewalHrmoOsdSignatureUrl,
    String? renewalHrmoOsdPdfUrl,
    String? renewalMedicalRemarks,
    String? renewalMedicalSignatoryName,
    String? renewalMedicalSignatureUrl,
    DateTime? renewalReassessmentRequestedAt,
    String? renewalReassessmentReason,
    bool? renewalReassessmentApproved,
    DateTime? renewalReassessmentReviewedAt,
    String? renewalReassessmentRemarks,
    int? renewalGsoBikeId,
    String? renewalGsoBikeNumber,
    String? renewalGsoCheckedBy,
    String? renewalGsoSignatureUrl,
    String? renewalGsoDamageRemarks,
    String? renewalGsoDamagePhotoUrl,
    int? renewalGsoDamageReportId,
    String? renewalForwardedBy,
    String? renewalForwardedRemarks,
    DateTime? renewalSuspendedUntil,
    DateTime? renewalTerminatedAt,
    String? renewalTerminatedBy,
    String? renewalTerminatedRemarks,
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
      finalApplicantSignatureUrl:
          finalApplicantSignatureUrl ?? this.finalApplicantSignatureUrl,
      renewalPdfUrl: renewalPdfUrl ?? this.renewalPdfUrl,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      reassessmentRequested:
          reassessmentRequested ?? this.reassessmentRequested,
      reassessmentRequestDate:
          reassessmentRequestDate ?? this.reassessmentRequestDate,
      reassessmentApproved: reassessmentApproved ?? this.reassessmentApproved,
      reassessmentReviewedBy:
          reassessmentReviewedBy ?? this.reassessmentReviewedBy,
      reassessmentReviewedAt:
          reassessmentReviewedAt ?? this.reassessmentReviewedAt,
      reassessmentRemarks: reassessmentRemarks ?? this.reassessmentRemarks,
      decisionSource: decisionSource ?? this.decisionSource,
      weightedScore: weightedScore ?? this.weightedScore,
      renewalAppliedAt: renewalAppliedAt ?? this.renewalAppliedAt,
      renewalCount: renewalCount ?? this.renewalCount,
      suspensionCount: suspensionCount ?? this.suspensionCount,
      renewalHrmoOsdRejectionReason:
          renewalHrmoOsdRejectionReason ?? this.renewalHrmoOsdRejectionReason,
      renewalHrmoOsdSignatoryName:
          renewalHrmoOsdSignatoryName ?? this.renewalHrmoOsdSignatoryName,
      renewalHrmoOsdSignatureUrl:
          renewalHrmoOsdSignatureUrl ?? this.renewalHrmoOsdSignatureUrl,
      renewalHrmoOsdPdfUrl: renewalHrmoOsdPdfUrl ?? this.renewalHrmoOsdPdfUrl,
      renewalMedicalRemarks:
          renewalMedicalRemarks ?? this.renewalMedicalRemarks,
      renewalMedicalSignatoryName:
          renewalMedicalSignatoryName ?? this.renewalMedicalSignatoryName,
      renewalMedicalSignatureUrl:
          renewalMedicalSignatureUrl ?? this.renewalMedicalSignatureUrl,
      renewalReassessmentRequestedAt:
          renewalReassessmentRequestedAt ?? this.renewalReassessmentRequestedAt,
      renewalReassessmentReason:
          renewalReassessmentReason ?? this.renewalReassessmentReason,
      renewalReassessmentApproved:
          renewalReassessmentApproved ?? this.renewalReassessmentApproved,
      renewalReassessmentReviewedAt:
          renewalReassessmentReviewedAt ?? this.renewalReassessmentReviewedAt,
      renewalReassessmentRemarks:
          renewalReassessmentRemarks ?? this.renewalReassessmentRemarks,
      renewalGsoBikeId: renewalGsoBikeId ?? this.renewalGsoBikeId,
      renewalGsoBikeNumber: renewalGsoBikeNumber ?? this.renewalGsoBikeNumber,
      renewalGsoCheckedBy: renewalGsoCheckedBy ?? this.renewalGsoCheckedBy,
      renewalGsoSignatureUrl:
          renewalGsoSignatureUrl ?? this.renewalGsoSignatureUrl,
      renewalGsoDamageRemarks:
          renewalGsoDamageRemarks ?? this.renewalGsoDamageRemarks,
      renewalGsoDamagePhotoUrl:
          renewalGsoDamagePhotoUrl ?? this.renewalGsoDamagePhotoUrl,
      renewalGsoDamageReportId:
          renewalGsoDamageReportId ?? this.renewalGsoDamageReportId,
      renewalForwardedBy: renewalForwardedBy ?? this.renewalForwardedBy,
      renewalForwardedRemarks:
          renewalForwardedRemarks ?? this.renewalForwardedRemarks,
      renewalSuspendedUntil:
          renewalSuspendedUntil ?? this.renewalSuspendedUntil,
      renewalTerminatedAt: renewalTerminatedAt ?? this.renewalTerminatedAt,
      renewalTerminatedBy: renewalTerminatedBy ?? this.renewalTerminatedBy,
      renewalTerminatedRemarks:
          renewalTerminatedRemarks ?? this.renewalTerminatedRemarks,
    );
  }

  @override
  String toString() =>
      'BorrowingApplicationV2Model(id: $id, name: $fullName, status: $status)';

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