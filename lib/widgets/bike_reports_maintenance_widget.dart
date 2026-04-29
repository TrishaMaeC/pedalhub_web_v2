// lib/widgets/bike_reports_maintenance_widget.dart
//
// Self-contained widget: Bike Reports + Maintenance tabs + PDF export.
// Drop into any page by supplying the campus string.
//
// DEPENDENCIES — add to pubspec.yaml:
//   pdf: ^3.10.8
//   path_provider: ^2.1.2
//
// USAGE:
//   BikeReportsMaintenanceWidget(campus: userCampus)

import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';

class BikeReportsMaintenanceWidget extends StatefulWidget {
  final String campus;

  const BikeReportsMaintenanceWidget({
    super.key,
    required this.campus,
  });

  @override
  State<BikeReportsMaintenanceWidget> createState() =>
      BikeReportsMaintenanceWidgetState();
}

class BikeReportsMaintenanceWidgetState
    extends State<BikeReportsMaintenanceWidget>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  late TabController _tabController;
  bool isLoading = true;

  // ── Report state
  String selectedReportStatus = 'submitted';
  List<Map<String, dynamic>> reports = [];
  int submittedCount = 0;
  int inProgressCount = 0;
  int resolvedCount = 0;

  // ── Maintenance state
  // Valid DB statuses: available, reserved, damaged, missing_bike, maintenance, in_use
  String selectedMaintenanceStatus = 'all';
  List<Map<String, dynamic>> maintenanceBikes = [];
  int allBikesCount = 0;
  int damagedCount = 0;      // was forMaintenanceCount — maps to 'damaged' in DB
  int maintenanceCount = 0;
  int availableCount = 0;

  // ── Colours
  static const _red = Color(0xFFD32F2F);
  static const _blue = Color(0xFF1565C0);
  static const _orange = Color(0xFFF57C00);
  static const _green = Color(0xFF388E3C);
  static const _purple = Color(0xFF6A1B9A);

  // ─────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      if (_tabController.index == 1) _fetchMaintenanceBikes();
    });
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(BikeReportsMaintenanceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.campus != widget.campus) _loadAll();
  }

  // ─────────────────────────────────────────────
  // DATA FETCHING
  // ─────────────────────────────────────────────
  Future<void> _loadAll() async {
    setState(() => isLoading = true);
    try {
      await Future.wait([
        _loadMetrics(),
        _fetchReports(),
        _fetchMaintenanceBikes(),
      ]);
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> refresh() => _loadAll();

  Future<void> _loadMetrics() async {
    try {
      final allReports = await supabase
          .from('bike_reports')
          .select('id, status, bike_id, bikes(campus)')
          .not('bike_id', 'is', null);

      final campusReports = (allReports as List).where((r) {
        final bike = r['bikes'];
        if (bike == null) return false;
        return (bike['campus'] ?? '').toString().toLowerCase() ==
            widget.campus.toLowerCase();
      }).toList();

      // Valid DB statuses: available, reserved, damaged, missing_bike, maintenance, in_use
      final damaged = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'damaged')
          .ilike('campus', widget.campus);

      final maintenance = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'maintenance')
          .ilike('campus', widget.campus);

      final available = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'available')
          .ilike('campus', widget.campus);

      final reserved = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'reserved')
          .ilike('campus', widget.campus);

      final inUse = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'in_use')
          .ilike('campus', widget.campus);

      final missingBike = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'missing_bike')
          .ilike('campus', widget.campus);

      if (mounted) {
        setState(() {
          submittedCount =
              campusReports.where((r) => r['status'] == 'submitted').length;
          inProgressCount =
              campusReports.where((r) => r['status'] == 'in_progress').length;
          resolvedCount =
              campusReports.where((r) => r['status'] == 'resolved').length;
          damagedCount = (damaged as List).length;
          maintenanceCount = (maintenance as List).length;
          availableCount = (available as List).length;
          allBikesCount = damagedCount +
              maintenanceCount +
              availableCount +
              (reserved as List).length +
              (inUse as List).length +
              (missingBike as List).length;
        });
      }
    } catch (e) {
      debugPrint('Metrics error: $e');
    }
  }

  Future<void> _fetchReports() async {
    try {
      final response = await supabase
          .from('bike_reports')
          .select('*')
          .eq('status', selectedReportStatus)
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> result = [];
      for (final r in (response as List)) {
        if (r['bike_id'] == null) continue;
        final bikeRes = await supabase
            .from('bikes')
            .select('campus')
            .eq('id', r['bike_id'])
            .maybeSingle();
        if (bikeRes == null) continue;
        if ((bikeRes['campus'] ?? '').toString().toLowerCase() ==
            widget.campus.toLowerCase()) {
          result.add(Map<String, dynamic>.from(r));
        }
      }
      if (mounted) setState(() => reports = result);
    } catch (e) {
      debugPrint('Fetch reports error: $e');
    }
  }

  Future<void> _fetchMaintenanceBikes() async {
    try {
      final response = selectedMaintenanceStatus == 'all'
          ? await supabase
              .from('bikes')
              .select('*')
              .ilike('campus', widget.campus)
              .order('updated_at', ascending: false)
          : await supabase
              .from('bikes')
              .select('*')
              .eq('status', selectedMaintenanceStatus)
              .ilike('campus', widget.campus)
              .order('updated_at', ascending: false);

      if (mounted) {
        setState(() => maintenanceBikes =
            List<Map<String, dynamic>>.from(response));
      }
    } catch (e) {
      debugPrint('Fetch maintenance bikes error: $e');
    }
  }

  // ─────────────────────────────────────────────
  // EXPORT — show date range dialog then save PDF
  // ─────────────────────────────────────────────
  Future<void> _showExportDialog() async {
    DateTime from;
    DateTime to;

    final now = DateTime.now();
    from = DateTime(now.year, now.month, 1);
    to = DateTime(now.year, now.month + 1, 0);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ExportDialog(
        campus: widget.campus,
        initialFrom: from,
        initialTo: to,
        onExport: (selectedFrom, selectedTo) async {
          await _runExport(selectedFrom, selectedTo);
        },
      ),
    );
  }

  Future<void> _runExport(DateTime from, DateTime to) async {
    // ── Filter data by date range ─────────────────
    final filteredReports = reports.where((r) {
      try {
        final d = DateTime.parse(r['created_at'].toString());
        return !d.isBefore(from) &&
            !d.isAfter(to.add(const Duration(days: 1)));
      } catch (_) {
        return false;
      }
    }).toList();

    // Fetch ALL bikes for the campus for export
    List<Map<String, dynamic>> allBikes;
    try {
      final res = await supabase
          .from('bikes')
          .select('*')
          .ilike('campus', widget.campus)
          .order('updated_at', ascending: false);
      allBikes = List<Map<String, dynamic>>.from(res);
    } catch (_) {
      allBikes = maintenanceBikes;
    }

    final filteredBikes = allBikes.where((b) {
      try {
        final d = DateTime.parse(b['updated_at'].toString());
        return !d.isBefore(from) &&
            !d.isAfter(to.add(const Duration(days: 1)));
      } catch (_) {
        return false;
      }
    }).toList();

    // ── Build & download PDF ──────────────────────
    final pdfBytes = await _buildPdf(
      campus: widget.campus,
      from: from,
      to: to,
      reports: filteredReports,
      bikes: filteredBikes,
    );

    final fileName =
        'PedalHub_Report_${widget.campus.toUpperCase()}_'
        '${DateFormat('yyyyMMdd').format(from)}_'
        '${DateFormat('yyyyMMdd').format(to)}.pdf';

    // ── Download for web ──────────────────────────
    final blob = html.Blob([pdfBytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', fileName)
      ..click();
    html.Url.revokeObjectUrl(url);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _green,
          duration: const Duration(seconds: 5),
          content: Row(children: [
            const Icon(Icons.check_circle_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('PDF downloaded successfully!',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white)),
                  Text(fileName,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.white70),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ]),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────
  // PDF BUILDER
  // ─────────────────────────────────────────────
  Future<List<int>> _buildPdf({
    required String campus,
    required DateTime from,
    required DateTime to,
    required List<Map<String, dynamic>> reports,
    required List<Map<String, dynamic>> bikes,
  }) async {
    final pdf = pw.Document();
    final df = DateFormat('MMM dd, yyyy');
    final dtf = DateFormat('MMM dd, yyyy  hh:mm a');
    final dateRange = '${df.format(from)} — ${df.format(to)}';
    final generatedAt = dtf.format(DateTime.now());

    // Pdf colours
    const pRed = PdfColor.fromInt(0xFFD32F2F);
    const pDarkRed = PdfColor.fromInt(0xFF9A0007);
    const pBlue = PdfColor.fromInt(0xFF1565C0);
    const pOrange = PdfColor.fromInt(0xFFF57C00);
    const pGreen = PdfColor.fromInt(0xFF388E3C);
    const pPurple = PdfColor.fromInt(0xFF6A1B9A);
    const pGrey100 = PdfColor.fromInt(0xFFF5F7FA);
    const pGrey300 = PdfColor.fromInt(0xFFE0E0E0);
    const pGrey600 = PdfColor.fromInt(0xFF757575);
    const pBlack = PdfColor.fromInt(0xFF1A1A1A);
    const pWhite = PdfColors.white;

    // ── Summary counts
    final totalReports = reports.length;
    final newReports =
        reports.where((r) => r['status'] == 'submitted').length;
    final inProg =
        reports.where((r) => r['status'] == 'in_progress').length;
    final resolved =
        reports.where((r) => r['status'] == 'resolved').length;
    final totalBikes = bikes.length;
    final availB = bikes.where((b) => b['status'] == 'available').length;
    final damagedB = bikes.where((b) => b['status'] == 'damaged').length;
    final maintB = bikes.where((b) => b['status'] == 'maintenance').length;
    final inUseB = bikes.where((b) => b['status'] == 'in_use').length;
    final reservedB = bikes.where((b) => b['status'] == 'reserved').length;
    final missingB = bikes.where((b) => b['status'] == 'missing_bike').length;

    // ── Shared builder helpers ────────────────────

    pw.Widget header() => pw.Container(
          decoration: const pw.BoxDecoration(
            gradient: pw.LinearGradient(
              colors: [pDarkRed, pRed],
              begin: pw.Alignment.centerLeft,
              end: pw.Alignment.centerRight,
            ),
          ),
          padding: const pw.EdgeInsets.symmetric(
              horizontal: 40, vertical: 26),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('PedalHub Admin',
                      style: pw.TextStyle(
                          fontSize: 9,
                          color: PdfColor.fromInt(0xFFFFCDD2),
                          letterSpacing: 2)),
                  pw.SizedBox(height: 4),
                  pw.Text('Bike Reports & Maintenance',
                      style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: pWhite)),
                  pw.SizedBox(height: 5),
                  pw.Text(
                      'Campus: ${campus.toUpperCase()}   |   Period: $dateRange',
                      style: pw.TextStyle(
                          fontSize: 9, color: pWhite)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('Generated',
                      style: pw.TextStyle(
                          fontSize: 8,
                          color: PdfColor.fromInt(0xFFFFCDD2))),
                  pw.Text(generatedAt,
                      style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                          color: pWhite)),
                ],
              ),
            ],
          ),
        );

    pw.Widget repeatHeader(String title, PdfColor color) =>
        pw.Container(
          color: color,
          padding: const pw.EdgeInsets.symmetric(
              horizontal: 40, vertical: 10),
          child: pw.Text(title,
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: pWhite)),
        );

    pw.Widget pageFooter(int n) => pw.Container(
          padding: const pw.EdgeInsets.symmetric(
              horizontal: 40, vertical: 8),
          decoration: const pw.BoxDecoration(
              border: pw.Border(
                  top: pw.BorderSide(color: pGrey300, width: 0.8))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                  'PedalHub  •  ${campus.toUpperCase()}  •  Confidential',
                  style: pw.TextStyle(
                      fontSize: 7, color: pGrey600)),
              pw.Text('Page $n',
                  style: pw.TextStyle(
                      fontSize: 7, color: pGrey600)),
            ],
          ),
        );

    pw.Widget sectionTitle(String label, PdfColor color,
            {String? sub}) =>
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(children: [
              pw.Container(
                  width: 4,
                  height: 16,
                  color: color,
                  margin: const pw.EdgeInsets.only(right: 8)),
              pw.Text(label.toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: color,
                      letterSpacing: 1.1)),
            ]),
            if (sub != null) ...[
              pw.SizedBox(height: 3),
              pw.Text(sub,
                  style:
                      pw.TextStyle(fontSize: 8, color: pGrey600)),
            ],
            pw.SizedBox(height: 5),
            pw.Divider(color: pGrey300, thickness: 0.8),
            pw.SizedBox(height: 6),
          ],
        );

    pw.Widget summaryCard(
            String label, String value, PdfColor color) =>
        pw.Expanded(
          child: pw.Container(
            margin:
                const pw.EdgeInsets.symmetric(horizontal: 4),
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: pw.BoxDecoration(
              color: pGrey100,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(
                  color: PdfColor(
                      color.red, color.green, color.blue, 0.3),
                  width: 1),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: 22,
                        fontWeight: pw.FontWeight.bold,
                        color: color)),
                pw.SizedBox(height: 3),
                pw.Text(label,
                    style: pw.TextStyle(
                        fontSize: 8, color: pGrey600)),
              ],
            ),
          ),
        );

    pw.Widget statusBadge(String label, PdfColor color) =>
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(
              horizontal: 6, vertical: 3),
          decoration: pw.BoxDecoration(
            color: PdfColor(
                color.red, color.green, color.blue, 0.12),
            borderRadius: pw.BorderRadius.circular(10),
            border: pw.Border.all(
                color: PdfColor(
                    color.red, color.green, color.blue, 0.5),
                width: 0.8),
          ),
          child: pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                  color: color)),
        );

    pw.Widget flowStep(
            String title, String desc, PdfColor color) =>
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 5),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Container(
                  width: 8,
                  height: 8,
                  margin: const pw.EdgeInsets.only(
                      top: 1, right: 6),
                  decoration: pw.BoxDecoration(
                      color: color,
                      shape: pw.BoxShape.circle)),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment:
                      pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(title,
                        style: pw.TextStyle(
                            fontSize: 8,
                            fontWeight: pw.FontWeight.bold,
                            color: color)),
                    pw.Text(desc,
                        style: pw.TextStyle(
                            fontSize: 7, color: pGrey600)),
                  ],
                ),
              ),
            ],
          ),
        );

    String fmtDate(dynamic raw) {
      if (raw == null) return 'N/A';
      try {
        return dtf.format(
            DateTime.parse(raw.toString()).toLocal());
      } catch (_) {
        return raw.toString();
      }
    }

    PdfColor rStatusColor(String s) {
      switch (s) {
        case 'submitted':
          return pRed;
        case 'under_review':
          return pBlue;
        case 'in_progress':
          return pOrange;
        case 'resolved':
          return pGreen;
        default:
          return pGrey600;
      }
    }

    String rStatusLabel(String s) {
      switch (s) {
        case 'submitted':
          return 'New';
        case 'under_review':
          return 'Under Review';
        case 'in_progress':
          return 'In Progress';
        case 'resolved':
          return 'Resolved';
        case 'rejected':
          return 'Rejected';
        default:
          return s.replaceAll('_', ' ');
      }
    }

    // Fixed to use actual DB status values
    PdfColor bStatusColor(String s) {
      switch (s) {
        case 'available':
          return pGreen;
        case 'damaged':
          return pRed;
        case 'maintenance':
          return pOrange;
        case 'in_use':
          return pBlue;
        case 'reserved':
          return pPurple;
        case 'missing_bike':
          return pGrey600;
        default:
          return pGrey600;
      }
    }

    String bStatusLabel(String s) {
      switch (s) {
        case 'available':
          return 'Available';
        case 'damaged':
          return 'Damaged';
        case 'maintenance':
          return 'Being Fixed';
        case 'in_use':
          return 'In Use';
        case 'reserved':
          return 'Reserved';
        case 'missing_bike':
          return 'Missing';
        default:
          return s.replaceAll('_', ' ');
      }
    }

    PdfColor priorityColor(String p) {
      switch (p) {
        case 'urgent':
          return pRed;
        case 'high':
          return pOrange;
        case 'medium':
          return const PdfColor.fromInt(0xFFF9A825);
        case 'low':
          return pGreen;
        default:
          return pGrey600;
      }
    }

    // ── PAGE 1 — Cover + Summary ──────────────────
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.zero,
      build: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          header(),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 40, vertical: 24),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  sectionTitle('Summary Overview', pBlack),
                  pw.Text('Bike Reports',
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: pRed)),
                  pw.SizedBox(height: 7),
                  pw.Row(children: [
                    summaryCard('Total Reports', '$totalReports', pBlack),
                    summaryCard('New', '$newReports', pRed),
                    summaryCard('In Progress', '$inProg', pOrange),
                    summaryCard('Resolved', '$resolved', pGreen),
                  ]),
                  pw.SizedBox(height: 14),
                  pw.Text('Bike Fleet Status',
                      style: pw.TextStyle(
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                          color: pOrange)),
                  pw.SizedBox(height: 7),
                  pw.Row(children: [
                    summaryCard('Total Bikes', '$totalBikes', pBlack),
                    summaryCard('Available', '$availB', pGreen),
                    summaryCard('Damaged', '$damagedB', pRed),
                    summaryCard('Being Fixed', '$maintB', pOrange),
                  ]),
                  pw.SizedBox(height: 7),
                  pw.Row(children: [
                    summaryCard('In Use', '$inUseB', pBlue),
                    summaryCard('Reserved', '$reservedB', pPurple),
                    summaryCard('Missing', '$missingB', pGrey600),
                    pw.Expanded(child: pw.SizedBox()),
                  ]),
                  pw.SizedBox(height: 24),
                  sectionTitle('Status Flow Reference', pBlack),
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment:
                              pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Bike Reports Flow',
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold,
                                    color: pRed)),
                            pw.SizedBox(height: 6),
                            flowStep('Submitted',
                                'User submits a bike issue', pRed),
                            flowStep('Under Review',
                                'GSO acknowledges report', pBlue),
                            flowStep('In Progress',
                                'Bike flagged for maintenance',
                                pOrange),
                            flowStep('Resolved',
                                'Issue fixed and closed', pGreen),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 24),
                      pw.Expanded(
                        child: pw.Column(
                          crossAxisAlignment:
                              pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Bike Status Flow',
                                style: pw.TextStyle(
                                    fontSize: 9,
                                    fontWeight: pw.FontWeight.bold,
                                    color: pOrange)),
                            pw.SizedBox(height: 6),
                            flowStep('Available',
                                'Ready for borrowing', pGreen),
                            flowStep('Damaged',
                                'Flagged as damaged, needs repair',
                                pRed),
                            flowStep('Maintenance',
                                'Worker assigned, being fixed',
                                pOrange),
                            flowStep('Available (again)',
                                'Repair done, back in service',
                                pGreen),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          pageFooter(1),
        ],
      ),
    ));

    // ── PAGE 2+ — Bike Reports table ─────────────
    if (reports.isNotEmpty) {
      final rRows = reports.map((r) {
        final status = r['status'] ?? 'submitted';
        final priority = r['priority'] ?? 'medium';
        final desc = r['description']?.toString() ?? '';
        return [
          pw.Text(r['reporter_name'] ?? 'Unknown',
              style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: pBlack)),
          pw.Text('${r['bike_number'] ?? 'N/A'}',
              style: pw.TextStyle(fontSize: 8, color: pBlack)),
          pw.Text(
              (r['issue_type'] ?? 'other')
                  .toString()
                  .replaceAll('_', ' ')
                  .split(' ')
                  .map((w) => w.isEmpty
                      ? w
                      : w[0].toUpperCase() + w.substring(1))
                  .join(' '),
              style: pw.TextStyle(fontSize: 8, color: pBlack)),
          statusBadge(rStatusLabel(status), rStatusColor(status)),
          statusBadge(priority.toUpperCase(), priorityColor(priority)),
          pw.Text(fmtDate(r['created_at']),
              style: pw.TextStyle(fontSize: 7, color: pGrey600)),
          pw.Text(
              desc.length > 60
                  ? '${desc.substring(0, 60)}...'
                  : desc.isEmpty
                      ? '—'
                      : desc,
              style: pw.TextStyle(fontSize: 7, color: pGrey600)),
        ];
      }).toList();

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        header: (ctx) => ctx.pageNumber == 1
            ? header()
            : repeatHeader('Bike Reports (continued)', pRed),
        footer: (ctx) => pageFooter(ctx.pageNumber + 1),
        build: (ctx) => [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 40, vertical: 20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionTitle('Bike Reports Detail', pRed,
                    sub:
                        '$totalReports report(s) in selected date range'),
                pw.TableHelper.fromTextArray(
                  headers: [
                    'Reporter',
                    'Bike',
                    'Issue Type',
                    'Status',
                    'Priority',
                    'Date Reported',
                    'Description',
                  ],
                  data: rRows,
                  headerStyle: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: pWhite),
                  headerDecoration:
                      const pw.BoxDecoration(color: pRed),
                  cellHeight: 28,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.center,
                    2: pw.Alignment.centerLeft,
                    3: pw.Alignment.center,
                    4: pw.Alignment.center,
                    5: pw.Alignment.centerLeft,
                    6: pw.Alignment.centerLeft,
                  },
                  cellStyle:
                      pw.TextStyle(fontSize: 8, color: pBlack),
                  rowDecoration: const pw.BoxDecoration(
                      color: PdfColors.white),
                  oddRowDecoration:
                      const pw.BoxDecoration(color: pGrey100),
                  border: pw.TableBorder.all(
                      color: pGrey300, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.8),
                    1: const pw.FlexColumnWidth(1.0),
                    2: const pw.FlexColumnWidth(1.5),
                    3: const pw.FlexColumnWidth(1.3),
                    4: const pw.FlexColumnWidth(1.0),
                    5: const pw.FlexColumnWidth(1.8),
                    6: const pw.FlexColumnWidth(2.4),
                  },
                ),
              ],
            ),
          ),
        ],
      ));
    }

    // ── PAGE — Maintenance/Fleet table ──────────────────
    if (bikes.isNotEmpty) {
      final bRows = bikes.map((b) {
        final status = b['status'] ?? 'available';
        final notes = b['maintenance_notes']?.toString() ?? '';
        return [
          pw.Text('${b['bike_number'] ?? 'N/A'}',
              style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: pBlack)),
          statusBadge(bStatusLabel(status), bStatusColor(status)),
          pw.Text(b['maintenance_worker'] ?? '—',
              style: pw.TextStyle(fontSize: 8, color: pBlack)),
          pw.Text(
              notes.length > 50
                  ? '${notes.substring(0, 50)}...'
                  : notes.isEmpty
                      ? '—'
                      : notes,
              style: pw.TextStyle(fontSize: 7, color: pGrey600)),
          pw.Text(fmtDate(b['maintenance_started_at']),
              style: pw.TextStyle(fontSize: 7, color: pGrey600)),
          pw.Text(fmtDate(b['last_maintenance_date']),
              style: pw.TextStyle(fontSize: 7, color: pGrey600)),
          pw.Text('${b['total_rides'] ?? 0}',
              style: pw.TextStyle(fontSize: 8, color: pBlack)),
        ];
      }).toList();

      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        header: (ctx) => ctx.pageNumber == 1
            ? header()
            : repeatHeader('Fleet Status (continued)', pOrange),
        footer: (ctx) => pageFooter(ctx.pageNumber + 1),
        build: (ctx) => [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(
                horizontal: 40, vertical: 20),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                sectionTitle('Bike Fleet Detail', pOrange,
                    sub:
                        '$totalBikes bike(s) in selected date range'),
                pw.TableHelper.fromTextArray(
                  headers: [
                    'Bike No.',
                    'Status',
                    'Worker',
                    'Notes',
                    'Started At',
                    'Last Maintenance',
                    'Rides',
                  ],
                  data: bRows,
                  headerStyle: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: pw.FontWeight.bold,
                      color: pWhite),
                  headerDecoration:
                      const pw.BoxDecoration(color: pOrange),
                  cellHeight: 28,
                  cellAlignments: {
                    0: pw.Alignment.centerLeft,
                    1: pw.Alignment.center,
                    2: pw.Alignment.centerLeft,
                    3: pw.Alignment.centerLeft,
                    4: pw.Alignment.centerLeft,
                    5: pw.Alignment.centerLeft,
                    6: pw.Alignment.center,
                  },
                  cellStyle:
                      pw.TextStyle(fontSize: 8, color: pBlack),
                  rowDecoration: const pw.BoxDecoration(
                      color: PdfColors.white),
                  oddRowDecoration:
                      const pw.BoxDecoration(color: pGrey100),
                  border: pw.TableBorder.all(
                      color: pGrey300, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.0),
                    1: const pw.FlexColumnWidth(1.5),
                    2: const pw.FlexColumnWidth(1.5),
                    3: const pw.FlexColumnWidth(2.4),
                    4: const pw.FlexColumnWidth(1.8),
                    5: const pw.FlexColumnWidth(1.8),
                    6: const pw.FlexColumnWidth(0.8),
                  },
                ),
              ],
            ),
          ),
        ],
      ));
    }

    return pdf.save();
  }

  // ─────────────────────────────────────────────
  // REPORT ACTIONS
  // ─────────────────────────────────────────────
  Future<void> _acknowledgeReport(
      Map<String, dynamic> report) async {
    try {
      await supabase.from('bike_reports').update({
        'status': 'under_review',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', report['id']);
      _showSnack('Report acknowledged — now under review.', _blue);
      await _loadAll();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _markInProgress(Map<String, dynamic> report) async {
    final ok = await _confirmDialog(
      title: 'Set For Maintenance',
      message:
          '${report['bike_number']} will be marked "damaged" and this report set to in progress.',
      confirmLabel: 'Confirm',
      confirmColor: _orange,
    );
    if (!ok) return;
    try {
      await supabase.from('bike_reports').update({
        'status': 'in_progress',
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', report['id']);
      if (report['bike_id'] != null) {
        // Use 'damaged' — valid DB status for bikes needing repair
        await supabase.from('bikes').update({
          'status': 'damaged',
          'maintenance_started_at':
              DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', report['bike_id']);
      }
      _showSnack('Bike marked as damaged, pending maintenance.', _orange);
      await _loadAll();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _resolveReport(Map<String, dynamic> report) async {
    final ctrl = TextEditingController();
    final notes = await _remarksDialog(ctrl,
        title: 'Resolution Notes (optional)');
    if (notes == null) return;
    try {
      await supabase.from('bike_reports').update({
        'status': 'resolved',
        'admin_notes':
            notes.trim().isEmpty ? null : notes.trim(),
        'resolved_by': supabase.auth.currentUser?.id,
        'resolved_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', report['id']);
      _showSnack('Report resolved.', _green);
      await _loadAll();
    } catch (e) {
      _showError(e);
    }
  }

  // ─────────────────────────────────────────────
  // MAINTENANCE ACTIONS
  // ─────────────────────────────────────────────
  Future<void> _assignWorker(Map<String, dynamic> bike) async {
    final workerCtrl = TextEditingController(
        text: bike['maintenance_worker'] ?? '');
    final notesCtrl = TextEditingController(
        text: bike['maintenance_notes'] ?? '');

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: _orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.engineering_rounded,
                color: _orange, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                'Assign Worker — ${bike['bike_number']}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Worker Name *',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: workerCtrl,
              decoration: InputDecoration(
                hintText: 'Enter worker name',
                prefixIcon: const Icon(Icons.person_rounded),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Maintenance Notes (optional)',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Describe the issue or work needed...',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: Text('Cancel',
                  style: TextStyle(color: Colors.grey[600]))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(ctx, {
              'worker': workerCtrl.text.trim(),
              'notes': notesCtrl.text.trim(),
            }),
            child: const Text('Assign'),
          ),
        ],
      ),
    );

    if (result == null || result['worker']!.isEmpty) return;
    try {
      // Use 'maintenance' — valid DB status for bikes being actively fixed
      await supabase.from('bikes').update({
        'status': 'maintenance',
        'maintenance_worker': result['worker'],
        'maintenance_notes':
            result['notes']!.isEmpty ? null : result['notes'],
        'maintenance_started_at':
            DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bike['id']);
      _showSnack(
          'Worker "${result['worker']}" assigned to ${bike['bike_number']}.',
          _orange);
      await _loadAll();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _setForMaintenance(Map<String, dynamic> bike) async {
    final ok = await _confirmDialog(
      title: 'Set as Damaged',
      message:
          '${bike['bike_number']} will be marked as "damaged" and flagged for maintenance.',
      confirmLabel: 'Confirm',
      confirmColor: _red,
    );
    if (!ok) return;
    try {
      // Use 'damaged' — valid DB status
      await supabase.from('bikes').update({
        'status': 'damaged',
        'maintenance_started_at':
            DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bike['id']);
      _showSnack(
          '${bike['bike_number']} marked as damaged.', _red);
      await _loadAll();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _markBikeDone(Map<String, dynamic> bike) async {
    final ok = await _confirmDialog(
      title: 'Mark as Done',
      message:
          '${bike['bike_number']} will be set back to available.',
      confirmLabel: 'Mark Done',
      confirmColor: _green,
    );
    if (!ok) return;
    try {
      await supabase.from('bikes').update({
        'status': 'available',
        'maintenance_worker': null,
        'maintenance_notes': null,
        'last_maintenance_date':
            DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', bike['id']);
      _showSnack(
          '${bike['bike_number']} is now available.', _green);
      await _loadAll();
    } catch (e) {
      _showError(e);
    }
  }

  // ─────────────────────────────────────────────
  // DIALOG HELPERS
  // ─────────────────────────────────────────────
  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: color));
  }

  void _showError(dynamic e) => _showSnack('Error: $e', Colors.red);

  Future<bool> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold)),
            content: Text(message),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: confirmColor,
                    foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(confirmLabel),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _remarksDialog(TextEditingController ctrl,
      {String title = 'Add Remarks (optional)'}) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16)),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
              hintText: 'Enter notes...',
              border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1A1A1A),
                foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // STATUS HELPERS
  // ─────────────────────────────────────────────
  Color _rStatusColor(String s) {
    switch (s) {
      case 'submitted':
        return _red;
      case 'under_review':
        return _blue;
      case 'in_progress':
        return _orange;
      case 'resolved':
        return _green;
      default:
        return Colors.grey;
    }
  }

  String _rStatusLabel(String s) {
    switch (s) {
      case 'submitted':
        return 'New';
      case 'under_review':
        return 'Under Review';
      case 'in_progress':
        return 'In Progress';
      case 'resolved':
        return 'Resolved';
      case 'rejected':
        return 'Rejected';
      default:
        return s.replaceAll('_', ' ');
    }
  }

  Color _priorityColor(String p) {
    switch (p) {
      case 'urgent':
        return _red;
      case 'high':
        return _orange;
      case 'medium':
        return const Color(0xFFF9A825);
      case 'low':
        return _green;
      default:
        return Colors.grey;
    }
  }

  // Fixed to use actual DB status values
  Color _bStatusColor(String s) {
    switch (s) {
      case 'available':
        return _green;
      case 'damaged':
        return _red;
      case 'maintenance':
        return _orange;
      case 'in_use':
        return _blue;
      case 'reserved':
        return _purple;
      case 'missing_bike':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _bStatusLabel(String s) {
    switch (s) {
      case 'available':
        return 'Available';
      case 'damaged':
        return 'Damaged';
      case 'maintenance':
        return 'Being Fixed';
      case 'in_use':
        return 'In Use';
      case 'reserved':
        return 'Reserved';
      case 'missing_bike':
        return 'Missing';
      default:
        return s.replaceAll('_', ' ');
    }
  }

  // ─────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Tab bar + Export button ────────────────
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border:
                Border(bottom: BorderSide(color: Colors.grey.shade200)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  labelColor: _red,
                  unselectedLabelColor: Colors.grey[500],
                  indicatorColor: _red,
                  indicatorWeight: 3,
                  labelStyle: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                  tabs: [
                    _buildTab(
                      icon: Icons.report_rounded,
                      label: 'Bike Reports',
                      badgeCount: submittedCount,
                      badgeColor: _red,
                    ),
                    _buildTab(
                      icon: Icons.build_rounded,
                      label: 'Maintenance',
                      badgeCount: damagedCount,
                      badgeColor: _orange,
                    ),
                  ],
                ),
              ),

              // ── Export button ──────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  onPressed: _showExportDialog,
                  icon: const Icon(
                      Icons.picture_as_pdf_rounded, size: 18),
                  label: const Text('Export Report',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13)),
                ),
              ),
            ],
          ),
        ),

        // ── Tab content ───────────────────────────
        Expanded(
          child: isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(_red)))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildReportsTab(),
                    _buildMaintenanceTab(),
                  ],
                ),
        ),
      ],
    );
  }

  Tab _buildTab({
    required IconData icon,
    required String label,
    required int badgeCount,
    required Color badgeColor,
  }) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(icon),
              if (badgeCount > 0)
                Positioned(
                  right: -10,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                        color: badgeColor,
                        shape: BoxShape.circle),
                    child: Text(badgeCount.toString(),
                        style: const TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Text(label),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════
  // REPORTS TAB
  // ══════════════════════════════════════════════
  Widget _buildReportsTab() {
    return RefreshIndicator(
      color: _red,
      onRefresh: _loadAll,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Metric cards
            Row(children: [
              _MetricCard(
                  label: 'New Reports',
                  count: submittedCount,
                  icon: Icons.fiber_new_rounded,
                  color: _red),
              const SizedBox(width: 16),
              _MetricCard(
                  label: 'In Progress',
                  count: inProgressCount,
                  icon: Icons.pending_rounded,
                  color: _orange),
              const SizedBox(width: 16),
              _MetricCard(
                  label: 'Resolved',
                  count: resolvedCount,
                  icon: Icons.check_circle_rounded,
                  color: _green),
            ]),
            const SizedBox(height: 24),

            // Filter chips
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _filterChip('submitted', 'New',
                    Icons.fiber_new_rounded, _red, true),
                _filterChip('under_review', 'Under Review',
                    Icons.search_rounded, _blue, true),
                _filterChip('in_progress', 'In Progress',
                    Icons.pending_rounded, _orange, true),
                _filterChip('resolved', 'Resolved',
                    Icons.check_circle_rounded, _green, true),
                _filterChip('rejected', 'Rejected',
                    Icons.cancel_rounded, Colors.grey, true),
              ],
            ),
            const SizedBox(height: 20),

            if (reports.isEmpty)
              _emptyState('No reports found', Icons.inbox_outlined)
            else
              ...reports.map(_reportCard),
          ],
        ),
      ),
    );
  }

  Widget _reportCard(Map<String, dynamic> r) {
    final status = r['status'] ?? 'submitted';
    final priority = r['priority'] ?? 'medium';
    final photoUrl = r['photo_url'] as String?;
    final statusColor = _rStatusColor(status);
    final statusLabel = _rStatusLabel(status);
    final priorityColor = _priorityColor(priority);

    String createdAt = 'N/A';
    try {
      createdAt = DateFormat('MMM dd, yyyy HH:mm')
          .format(DateTime.parse(r['created_at'].toString()).toLocal());
    } catch (_) {}

    final issueType = (r['issue_type'] ?? 'other')
        .toString()
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) =>
            w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
        .join(' ');

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (photoUrl != null && photoUrl.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16)),
              child: GestureDetector(
                onTap: () => _showPhotoDialog(photoUrl),
                child: Stack(children: [
                  Image.network(photoUrl,
                      width: double.infinity,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                          height: 80,
                          color: Colors.grey[100],
                          child: const Center(
                              child: Icon(
                                  Icons.broken_image_rounded,
                                  color: Colors.grey,
                                  size: 32)))),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_in_rounded,
                              color: Colors.white, size: 14),
                          SizedBox(width: 4),
                          Text('Tap to expand',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
                ]),
              ),
            ),

          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.report_rounded,
                        color: statusColor, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Flexible(
                              child: Text(
                                  r['reporter_name'] ?? 'Unknown',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold))),
                          const SizedBox(width: 8),
                          _chip(statusLabel, statusColor),
                          const SizedBox(width: 6),
                          _chip(priority.toUpperCase(),
                              priorityColor),
                        ]),
                        const SizedBox(height: 3),
                        Text(
                            '${r['bike_number'] ?? 'N/A'}  •  $issueType',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600])),
                        Text('Reported: $createdAt',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[500])),
                      ],
                    ),
                  ),
                ]),

                if (r['description'] != null &&
                    r['description'].toString().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: Colors.grey[200]!)),
                    child: Text(r['description'],
                        style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700])),
                  ),
                ],

                if (r['admin_notes'] != null &&
                    r['admin_notes'].toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Icon(Icons.notes_rounded,
                        size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          'Admin Notes: ${r['admin_notes']}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic)),
                    ),
                  ]),
                ],

                const SizedBox(height: 14),

                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (status == 'submitted')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8))),
                        onPressed: () => _acknowledgeReport(r),
                        icon: const Icon(
                            Icons.visibility_rounded, size: 16),
                        label: const Text('Acknowledge',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                    if (status == 'under_review') ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _orange,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8))),
                        onPressed: () => _markInProgress(r),
                        icon: const Icon(Icons.build_rounded,
                            size: 16),
                        label: const Text('Set For Maintenance',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8))),
                        onPressed: () => _resolveReport(r),
                        icon: const Icon(
                            Icons.check_circle_rounded, size: 16),
                        label: const Text('Resolve',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                    ],
                    if (status == 'in_progress')
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(8))),
                        onPressed: () => _resolveReport(r),
                        icon: const Icon(
                            Icons.check_circle_rounded, size: 16),
                        label: const Text('Mark Resolved',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13)),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPhotoDialog(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Stack(children: [
          ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                      padding: const EdgeInsets.all(32),
                      color: Colors.white,
                      child: const Icon(Icons.broken_image_rounded,
                          size: 64, color: Colors.grey)))),
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // MAINTENANCE TAB
  // ══════════════════════════════════════════════
  Widget _buildMaintenanceTab() {
    return RefreshIndicator(
      color: _red,
      onRefresh: _fetchMaintenanceBikes,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _MetricCard(
                  label: 'All Bikes',
                  count: allBikesCount,
                  icon: Icons.pedal_bike_rounded,
                  color: _blue),
              const SizedBox(width: 16),
              _MetricCard(
                  label: 'Damaged',
                  count: damagedCount,
                  icon: Icons.warning_amber_rounded,
                  color: _red),
              const SizedBox(width: 16),
              _MetricCard(
                  label: 'Being Fixed',
                  count: maintenanceCount,
                  icon: Icons.engineering_rounded,
                  color: _orange),
              const SizedBox(width: 16),
              _MetricCard(
                  label: 'Available',
                  count: availableCount,
                  icon: Icons.check_circle_rounded,
                  color: _green),
            ]),
            const SizedBox(height: 24),

            // Filter chips — all use valid DB status values
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _filterChip('all', 'All Bikes',
                    Icons.pedal_bike_rounded, _blue, false),
                _filterChip('damaged', 'Damaged',
                    Icons.warning_amber_rounded, _red, false),
                _filterChip('maintenance', 'Being Fixed',
                    Icons.engineering_rounded, _orange, false),
                _filterChip('available', 'Available',
                    Icons.check_circle_rounded, _green, false),
                _filterChip('in_use', 'In Use',
                    Icons.directions_bike_rounded, _blue, false),
                _filterChip('reserved', 'Reserved',
                    Icons.bookmark_rounded, _purple, false),
                _filterChip('missing_bike', 'Missing',
                    Icons.search_off_rounded, Colors.grey, false),
              ],
            ),
            const SizedBox(height: 20),

            if (maintenanceBikes.isEmpty)
              _emptyState('No bikes found', Icons.pedal_bike_outlined)
            else
              ...maintenanceBikes.map(_bikeCard),
          ],
        ),
      ),
    );
  }

  Widget _bikeCard(Map<String, dynamic> b) {
    final status = b['status'] ?? 'available';
    // All statuses from actual DB constraint:
    // available, reserved, damaged, missing_bike, maintenance, in_use
    final isDamaged = status == 'damaged';
    final isBeingFixed = status == 'maintenance';
    final isAvailable = status == 'available';
    final isInUse = status == 'in_use';
    final isReserved = status == 'reserved';
    final isMissing = status == 'missing_bike';

    final color = _bStatusColor(status);
    final statusLabel = _bStatusLabel(status);

    String lastMaint = 'Never';
    try {
      lastMaint = DateFormat('MMM dd, yyyy').format(
          DateTime.parse(b['last_maintenance_date'].toString())
              .toLocal());
    } catch (_) {}

    String startedAt = 'N/A';
    try {
      startedAt = DateFormat('MMM dd, yyyy HH:mm').format(
          DateTime.parse(b['maintenance_started_at'].toString())
              .toLocal());
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14)),
              child: Icon(
                  isBeingFixed
                      ? Icons.engineering_rounded
                      : isMissing
                          ? Icons.search_off_rounded
                          : Icons.pedal_bike_rounded,
                  color: color,
                  size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text('${b['bike_number']}',
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    _chip(statusLabel, color),
                  ]),
                  const SizedBox(height: 3),
                  Text(
                      'Campus: ${(b['campus'] ?? 'N/A').toString().toUpperCase()}',
                      style: TextStyle(
                          fontSize: 13, color: Colors.grey[600])),
                  Text(
                      'Last Maintenance: $lastMaint  •  Rides: ${b['total_rides'] ?? 0}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey[500])),
                ],
              ),
            ),
          ]),

          if (isBeingFixed || isDamaged) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: color.withOpacity(0.2))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isBeingFixed &&
                      b['maintenance_worker'] != null) ...[
                    Row(children: [
                      Icon(Icons.engineering_rounded,
                          size: 14, color: color),
                      const SizedBox(width: 6),
                      Text('Worker: ${b['maintenance_worker']}',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: color)),
                    ]),
                    const SizedBox(height: 4),
                  ],
                  if (b['maintenance_notes'] != null &&
                      b['maintenance_notes']
                          .toString()
                          .isNotEmpty) ...[
                    Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notes_rounded,
                            size: 14, color: Colors.grey[500]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(b['maintenance_notes'],
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600])),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(children: [
                    Icon(Icons.schedule_rounded,
                        size: 14, color: Colors.grey[500]),
                    const SizedBox(width: 6),
                    Text('Started: $startedAt',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500])),
                  ]),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Damaged bike — assign a worker (moves to 'maintenance')
              if (isDamaged)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _orange,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                  onPressed: () => _assignWorker(b),
                  icon: const Icon(Icons.engineering_rounded,
                      size: 18),
                  label: const Text('Assign Worker',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),

              // Available bike — flag as damaged
              if (isAvailable)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                  onPressed: () => _setForMaintenance(b),
                  icon: const Icon(Icons.build_rounded, size: 18),
                  label: const Text('Mark as Damaged',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),

              // Being fixed — edit worker or mark done
              if (isBeingFixed) ...[
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: _orange,
                      side: const BorderSide(color: _orange),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                  onPressed: () => _assignWorker(b),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: const Text('Edit Worker',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                  onPressed: () => _markBikeDone(b),
                  icon: const Icon(Icons.check_circle_rounded,
                      size: 18),
                  label: const Text('Mark Done',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],

              // In use / reserved / missing — read-only display, no action
              if (isInUse || isReserved || isMissing)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withOpacity(0.3)),
                  ),
                  child: Text(
                    isInUse
                        ? 'Currently in use'
                        : isReserved
                            ? 'Reserved by user'
                            : 'Reported missing',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: color),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────
  // SHARED SMALL WIDGETS
  // ─────────────────────────────────────────────
  Widget _filterChip(String value, String label, IconData icon,
      Color color, bool isReport) {
    final isSelected = isReport
        ? selectedReportStatus == value
        : selectedMaintenanceStatus == value;
    return GestureDetector(
      onTap: () {
        setState(() {
          if (isReport) {
            selectedReportStatus = value;
          } else {
            selectedMaintenanceStatus = value;
          }
        });
        isReport ? _fetchReports() : _fetchMaintenanceBikes();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
            horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: isSelected ? color : Colors.grey[300]!,
              width: 1.5),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                      color: color.withOpacity(0.25),
                      blurRadius: 10,
                      offset: const Offset(0, 3))
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: isSelected ? Colors.white : color),
            const SizedBox(width: 7),
            Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : color)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.5))),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color)),
      );

  Widget _emptyState(String msg, IconData icon) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 80),
          child: Column(children: [
            Icon(icon, size: 72, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(msg,
                style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Metric card
// ─────────────────────────────────────────────────────────────────────────────
class _MetricCard extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.15)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 3))
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(count.toString(),
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: color)),
              Text(label,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey[600])),
            ],
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Export dialog  (date range picker + quick presets)
// ─────────────────────────────────────────────────────────────────────────────
class _ExportDialog extends StatefulWidget {
  final String campus;
  final DateTime initialFrom;
  final DateTime initialTo;
  final Future<void> Function(DateTime, DateTime) onExport;

