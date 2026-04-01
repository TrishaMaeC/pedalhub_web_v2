

import 'package:flutter/services.dart' show rootBundle;
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
  });
}

class MedicalCertificateGenerator {
  // 210 x 148 mm - Landscape orientation
  static const PdfPageFormat customFormat = PdfPageFormat(
    210 * PdfPageFormat.mm,
    148 * PdfPageFormat.mm,
    marginAll: 10 * PdfPageFormat.mm,
  );

  static Future<void> previewCertificate(MedicalCertificateData data) async {
    // Load logo and font
    final logoImage = await _loadLogo();
    final font = await _loadTimesNewRoman();
    final fontBold = await _loadTimesNewRomanBold();

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async {
        final pdf = pw.Document();
        pdf.addPage(
          pw.Page(
            pageFormat: customFormat,
            build: (pw.Context context) {
              return _buildCertificateContent(data, logoImage, font, fontBold);
            },
          ),
        );
        return pdf.save();
      },
    );
  }

  /// Load BatState U logo
  static Future<pw.ImageProvider> _loadLogo() async {
    final bytes = await rootBundle.load('assets/images/batstateu_logo.png');
    return pw.MemoryImage(bytes.buffer.asUint8List());
  }

  /// Load Times New Roman font
  static Future<pw.Font> _loadTimesNewRoman() async {
    final fontData = await rootBundle.load('assets/fonts/times_new_roman.ttf');
    return pw.Font.ttf(fontData);
  }

  /// Load Times New Roman Bold font
  static Future<pw.Font> _loadTimesNewRomanBold() async {
    final fontData = await rootBundle.load('assets/fonts/times_new_roman_bold.ttf');
    return pw.Font.ttf(fontData);
  }

  static pw.Widget _buildCertificateContent(
    MedicalCertificateData data,
    pw.ImageProvider logo,
    pw.Font font,
    pw.Font fontBold,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _buildReferenceHeader(font),
        pw.SizedBox(height: 4),

        pw.Center(
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Container(width: 50, height: 50, child: pw.Image(logo)),
              pw.SizedBox(width: 8),
              _buildUniversityHeader(font, fontBold),
            ],
          ),
        ),

        pw.SizedBox(height: 6),

        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 10),
            pw.Expanded(
              child: pw.Center(
                child: pw.Text(
                  'MEDICAL CERTIFICATE',
                  style: pw.TextStyle(fontSize: 10, font: fontBold),
                ),
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildSmallField('Control No.:', data.controlNumber, font),
                pw.SizedBox(height: 2),
                _buildSmallField('Date:', _formatDate(data.date), font),
              ],
            ),
          ],
        ),

        pw.SizedBox(height: 6),

        pw.Text(
          'To whom it may concern,',
          style: pw.TextStyle(fontSize: 8, font: font),
        ),
        pw.SizedBox(height: 4),

        _buildPatientInfo(data, font),
        pw.SizedBox(height: 5),

        _buildDiagnosisSection(data, font),
        pw.SizedBox(height: 4),

        _buildRemarksSection(data, font),
        pw.SizedBox(height: 4),

        _buildPurposeStatement(data, font),

        pw.Spacer(),

        _buildDoctorSignature(data, font, fontBold),
        pw.SizedBox(height: 8),
      ],
    );
  }

  static pw.Widget _buildReferenceHeader(pw.Font font) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('Reference No: BatStateU-CE-12', style: pw.TextStyle(fontSize: 6, font: font)),
        pw.Text('Effectivity Date: July 01, 2024', style: pw.TextStyle(fontSize: 6, font: font)),
        pw.Text('Revision No.: 02', style: pw.TextStyle(fontSize: 6, font: font)),
      ],
    );
  }

  static pw.Widget _buildUniversityHeader(pw.Font font, pw.Font fontBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        pw.Text('Republic of the Philippines', style: pw.TextStyle(fontSize: 8, font: font), textAlign: pw.TextAlign.center),
        pw.Text('BATANGAS STATE UNIVERSITY', style: pw.TextStyle(fontSize: 9, font: fontBold), textAlign: pw.TextAlign.center),
        pw.Text('The National Engineering University', style: pw.TextStyle(fontSize: 7, font: fontBold), textAlign: pw.TextAlign.center),
        pw.Text('Alangilan Campus', style: pw.TextStyle(fontSize: 7, font: fontBold), textAlign: pw.TextAlign.center),
        pw.Text('Golden Country Homes, Alangilan, Batangas City, Philippines 4200', style: pw.TextStyle(fontSize: 6, font: fontBold), textAlign: pw.TextAlign.center),
        pw.Text('Tel. No.: 425-0139; 425-0143 loc. 2140', style: pw.TextStyle(fontSize: 6, font: font), textAlign: pw.TextAlign.center),
        pw.Text('E-mail Address: healthservices.alangilan@g.batstate-u.edu.ph', style: pw.TextStyle(fontSize: 6, font: font), textAlign: pw.TextAlign.center),
      ],
    );
  }

  static pw.Widget _buildSmallField(String label, String value, pw.Font font) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 7, font: font)),
        pw.SizedBox(width: 2),
        pw.Container(
          width: 60,
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: pw.BorderSide(width: 0.3)),
          ),
          child: pw.Text(
            value.isEmpty ? '' : value,
            style: pw.TextStyle(fontSize: 7, font: font),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildPatientInfo(MedicalCertificateData data, pw.Font font) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('This is to certify that Mr/Ms/Mrs', style: pw.TextStyle(fontSize: 8, font: font)),
            pw.SizedBox(width: 3),
            pw.Container(
              width: 130,
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3))),
              child: pw.Text(data.patientName.isEmpty ? '' : data.patientName, style: pw.TextStyle(fontSize: 8, font: font)),
            ),
            pw.SizedBox(width: 2),
            pw.Text('-', style: pw.TextStyle(fontSize: 8, font: font)),
            pw.SizedBox(width: 2),
            pw.Container(
              width: 20,
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3))),
              child: pw.Text(data.age.isEmpty ? '' : data.age, style: pw.TextStyle(fontSize: 8, font: font), textAlign: pw.TextAlign.center),
            ),
            pw.SizedBox(width: 2),
            pw.Text('years old,', style: pw.TextStyle(fontSize: 8, font: font)),
          ],
        ),
        pw.SizedBox(height: 1),
        pw.Row(
          children: [
            pw.SizedBox(width: 160),
            pw.Text('Name', style: pw.TextStyle(fontSize: 6, font: font)),
            pw.SizedBox(width: 95),
            pw.Text('Age', style: pw.TextStyle(fontSize: 6, font: font)),
          ],
        ),
        pw.SizedBox(height: 2),

        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Container(
              width: 30,
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3))),
              child: pw.Text(data.sex.isEmpty ? '' : data.sex, style: pw.TextStyle(fontSize: 8, font: font), textAlign: pw.TextAlign.center),
            ),
            pw.SizedBox(width: 2),
            pw.Text('-', style: pw.TextStyle(fontSize: 8, font: font)),
            pw.SizedBox(width: 2),
            pw.Container(
              width: 45,
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3))),
              child: pw.Text(data.civilStatus.isEmpty ? '' : data.civilStatus, style: pw.TextStyle(fontSize: 8, font: font), textAlign: pw.TextAlign.center),
            ),
            pw.Text(' , a resident of', style: pw.TextStyle(fontSize: 8, font: font)),
            pw.SizedBox(width: 3),
            pw.Expanded(
              child: pw.Container(
                decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3))),
                child: pw.Text(data.address.isEmpty ? '' : data.address, style: pw.TextStyle(fontSize: 8, font: font)),
              ),
            ),
            pw.Text(' , was confined/', style: pw.TextStyle(fontSize: 8, font: font)),
          ],
        ),
        pw.SizedBox(height: 1),
        pw.Row(
          children: [
            pw.Text('Sex', style: pw.TextStyle(fontSize: 6, font: font)),
            pw.SizedBox(width: 25),
            pw.Text('Civil Status', style: pw.TextStyle(fontSize: 6, font: font)),
            pw.SizedBox(width: 73),
            pw.Text('Address', style: pw.TextStyle(fontSize: 6, font: font)),
          ],
        ),
        pw.SizedBox(height: 2),

        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('examined/consulted on', style: pw.TextStyle(fontSize: 8, font: font)),
            pw.SizedBox(width: 3),
            pw.Container(
              width: 90,
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3))),
              child: pw.Text(_formatDate(data.examDate), style: pw.TextStyle(fontSize: 8, font: font)),
            ),
          ],
        ),
        pw.SizedBox(height: 1),
        pw.Row(
          children: [
            pw.SizedBox(width: 120),
            pw.Text('Date', style: pw.TextStyle(fontSize: 6, font: font)),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildDiagnosisSection(MedicalCertificateData data, pw.Font font) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text('Diagnosis:', style: pw.TextStyle(fontSize: 8, font: font)),
        pw.SizedBox(width: 3),
        pw.Expanded(
          child: pw.Container(
            decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3))),
            child: pw.Text(data.diagnosis.isEmpty ? '' : data.diagnosis, style: pw.TextStyle(fontSize: 8, font: font)),
          ),
        ),
      ],
    );
  }

  static pw.Widget _buildRemarksSection(MedicalCertificateData data, pw.Font font) {
    return pw.Column(
      children: [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text('Remarks:', style: pw.TextStyle(fontSize: 8, font: font)),
            pw.SizedBox(width: 3),
            pw.Expanded(
              child: pw.Container(
                decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3))),
                child: pw.Text(data.remarks.isEmpty ? '' : data.remarks, style: pw.TextStyle(fontSize: 8, font: font)),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 1.5),
        pw.Container(
          width: double.infinity,
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3))),
          child: pw.SizedBox(height: 8),
        ),
      ],
    );
  }

  static pw.Widget _buildPurposeStatement(MedicalCertificateData data, pw.Font font) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text('This medical certificate is issued upon request of the patient and for', style: pw.TextStyle(fontSize: 8, font: font)),
        pw.SizedBox(width: 3),
        pw.Container(
          width: 40,
          decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3))),
          child: pw.Text(data.purpose.isEmpty ? '' : data.purpose, style: pw.TextStyle(fontSize: 8, font: font), textAlign: pw.TextAlign.center),
        ),
        pw.SizedBox(width: 2),
        pw.Text('purpose only and not for medico-legal purposes.', style: pw.TextStyle(fontSize: 8, font: font)),
      ],
    );
  }

  static pw.Widget _buildDoctorSignature(MedicalCertificateData data, pw.Font font, pw.Font fontBold) {
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 120,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Container(
              height: 20,
              decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(width: 0.3))),
            ),
            pw.SizedBox(height: 2),
            pw.Text(
              data.doctorName.isEmpty ? '' : data.doctorName.toUpperCase(),
              style: pw.TextStyle(fontSize: 8, font: fontBold),
              textAlign: pw.TextAlign.center,
            ),
            pw.Text('NAME OF THE DOCTOR', style: pw.TextStyle(fontSize: 6, font: font), textAlign: pw.TextAlign.center),
            pw.Text('Attending Physician', style: pw.TextStyle(fontSize: 7, font: font), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 2),
            pw.Text(
              'License No.: ${data.licenseNumber.isEmpty ? "_______" : data.licenseNumber}',
              style: pw.TextStyle(fontSize: 7, font: font),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}