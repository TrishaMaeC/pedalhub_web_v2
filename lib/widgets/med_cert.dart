import 'dart:developer' as developer;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class MedicalCertificateData {
  final String controlNumber;
  final DateTime date;
  final String patientName;
  final String age;
  final String sex;
  final String civilStatus;
  final String address;
  final DateTime examDate;
  final String diagnosis;
  final String remarks;
  final String purpose;
  final String doctorName;
  final String licenseNumber;
  final String? physicianSignatureUrl; // from DB column physician_signature_url

  MedicalCertificateData({
    required this.controlNumber,
    required this.date,
    required this.patientName,
    required this.age,
    required this.sex,
    required this.civilStatus,
    required this.address,
    required this.examDate,
    required this.diagnosis,
    required this.remarks,
    required this.purpose,
    required this.doctorName,
    required this.licenseNumber,
    this.physicianSignatureUrl,
  });
}

class MedicalCertificateGenerator {
  static const PdfPageFormat customFormat = PdfPageFormat(
    8.5 * PdfPageFormat.inch,
    11 * PdfPageFormat.inch,
    marginAll: 0.75 * PdfPageFormat.inch,
  );

  static Future<void> previewCertificate(MedicalCertificateData data) async {
    final logoImage = await _loadLogo();
    final font = await _loadTimesNewRoman();
    final fontBold = await _loadTimesNewRomanBold();

    // Load physician signature from Supabase URL
    pw.ImageProvider? signatureImage;
    if (data.physicianSignatureUrl != null &&
        data.physicianSignatureUrl!.trim().isNotEmpty) {
      developer.log(
        'Loading signature from: ${data.physicianSignatureUrl}',
        name: 'MedicalCert',
      );
      signatureImage =
          await _loadSignatureFromSupabase(data.physicianSignatureUrl!.trim());
      if (signatureImage == null) {
        developer.log(
          'WARNING: Signature failed to load — URL: ${data.physicianSignatureUrl}',
          name: 'MedicalCert',
        );
      } else {
        developer.log('Signature loaded OK.', name: 'MedicalCert');
      }
    } else {
      developer.log(
        'WARNING: physicianSignatureUrl is null or empty.',
        name: 'MedicalCert',
      );
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        final pdf = pw.Document();
        pdf.addPage(
          pw.Page(
            pageFormat: customFormat,
            build: (pw.Context context) => _buildCertificateContent(
              data, logoImage, font, fontBold, signatureImage,
            ),
          ),
        );
        return pdf.save();
      },
    );
  }

  /// Fetch image bytes from a Supabase public storage URL
  static Future<pw.ImageProvider?> _loadSignatureFromSupabase(
      String url) async {
    try {
      final response = await http
          .get(Uri.parse(url), headers: {'Accept': 'image/*'})
          .timeout(const Duration(seconds: 15));

      developer.log(
        'Signature response — status: ${response.statusCode}, '
        'content-type: ${response.headers['content-type']}, '
        'bytes: ${response.bodyBytes.length}',
        name: 'MedicalCert',
      );

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return pw.MemoryImage(response.bodyBytes);
      }
    } catch (e, stack) {
      developer.log(
        'Signature fetch error: $e',
        name: 'MedicalCert',
        error: e,
        stackTrace: stack,
      );
    }
    return null;
  }

  static Future<pw.ImageProvider> _loadLogo() async {
    final bytes = await rootBundle.load('assets/images/batstateu_logo.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  static Future<pw.Font> _loadTimesNewRoman() async {
    final data = await rootBundle.load('assets/fonts/times_new_roman.ttf');
    return pw.Font.ttf(data);
  }

  static Future<pw.Font> _loadTimesNewRomanBold() async {
    final data =
        await rootBundle.load('assets/fonts/times_new_roman_bold.ttf');
    return pw.Font.ttf(data);
  }

  // ── Page layout ───────────────────────────────────────────────────────────

  static pw.Widget _buildCertificateContent(
    MedicalCertificateData data,
    pw.ImageProvider logo,
    pw.Font font,
    pw.Font fontBold,
    pw.ImageProvider? signatureImage,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildReferenceHeader(font),
        pw.SizedBox(height: 6),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(width: 65, height: 65, child: pw.Image(logo)),
            pw.SizedBox(width: 12),
            pw.Expanded(child: _buildUniversityHeader(font, fontBold)),
          ],
        ),
        pw.SizedBox(height: 10),
        pw.Divider(thickness: 0.5),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(child: pw.SizedBox()),
            pw.Text('MEDICAL CERTIFICATE',
                style: pw.TextStyle(fontSize: 14, font: fontBold)),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  _buildSmallField('Control No.:', data.controlNumber, font, 90),
                  pw.SizedBox(height: 4),
                  _buildSmallField('Date:', _formatDate(data.date), font, 90),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text('To whom it may concern,',
            style: pw.TextStyle(fontSize: 11, font: font)),
        pw.SizedBox(height: 12),
        _buildPatientInfo(data, font),
        pw.SizedBox(height: 14),
        _buildLabeledLine(label: 'Diagnosis:', value: data.diagnosis, font: font),
        pw.SizedBox(height: 12),
        _buildRemarksSection(data, font),
        pw.SizedBox(height: 12),
        _buildPurposeStatement(data, font),
        pw.Spacer(),
        _buildDoctorSignature(data, font, fontBold, signatureImage),
        pw.SizedBox(height: 20),
      ],
    );
  }

  static pw.Widget _buildReferenceHeader(pw.Font font) {
    final s = pw.TextStyle(fontSize: 8, font: font);
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('Reference No: BatStateU-CE-12', style: s),
        pw.Text('Effectivity Date: July 01, 2024', style: s),
        pw.Text('Revision No.: 02', style: s),
      ],
    );
  }

  static pw.Widget _buildUniversityHeader(pw.Font font, pw.Font fontBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text('Republic of the Philippines',
            style: pw.TextStyle(fontSize: 11, font: font),
            textAlign: pw.TextAlign.center),
        pw.Text('BATANGAS STATE UNIVERSITY',
            style: pw.TextStyle(fontSize: 13, font: fontBold),
            textAlign: pw.TextAlign.center),
        pw.Text('The National Engineering University',
            style: pw.TextStyle(fontSize: 10, font: fontBold),
            textAlign: pw.TextAlign.center),
        pw.Text('Alangilan Campus',
            style: pw.TextStyle(fontSize: 10, font: fontBold),
            textAlign: pw.TextAlign.center),
        pw.Text(
            'Golden Country Homes, Alangilan, Batangas City, Philippines 4200',
            style: pw.TextStyle(fontSize: 9, font: fontBold),
            textAlign: pw.TextAlign.center),
        pw.Text('Tel. No.: 425-0139; 425-0143 loc. 2140',
            style: pw.TextStyle(fontSize: 8, font: font),
            textAlign: pw.TextAlign.center),
        pw.Text(
            'E-mail Address: healthservices.alangilan@g.batstate-u.edu.ph',
            style: pw.TextStyle(fontSize: 8, font: font),
            textAlign: pw.TextAlign.center),
      ],
    );
  }

  static pw.Widget _buildSmallField(
      String label, String value, pw.Font font, double valueWidth) {
    return pw.Row(
      mainAxisSize: pw.MainAxisSize.min,
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 10, font: font)),
        pw.SizedBox(width: 4),
        pw.Container(
          width: valueWidth,
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
          child: pw.Text(value, style: pw.TextStyle(fontSize: 10, font: font)),
        ),
      ],
    );
  }

  static pw.Widget _buildPatientInfo(
      MedicalCertificateData data, pw.Font font) {
    final s = pw.TextStyle(fontSize: 11, font: font);
    final sLabel = pw.TextStyle(fontSize: 8, font: font);

    pw.Widget uBox(String value, double width) => pw.Container(
          width: width,
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
          child: pw.Text(value, style: s, textAlign: pw.TextAlign.center),
        );

    pw.Widget uBoxExpanded(String value) => pw.Expanded(
          child: pw.Container(
            decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
            child: pw.Text(value, style: s),
          ),
        );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('This is to certify that Mr/Ms/Mrs', style: s),
          pw.SizedBox(width: 4),
          uBox(data.patientName, 180),
          pw.SizedBox(width: 3),
          pw.Text('-', style: s),
          pw.SizedBox(width: 3),
          uBox(data.age, 30),
          pw.SizedBox(width: 3),
          pw.Text('years old,', style: s),
        ]),
        pw.Row(children: [
          pw.SizedBox(width: 230),
          pw.Text('Name', style: sLabel),
          pw.SizedBox(width: 113),
          pw.Text('Age', style: sLabel),
        ]),
        pw.SizedBox(height: 8),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          uBox(data.sex, 40),
          pw.SizedBox(width: 3),
          pw.Text('-', style: s),
          pw.SizedBox(width: 3),
          uBox(data.civilStatus, 60),
          pw.Text(', a resident of', style: s),
          pw.SizedBox(width: 4),
          uBoxExpanded(data.address),
          pw.Text(', was confined/', style: s),
        ]),
        pw.Row(children: [
          pw.Text('Sex', style: sLabel),
          pw.SizedBox(width: 33),
          pw.Text('Civil Status', style: sLabel),
          pw.SizedBox(width: 106),
          pw.Text('Address', style: sLabel),
        ]),
        pw.SizedBox(height: 8),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('examined/consulted on', style: s),
          pw.SizedBox(width: 4),
          pw.Container(
            width: 130,
            decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
            child: pw.Text(_formatDate(data.examDate), style: s),
          ),
        ]),
        pw.Row(children: [
          pw.SizedBox(width: 168),
          pw.Text('Date', style: sLabel),
        ]),
      ],
    );
  }

  static pw.Widget _buildLabeledLine({
    required String label,
    required String value,
    required pw.Font font,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 11, font: font)),
        pw.SizedBox(width: 4),
        pw.Expanded(
          child: pw.Container(
            decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
            child:
                pw.Text(value, style: pw.TextStyle(fontSize: 11, font: font)),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildRemarksSection(
      MedicalCertificateData data, pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildLabeledLine(label: 'Remarks:', value: data.remarks, font: font),
        pw.SizedBox(height: 3),
        pw.Container(
          width: double.infinity,
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
          child: pw.SizedBox(height: 13),
        ),
      ],
    );
  }

  static pw.Widget _buildPurposeStatement(
      MedicalCertificateData data, pw.Font font) {
    final s = pw.TextStyle(fontSize: 11, font: font);
    return pw.Wrap(
      crossAxisAlignment: pw.WrapCrossAlignment.end,
      children: [
        pw.Text(
            'This medical certificate is issued upon request of the patient and for ',
            style: s),
        pw.Container(
          width: 80,
          decoration: const pw.BoxDecoration(
              border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
          child:
              pw.Text(data.purpose, style: s, textAlign: pw.TextAlign.center),
        ),
        pw.Text(' purpose only and not for medico-legal purposes.', style: s),
      ],
    );
  }

  static pw.Widget _buildDoctorSignature(
    MedicalCertificateData data,
    pw.Font font,
    pw.Font fontBold,
    pw.ImageProvider? signatureImage,
  ) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.SizedBox(
        width: 180,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            // Signature image above the line
            if (signatureImage != null)
              pw.Image(signatureImage, height: 50, width: 170,
                  fit: pw.BoxFit.contain)
            else
              pw.SizedBox(height: 50),

            // Underline below signature
            pw.Container(
              width: 180,
              decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 0.5))),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              data.doctorName.isEmpty ? '' : data.doctorName.toUpperCase(),
              style: pw.TextStyle(fontSize: 11, font: fontBold),
              textAlign: pw.TextAlign.center,
            ),
            pw.Text('NAME OF THE DOCTOR',
                style: pw.TextStyle(fontSize: 8, font: font),
                textAlign: pw.TextAlign.center),
            pw.Text('Attending Physician',
                style: pw.TextStyle(fontSize: 10, font: font),
                textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 4),
            pw.Text(
              'License No.: ${data.licenseNumber.isEmpty ? "_______" : data.licenseNumber}',
              style: pw.TextStyle(fontSize: 10, font: font),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}