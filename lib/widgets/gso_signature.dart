import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signature/signature.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart';

class GsoReleaseSignatureDialog extends StatefulWidget {
  final int applicationId;
  final String applicantName;
  final VoidCallback onReleased;

  const GsoReleaseSignatureDialog({
    super.key,
    required this.applicationId,
    required this.applicantName,
    required this.onReleased,
  });

  @override
  State<GsoReleaseSignatureDialog> createState() => _GsoReleaseSignatureDialogState();
}

class _GsoReleaseSignatureDialogState extends State<GsoReleaseSignatureDialog> {
  final supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();
  
  // Text Controllers
  final TextEditingController _gsoOfficerNameController = TextEditingController();
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
  DateTime _releaseDate = DateTime.now();

  // Bike assignment variables
  List<Map<String, dynamic>> _availableBikes = [];
  int? _selectedBikeId;
  String? _selectedBikeNumber;
  bool _loadingBikes = true;

  @override
  void initState() {
    super.initState();
    _loadUserName();
    _loadAvailableBikes();
    _signatureController.addListener(() {
      if (_signatureController.isNotEmpty) {
        setState(() => _hasSignature = true);
      }
    });
  }

  @override
  void dispose() {
    _gsoOfficerNameController.dispose();
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
          // Extract name from email or use email
          final email = response['email'] as String;
          _gsoOfficerNameController.text = email.split('@')[0].replaceAll('.', ' ').toUpperCase();
        }
      }
    } catch (e) {
      debugPrint('Error loading user name: $e');
    }
  }

  // ================= LOAD AVAILABLE LONG-TERM BIKES =================
  Future<void> _loadAvailableBikes() async {
  setState(() => _loadingBikes = true);

  try {
    final response = await supabase
        .from('bikes')
        .select('id, bike_number, campus')
        .eq('status', 'available') // make sure this matches your DB exactly
        .order('bike_number');

    if (mounted) {
      _availableBikes = response != null
          ? List<Map<String, dynamic>>.from(response)
          : [];

      _loadingBikes = false;

      if (_availableBikes.length == 1) {
        _selectedBikeId = _availableBikes.first['id'];
        _selectedBikeNumber = _availableBikes.first['bike_number'];
      }

      setState(() {}); // trigger UI update
    }
  } catch (e) {
    debugPrint('Error loading bikes: $e');
    if (mounted) setState(() => _loadingBikes = false);
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
      final filePath = 'gso_signatures/${userId}_${timestamp}_$fileName';

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
      initialDate: _releaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (picked != null && picked != _releaseDate) {
      setState(() => _releaseDate = picked);
    }
  }

  // ================= CONFIRM RELEASE WITH SIGNATURE =================
  Future<void> _confirmRelease() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

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
        if (signature == null) {
          throw Exception('Failed to generate signature image');
        }
        signatureBytes = signature;
        fileName = 'drawn_signature.png';
      } else {
        signatureBytes = _uploadedImageBytes;
        fileName = _uploadedFileName ?? 'uploaded_signature.png';
      }

      if (signatureBytes == null) {
        throw Exception('No signature data available');
      }

      final signatureUrl = await _uploadSignatureToStorage(signatureBytes, fileName);

      if (signatureUrl == null) {
        throw Exception('Failed to upload signature');
      }

      // Get user_id from the application
      final appResponse = await supabase
          .from('borrowing_applications')
          .select('user_id')
          .eq('id', widget.applicationId)
          .single();

      final userId = appResponse['user_id'];

      // Update bike status and assignment
      if (_selectedBikeId != null) {
        await supabase
            .from('bikes')
            .update({
              'status': 'in_use',
              'current_user_id': userId,
            })
            .eq('id', _selectedBikeId!);
      }

      // Update application with release information
      await supabase
          .from('borrowing_applications')
          .update({
            'status': 'approved',
            'released_at': _releaseDate.toIso8601String(),
            'released_by': supabase.auth.currentUser?.id,
            'gso_officer_name': _gsoOfficerNameController.text.trim(),
            'gso_signature_url': signatureUrl,
            'gso_release_remarks': _remarksController.text.trim().isEmpty 
                ? null 
                : _remarksController.text.trim(),
            'assigned_bike_id': _selectedBikeId,
            'assigned_bike_number': _selectedBikeNumber,
          })
          .eq('id', widget.applicationId);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Supply marked as released successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onReleased();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error confirming release: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
                    'Confirm Supply Release',
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
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2, color: Colors.green),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Releasing bicycle supplies to:',
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
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Release Details Section
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // GSO Officer Name
                      const Text(
                        'GSO Officer Name *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _gsoOfficerNameController,
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
                            return 'Please enter GSO officer name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Release Date
                      const Text(
                        'Release Date *',
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
                                DateFormat('MMMM dd, yyyy').format(_releaseDate),
                                style: const TextStyle(fontSize: 14),
                              ),
                              const Spacer(),
                              Icon(Icons.edit, size: 16, color: Colors.grey[600]),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Assign Bike
                      const Text(
                        'Assign Bike *',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _loadingBikes
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16.0),
                                child: CircularProgressIndicator(),
                              ),
                            )
                          : _availableBikes.isEmpty
                              ? Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.orange[50],
                                    border: Border.all(color: Colors.orange[300]!),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.warning_amber, color: Colors.orange[700]),
                                      const SizedBox(width: 12),
                                      const Expanded(
                                        child: Text(
                                          'No available long-term bikes to assign',
                                          style: TextStyle(fontSize: 14),
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : DropdownButtonFormField<int>(
                                value: _selectedBikeId,
                                decoration: const InputDecoration(
                                  hintText: 'Select a bike to assign',
                                  prefixIcon: Icon(Icons.pedal_bike),
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                ),
                                items: _availableBikes.map((bike) {
                                  return DropdownMenuItem<int>(
                                    value: bike['id'],
                                    child: Row(
                                      children: [
                                        Text(
                                          'Bike #${bike['bike_number']}',
                                          style: const TextStyle(fontWeight: FontWeight.w500),
                                        ),
                                        if (bike['campus'] != null) ...[
                                          const SizedBox(width: 8),
                                          Text(
                                            '• Campus: ${bike['campus']}',
                                            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                          ),
                                        ],
                                      ],
                                    ),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedBikeId = value;
                                    _selectedBikeNumber = _availableBikes
                                        .firstWhere((bike) => bike['id'] == value)['bike_number'];
                                  });
                                },
                                validator: (value) {
                                  if (value == null) return 'Please select a bike to assign';
                                  return null;
                                },
                              ),
                          
                        const SizedBox(height: 16),

                      // Remarks (Optional)
                      const Text(
                        'Release Notes (Optional)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: _remarksController,
                        decoration: const InputDecoration(
                          hintText: 'Add any notes about the release (e.g., items included, condition, etc.)',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.all(12),
                        ),
                        maxLines: 3,
                        maxLength: 500,
                      ),
                      const SizedBox(height: 24),

                      // Signature Section
                      const Text(
                        'GSO Officer Signature *',
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
                    onPressed: _isLoading || !_hasSignature ? null : _confirmRelease,
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
                    label: Text(_isLoading ? 'Processing...' : 'Confirm Release'),
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