import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signature/signature.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

class SignatureApprovalDialog extends StatefulWidget {
  final int applicationId;
  final String applicantName;
  final String approvalType; // REQUIRED: 'sdo' or 'chancellor'
  final VoidCallback onApproved;
  final String? targetStatus;
  final String table; // Optional: defaults to 'for_ranking' for SDO

  const SignatureApprovalDialog({
    super.key,
    required this.applicationId,
    required this.applicantName,
    required this.approvalType, // now required
    required this.onApproved,
    this.targetStatus,
    required this.table,
  });

  @override
  State<SignatureApprovalDialog> createState() => _SignatureApprovalDialogState();
}

class _SignatureApprovalDialogState extends State<SignatureApprovalDialog> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  
  // Text Controllers
  final TextEditingController _signatoryNameController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();
  
  // Signature Controller for drawing
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  // State variables
  bool _isDrawMode = true;
  bool _isLoading = false;
  Uint8List? _uploadedImageBytes;
  String? _uploadedFileName;
  bool _hasSignature = false;
  DateTime _approvalDate = DateTime.now();

  // Use required approvalType
  String get _approvalType => widget.approvalType;

  // Get target status (defaults to 'for_ranking' for SDO)
  String get _targetStatus => widget.targetStatus ?? 'for_ranking';

  @override
  void initState() {
    super.initState();

    // Sanity check
    assert(
      ['sdo', 'chancellor'].contains(_approvalType),
      'Invalid approvalType: $_approvalType',
    );

    _loadUserName();
    _signatureController.addListener(() {
      if (_signatureController.isNotEmpty) {
        setState(() => _hasSignature = true);
      }
    });
  }

  @override
  void dispose() {
    _signatoryNameController.dispose();
    _remarksController.dispose();
    _signatureController.dispose();
    super.dispose();
  }

  // ================= LOAD CURRENT USER NAME =================
  Future<void> _loadUserName() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final response = await supabase
            .from('profiles')
            .select('email')
            .eq('id', userId)
            .maybeSingle();
        
        if (response != null && mounted) {
          final email = response['email'] as String;
          _signatoryNameController.text = email.split('@')[0].replaceAll('.', ' ').toUpperCase();
        }
      }
    } catch (e) {
      debugPrint('Error loading user name: $e');
    }
  }

  // ================= PICK IMAGE FILE =================
  Future<void> _pickImage() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
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
            _hasSignature = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error picking image: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ================= UPLOAD SIGNATURE TO SUPABASE STORAGE =================
  Future<String?> _uploadSignatureToStorage(Uint8List bytes, String fileName) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final userId = supabase.auth.currentUser?.id ?? 'unknown';
      final folderName = _approvalType == 'chancellor' ? 'chancellor_signatures' : 'sdo_signatures';
      final filePath = '$folderName/${userId}_${timestamp}_$fileName';

      await supabase.storage
          .from('signatures')
          .uploadBinary(filePath, bytes);

      final publicUrl = supabase.storage
          .from('signatures')
          .getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  // ================= SELECT DATE =================
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _approvalDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (picked != null && picked != _approvalDate) {
      setState(() => _approvalDate = picked);
    }
  }

  // ================= APPROVE WITH SIGNATURE =================
  Future<void> _approveApplication() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_hasSignature) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide a signature first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      Uint8List? signatureBytes;
      String fileName;

      if (_isDrawMode) {
        final signature = await _signatureController.toPngBytes();
        if (signature == null) throw Exception('Failed to generate signature image');
        signatureBytes = signature;
        fileName = 'drawn_signature.png';
      } else {
        signatureBytes = _uploadedImageBytes;
        fileName = _uploadedFileName ?? 'uploaded_signature.png';
      }

      if (signatureBytes == null) throw Exception('No signature data available');

      final signatureUrl = await _uploadSignatureToStorage(signatureBytes, fileName);
      if (signatureUrl == null) throw Exception('Failed to upload signature');

      Map<String, dynamic> updateData = {
      'status': _targetStatus,
      if (widget.table == 'borrowing_applications') ...{
        'reviewed_at': DateTime.now().toIso8601String(),
        'reviewed_by': supabase.auth.currentUser?.id,
      },
    };

      if (_approvalType == 'chancellor') {
        updateData.addAll({
          'chancellor_signature_url': signatureUrl,
          'chancellor_signatory_name': _signatoryNameController.text.trim(),
          'chancellor_approval_date': _approvalDate.toIso8601String(),
          'chancellor_remarks': _remarksController.text.trim().isEmpty 
              ? null 
              : _remarksController.text.trim(),
        });
      } else {
        updateData.addAll({
          'sdo_signature_url': signatureUrl,
          'sdo_signatory_name': _signatoryNameController.text.trim(),
          'sdo_approval_date': _approvalDate.toIso8601String(),
          'sdo_remarks': _remarksController.text.trim().isEmpty 
              ? null 
              : _remarksController.text.trim(),
        });
      }

      await supabase
        .from(widget.table)
        .update(updateData)
        .eq('id', widget.applicationId);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Application approved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onApproved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving application: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 750,
        constraints: const BoxConstraints(maxHeight: 800),
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Approve Application',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 16),

              // Applicant Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.person, color: Colors.blue),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Approving application for:',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          widget.applicantName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Approval Details Section
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Signatory Name
                      const Text(
                        'Signatory Name *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _signatoryNameController,
                        decoration: const InputDecoration(
                          hintText: 'Enter your full name',
                          prefixIcon: Icon(Icons.badge),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter signatory name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Approval Date
                      const Text(
                        'Approval Date *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                              Text(
                                DateFormat('MMMM dd, yyyy').format(_approvalDate),
                                style: const TextStyle(fontSize: 14),
                              ),
                              const Spacer(),
                              Icon(Icons.edit, size: 16, color: Colors.grey[600]),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Remarks (Optional)
                      const Text(
                        'Remarks (Optional)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _remarksController,
                        decoration: const InputDecoration(
                          hintText: 'Add any additional remarks or notes',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.all(12),
                        ),
                        maxLines: 3,
                        maxLength: 500,
                      ),
                      const SizedBox(height: 24),

                      // Signature Section
                      const Text(
                        'Digital Signature *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Mode Toggle
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _isDrawMode = true;
                                  _uploadedImageBytes = null;
                                  _uploadedFileName = null;
                                  _hasSignature = _signatureController.isNotEmpty;
                                });
                              },
                              icon: const Icon(Icons.draw),
                              label: const Text('Draw'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isDrawMode ? Colors.blue : Colors.grey[300],
                                foregroundColor: _isDrawMode ? Colors.white : Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _isDrawMode = false;
                                  _hasSignature = _uploadedImageBytes != null;
                                });
                              },
                              icon: const Icon(Icons.upload_file),
                              label: const Text('Upload'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: !_isDrawMode ? Colors.blue : Colors.grey[300],
                                foregroundColor: !_isDrawMode ? Colors.white : Colors.black,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Signature Area
                      SizedBox(
                        height: 200,
                        child: _isDrawMode 
                            ? _buildDrawSignatureArea() 
                            : _buildUploadSignatureArea(),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _isLoading || !_hasSignature ? null : _approveApplication,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.check_circle),
                    label: Text(_isLoading ? 'Approving...' : 'Approve Application'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
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

  // ================= DRAW SIGNATURE AREA =================
  Widget _buildDrawSignatureArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[400]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.white,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Signature(
                controller: _signatureController,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              _signatureController.clear();
              setState(() => _hasSignature = false);
            },
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('Clear'),
          ),
        ),
      ],
    );
  }

  // ================= UPLOAD SIGNATURE AREA =================
  Widget _buildUploadSignatureArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[400]!),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[50],
            ),
            child: _uploadedImageBytes == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_upload, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.upload_file, size: 16),
                          label: const Text('Choose Image'),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'JPG, PNG, GIF',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : Stack(
                    children: [
                      Center(
                        child: Image.memory(
                          _uploadedImageBytes!,
                          fit: BoxFit.contain,
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton(
                          onPressed: () {
                            setState(() {
                              _uploadedImageBytes = null;
                              _uploadedFileName = null;
                              _hasSignature = false;
                            });
                          },
                          icon: const Icon(Icons.close, size: 16),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(4),
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
