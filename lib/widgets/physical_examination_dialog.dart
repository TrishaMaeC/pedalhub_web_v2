// lib/widgets/physical_examination_dialog.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signature/signature.dart';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

class PhysicalExaminationDialog extends StatefulWidget {
  final int applicationId;
  final String studentName;
  final VoidCallback onCompleted;
  final bool isReassessment;
  final bool isRenewal;

  const PhysicalExaminationDialog({
    super.key,
    required this.applicationId,
    required this.studentName,
    required this.onCompleted,
    this.isReassessment = false,
    this.isRenewal = false,
  });

  @override
  State<PhysicalExaminationDialog> createState() =>
      _PhysicalExaminationDialogState();
}

class _PhysicalExaminationDialogState extends State<PhysicalExaminationDialog> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  // Text Controllers
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _heightController = TextEditingController();
  final TextEditingController _bloodPressureController = TextEditingController();
  final TextEditingController _heartRateController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  final TextEditingController _physicianNameController = TextEditingController();
  final TextEditingController _licenseNumberController = TextEditingController();

  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  // BMI Calculation
  double? _bmi;
  String _bmiCategory = '';

  // Physical Examination Findings
  final Map<String, bool> _examFindings = {
    'balance': true,
    'musculoskeletal': true,
    'lungs': true,
    'heart': true,
    'extremities': true,
    'hearing': true,
    'vision': true,
  };

  bool _isDrawMode = true;
  Uint8List? _uploadedImageBytes;
  String? _uploadedFileName;
  bool _isSubmitting = false;
  DateTime _examinationDate = DateTime.now();
  bool _hasAbnormalities() {
  return _examFindings.values.contains(false);
}
  
  // Previous examination data for comparison
  Map<String, dynamic>? _previousExam;

  @override
  void initState() {
    super.initState();

    _signatureController.addListener(() {
      setState(() {
      });
    });

    _weightController.addListener(_calculateBMI);
    _heightController.addListener(_calculateBMI);
    
    if (widget.isReassessment) {
      _loadPreviousExamination();
    }
  }

  Future<void> _loadPreviousExamination() async {
    try {
      final response = await supabase
          .from('physical_examinations')
          .select('*')
          .eq(widget.isRenewal ? 'renewal_application_id' : 'application_id', widget.applicationId)
          .order('examination_date', ascending: false)
          .limit(1)
          .maybeSingle();
      
      if (response != null) {
        setState(() {
          _previousExam = response;
        });
      }
    } catch (e) {
      debugPrint('Error loading previous exam: $e');
    }
  }

  @override
  void dispose() {
    _weightController.dispose();
    _heightController.dispose();
    _bloodPressureController.dispose();
    _heartRateController.dispose();
    _remarksController.dispose();
    _physicianNameController.dispose();
    _licenseNumberController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  void _calculateBMI() {
    final weight = double.tryParse(_weightController.text);
    final height = double.tryParse(_heightController.text);

    if (weight != null && height != null && height > 0) {
      setState(() {
        _bmi = weight / ((height / 100) * (height / 100));

        if (_bmi! < 18.5) {
          _bmiCategory = 'Underweight';
        } else if (_bmi! >= 18.5 && _bmi! < 25.0) {
          _bmiCategory = 'Healthy Weight';
        } else if (_bmi! >= 25.0 && _bmi! < 30.0) {
          _bmiCategory = 'Overweight';
        } else {
          _bmiCategory = 'Obesity';
        }
      });
    } else {
      setState(() {
        _bmi = null;
        _bmiCategory = '';
      });
    }
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _examinationDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null && picked != _examinationDate) {
      setState(() => _examinationDate = picked);
    }
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result != null && result.files.isNotEmpty) {
      final bytes = result.files.first.bytes;
      final fileName = result.files.first.name;
      if (bytes != null) {
        setState(() {
          _uploadedImageBytes = bytes;
          _uploadedFileName = fileName;
        });
      }
    }
  }

  Future<String?> _uploadSignature(Uint8List bytes, String fileName) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final path = 'physician_signatures/${widget.applicationId}_${timestamp}_$fileName';

      await supabase.storage.from('signatures').uploadBinary(path, bytes);

      final publicUrl = supabase.storage.from('signatures').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  Future<void> _submitExamination(bool isPassed) async {
  // 1️⃣ Validate form
  if (!_formKey.currentState!.validate()) return;

  // 2️⃣ Check signature
  if (_isDrawMode && _signatureController.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please draw your signature'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  if (!_isDrawMode && _uploadedImageBytes == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please upload a signature'),
        backgroundColor: Colors.orange,
      ),
    );
    return;
  }

  setState(() => _isSubmitting = true);

  try {
    // 3️⃣ Prepare signature bytes
    Uint8List sigBytes;
    String fileName;
    if (_isDrawMode) {
      sigBytes = await _signatureController.toPngBytes() ?? Uint8List(0);
      if (sigBytes.isEmpty) throw Exception('Signature generation failed');
      fileName = 'drawn_signature.png';
    } else {
      sigBytes = _uploadedImageBytes!;
      fileName = _uploadedFileName ?? 'uploaded_signature.png';
    }

    // 4️⃣ Upload signature to Supabase Storage
    final signatureUrl = await _uploadSignature(sigBytes, fileName);
    if (signatureUrl == null) throw Exception('Failed to upload signature');

    // 5️⃣ Determine status updates
    final borrowingStatus = isPassed
        ? (widget.isRenewal ? 'renewal_health' : 'fit_to_use')
        : (widget.isRenewal ? 'renewal_health_rejected' : 'rejected_health');
    final appointmentStatus = isPassed ? 'completed' : 'cancelled';

    // 6️⃣ Insert physical examination
    await supabase.from('physical_examinations').insert({
      'application_id': (widget.isRenewal || widget.isReassessment) ? null : widget.applicationId,
      'renewal_application_id': (widget.isRenewal || widget.isReassessment) ? widget.applicationId : null,
      'weight': double.parse(_weightController.text),
      'height': double.parse(_heightController.text),
      'bmi': _bmi,
      'bmi_category': _bmiCategory,
      'blood_pressure': _bloodPressureController.text.trim(),
      'heart_rate': _heartRateController.text.trim(),
      'balance': _examFindings['balance'],
      'musculoskeletal': _examFindings['musculoskeletal'],
      'lungs': _examFindings['lungs'],
      'heart': _examFindings['heart'],
      'extremities': _examFindings['extremities'],
      'hearing': _examFindings['hearing'],
      'vision': _examFindings['vision'],
      'remarks': _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
      'physician_name': _physicianNameController.text.trim(),
      'physician_license_number': _licenseNumberController.text.trim(),
      'physician_signature_url': signatureUrl,
      'examination_date': _examinationDate.toIso8601String(),
      'created_by': supabase.auth.currentUser?.id,
      'is_reassessment': widget.isReassessment,
    });

    // 7️⃣ Update borrowing/renewal applications
    if (widget.isRenewal) {
      await supabase.from('renewal_applications').update({
        'status': borrowingStatus,
        'health_approval_date': DateTime.now().toIso8601String(),
        'health_signatory_name': _physicianNameController.text.trim(),
        'health_signature_url': signatureUrl,
        'health_remarks': _remarksController.text.trim().isEmpty ? null : _remarksController.text.trim(),
      }).eq('id', widget.applicationId);
    } else {
      Map<String, dynamic> updates = {'status': borrowingStatus};
      if (widget.isReassessment) {
        updates['reassessment_requested'] = false;
        updates['reassessment_approved'] = null;
        updates['reassessment_request_date'] = null;
      }
      await supabase.from('borrowing_applications_version2').update(updates).eq('id', widget.applicationId);
    }

    // 8️⃣ Update medical appointments
    await supabase
        .from('medical_appointments')
        .update({'status': appointmentStatus})
        .eq('application_id', widget.applicationId);

    // 9️⃣ Show success SnackBar & close dialog
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.isReassessment
                ? 'Re-assessment completed! Status: ${isPassed ? 'PASSED' : 'FAILED'}'
                : isPassed
                    ? 'Physical examination recorded successfully! Student PASSED.'
                    : 'Physical examination recorded. Student FAILED.',
          ),
          backgroundColor: isPassed ? Colors.green : Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      widget.onCompleted();
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
      );
    }
  } finally {
    setState(() => _isSubmitting = false);
  }
}

  Widget _buildPreviousExamComparison() {
    if (_previousExam == null) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.purple[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: Colors.purple[700], size: 20),
              const SizedBox(width: 8),
              Text(
                'Previous Examination',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple[700],
                ),
              ),
              const Spacer(),
              Text(
                DateFormat('MMM dd, yyyy').format(
                  DateTime.parse(_previousExam!['examination_date']),
                ),
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
            ],
          ),
          const Divider(height: 20),
          
          Row(
            children: [
              Expanded(
                child: _buildComparisonItem(
                  'BMI',
                  '${_previousExam!['bmi']?.toStringAsFixed(1) ?? 'N/A'}',
                  _previousExam!['bmi_category'] ?? 'N/A',
                ),
              ),
              Expanded(
                child: _buildComparisonItem(
                  'Weight',
                  '${_previousExam!['weight']} kg',
                  '',
                ),
              ),
              Expanded(
                child: _buildComparisonItem(
                  'Height',
                  '${_previousExam!['height']} cm',
                  '',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          Row(
            children: [
              Expanded(
                child: _buildComparisonItem(
                  'Blood Pressure',
                  _previousExam!['blood_pressure'] ?? 'N/A',
                  '',
                ),
              ),
              Expanded(
                child: _buildComparisonItem(
                  'Heart Rate',
                  '${_previousExam!['heart_rate'] ?? 'N/A'} bpm',
                  '',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonItem(String label, String value, String? subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
        if (subtitle != null && subtitle.isNotEmpty)
          Text(
            subtitle,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 700,
        constraints: const BoxConstraints(maxHeight: 800),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isReassessment
                            ? 'Physical Re-assessment Form'
                            : 'Physical Examination & Diagnostic Form',
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Student: ${widget.studentName}',
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.isReassessment) _buildPreviousExamComparison(),

                      _buildSectionTitle('Body Mass Index (BMI)'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _weightController,
                              decoration: const InputDecoration(
                                labelText: 'Weight (kg) *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.monitor_weight),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) return 'Required';
                                if (double.tryParse(value) == null) return 'Invalid number';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _heightController,
                              decoration: const InputDecoration(
                                labelText: 'Height (cm) *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.height),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) return 'Required';
                                if (double.tryParse(value) == null) return 'Invalid number';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      if (_bmi != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue[200]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.analytics, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  const Text('BMI Result:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  const SizedBox(width: 8),
                                  Text(
                                    _bmi!.toStringAsFixed(1),
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.blue),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Text('Category:', style: TextStyle(fontSize: 14)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getBMIColor(),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _bmiCategory,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      _buildSectionTitle('Vital Signs'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _bloodPressureController,
                              decoration: const InputDecoration(
                                labelText: 'Blood Pressure *',
                                hintText: 'e.g., 120/80',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.favorite),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) return 'Required';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _heartRateController,
                              decoration: const InputDecoration(
                                labelText: 'Heart Rate (bpm) *',
                                hintText: 'e.g., 72',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.monitor_heart),
                              ),
                              keyboardType: TextInputType.number,
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) return 'Required';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      _buildSectionTitle('Physical Examination Findings'),
                      const SizedBox(height: 8),
                      const Text('Check if finding is NORMAL', style: TextStyle(fontSize: 12, color: Colors.grey)),

                      if (_hasAbnormalities())
                        Container(
                          margin: const EdgeInsets.only(top: 8, bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            border: Border.all(color: Colors.orange),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.warning_amber_rounded, color: Colors.orange),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Abnormal findings detected. Student cannot PASS. Choose FAIL instead.',
                                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),

                      const SizedBox(height: 12),
                      const SizedBox(height: 12),
                      _buildCheckboxTile('Balance', 'balance'),
                      _buildCheckboxTile('Musculo-Skeletal', 'musculoskeletal'),
                      _buildCheckboxTile('Lungs', 'lungs'),
                      _buildCheckboxTile('Heart', 'heart'),
                      _buildCheckboxTile('Extremities', 'extremities'),
                      _buildCheckboxTile('Hearing', 'hearing'),
                      _buildCheckboxTile('Vision', 'vision'),

                      const SizedBox(height: 24),

                      _buildSectionTitle('Remarks'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _remarksController,
                        decoration: const InputDecoration(
                          hintText: 'Additional notes or observations',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 3,
                      ),

                      const SizedBox(height: 24),
                      const Divider(thickness: 2),
                      const SizedBox(height: 16),

                      _buildSectionTitle('Attending Physician'),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _physicianNameController,
                        decoration: const InputDecoration(
                          labelText: 'Physician Name *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Please enter physician name';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _licenseNumberController,
                        decoration: const InputDecoration(
                          labelText: 'License Number *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) return 'Please enter license number';
                          return null;
                        },
                      ),

                      const SizedBox(height: 16),

                      const Text('Date of Examination *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: _selectDate,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[400]!),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 20),
                              const SizedBox(width: 12),
                              Text(DateFormat('MMMM dd, yyyy').format(_examinationDate), style: const TextStyle(fontSize: 14)),
                              const Spacer(),
                              Icon(Icons.edit, size: 16, color: Colors.grey[600]),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      const Text('Physician Signature *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 150,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey[400]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: _isDrawMode
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Signature(
                                        controller: _signatureController,
                                        backgroundColor: Colors.white,
                                      ),
                                    )
                                  : _uploadedImageBytes == null
                                      ? Center(
                                          child: ElevatedButton.icon(
                                            onPressed: _pickImage,
                                            icon: const Icon(Icons.upload_file, size: 20),
                                            label: const Text('Upload Signature'),
                                          ),
                                        )
                                      : ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.memory(_uploadedImageBytes!, fit: BoxFit.contain),
                                        ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: 'Clear',
                                onPressed: () {
                                  _signatureController.clear();
                                  setState(() {
                                    _uploadedImageBytes = null;
                                  });
                                },
                              ),
                              IconButton(
                                icon: Icon(_isDrawMode ? Icons.upload_file : Icons.edit),
                                tooltip: _isDrawMode ? 'Upload' : 'Draw',
                                onPressed: () {
                                  setState(() {
                                    _isDrawMode = !_isDrawMode;
                                    _uploadedImageBytes = null;
                                  });
                                },
                              )
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : () => _submitExamination(false),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                            )
                          : const Icon(Icons.cancel),
                      label: const Text('FAIL', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_isSubmitting || _hasAbnormalities())
                          ? null
                          : () => _submitExamination(true),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                            )
                          : const Icon(Icons.check_circle),
                      label: const Text('PASS', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold));
  }

  Widget _buildCheckboxTile(String label, String key) {
    final isNormal = _examFindings[key] ?? false;

    return CheckboxListTile(
      title: Text(
        label,
        style: TextStyle(
          color: isNormal ? Colors.black : Colors.red,
          fontWeight: isNormal ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      value: _examFindings[key],
      onChanged: (bool? value) {
        setState(() {
          _examFindings[key] = value ?? false;
        });
      },
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
    );
  }

  Color _getBMIColor() {
    if (_bmi == null) return Colors.grey;
    if (_bmi! < 18.5) return Colors.orange;
    if (_bmi! < 25.0) return Colors.green;
    if (_bmi! < 30.0) return Colors.orange;
    return Colors.red;
  }
}