  const _ExportDialog({
    required this.campus,
    required this.initialFrom,
    required this.initialTo,
    required this.onExport,
  });

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  late DateTime _from;
  late DateTime _to;
  bool _exporting = false;

  static const _red = Color(0xFFD32F2F);
  static const _darkRed = Color(0xFF9A0007);

  @override
  void initState() {
    super.initState();
    _from = widget.initialFrom;
    _to = widget.initialTo;
  }

  String get _fmt => 'MMM dd, yyyy';
  String get _fmtFrom => DateFormat(_fmt).format(_from);
  String get _fmtTo => DateFormat(_fmt).format(_to);

  Future<void> _pickFrom() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020),
      lastDate: _to,
      builder: (ctx, child) => _theme(child!),
    );
    if (p != null) setState(() => _from = p);
  }

  Future<void> _pickTo() async {
    final p = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: _from,
      lastDate: DateTime.now(),
      builder: (ctx, child) => _theme(child!),
    );
    if (p != null) setState(() => _to = p);
  }

  Widget _theme(Widget child) => Theme(
        data: ThemeData.light().copyWith(
          colorScheme: const ColorScheme.light(
              primary: _red, onPrimary: Colors.white),
        ),
        child: child,
      );

  void _preset(String key) {
    final now = DateTime.now();
    setState(() {
      switch (key) {
        case 'this_month':
          _from = DateTime(now.year, now.month, 1);
          _to = DateTime(now.year, now.month + 1, 0);
          break;
        case 'last_month':
          _from = DateTime(now.year, now.month - 1, 1);
          _to = DateTime(now.year, now.month, 0);
          break;
        case 'last_7':
          _from = now.subtract(const Duration(days: 7));
          _to = now;
          break;
        case 'last_30':
          _from = now.subtract(const Duration(days: 30));
          _to = now;
          break;
        case 'this_year':
          _from = DateTime(now.year, 1, 1);
          _to = DateTime(now.year, 12, 31);
          break;
      }
    });
  }

  Future<void> _handleExport() async {
    setState(() => _exporting = true);
    try {
      await widget.onExport(_from, _to);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(
          horizontal: 120, vertical: 80),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [_darkRed, _red]),
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: 28, vertical: 20),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.picture_as_pdf_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Export Combined Report',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white)),
                    Text(
                        'Campus: ${widget.campus.toUpperCase()}  •  Saves as PDF',
                        style: TextStyle(
                            fontSize: 12,
                            color:
                                Colors.white.withOpacity(0.8))),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white),
                onPressed: _exporting
                    ? null
                    : () => Navigator.pop(context),
              ),
            ]),
          ),

          // Body
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info notice
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.info_outline_rounded,
                        size: 18, color: Colors.grey[500]),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Exports a combined PDF with a summary, all bike reports, and fleet status records for the selected period.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[700]),
                      ),
                    ),
                  ]),
                ),

                const SizedBox(height: 22),

                // Quick presets
                Text('QUICK PRESETS',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Colors.grey[500])),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _presetBtn('This Month', 'this_month'),
                    _presetBtn('Last Month', 'last_month'),
                    _presetBtn('Last 7 Days', 'last_7'),
                    _presetBtn('Last 30 Days', 'last_30'),
                    _presetBtn('This Year', 'this_year'),
                  ],
                ),

                const SizedBox(height: 22),

                // Custom range
                Text('CUSTOM DATE RANGE',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: Colors.grey[500])),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                      child: _dateField('From', _fmtFrom,
                          _exporting ? null : _pickFrom)),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12),
                    child: Icon(Icons.arrow_forward_rounded,
                        color: Colors.grey[400], size: 20),
                  ),
                  Expanded(
                      child: _dateField('To', _fmtTo,
                          _exporting ? null : _pickTo)),
                ]),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '${_to.difference(_from).inDays + 1} day(s) selected',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey[500]),
                  ),
                ),
              ],
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 28, vertical: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border(
                  top: BorderSide(color: Colors.grey.shade200)),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(20)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _exporting
                      ? null
                      : () => Navigator.pop(context),
                  child: Text('Cancel',
                      style:
                          TextStyle(color: Colors.grey[600])),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  onPressed: _exporting ? null : _handleExport,
                  icon: _exporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(
                                      Colors.white)))
                      : const Icon(Icons.save_alt_rounded,
                          size: 18),
                  label: Text(
                    _exporting ? 'Saving PDF...' : 'Save PDF',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetBtn(String label, String key) => OutlinedButton(
        onPressed: _exporting ? null : () => _preset(key),
        style: OutlinedButton.styleFrom(
          foregroundColor: _red,
          side: BorderSide(color: Colors.grey.shade300),
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      );

  Widget _dateField(
          String label, String value, VoidCallback? onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(children: [
            const Icon(Icons.calendar_today_rounded,
                size: 16, color: _red),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10, color: Colors.grey[500])),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A))),
              ],
            ),
            const Spacer(),
            Icon(Icons.arrow_drop_down_rounded,
                color: Colors.grey[400]),
          ]),
        ),
      );
}