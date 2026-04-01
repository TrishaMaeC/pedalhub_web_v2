import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:signature/signature.dart';
import 'package:file_picker/file_picker.dart';

class ShortTermSignatureApprovalDialog extends StatefulWidget {
  final int requestId;
  final String userName;
  final VoidCallback onApproved;

  const ShortTermSignatureApprovalDialog({
    super.key,
    required this.requestId,
    required this.userName,
    required this.onApproved,
  });

  @override
  State<ShortTermSignatureApprovalDialog> createState() => _ShortTermSignatureApprovalDialogState();
}

class _ShortTermSignatureApprovalDialogState extends State<ShortTermSignatureApprovalDialog> {
  final supabase = Supabase.instance.client;
  
  // Signature Controller for drawing
  final SignatureController _signatureController = SignatureController(
    penStrokeWidth: 3,
    penColor: Colors.black,
    exportBackgroundColor: Colors.white,
  );

  // State variables
  bool _isDrawMode = true; // true = draw, false = upload
  bool _isLoading = false;
  Uint8List? _uploadedImageBytes;
  String? _uploadedFileName;
  bool _hasSignature = false;

  @override
  void initState() {
    super.initState();
    _signatureController.addListener(() {
      if (_signatureController.isNotEmpty) {
        setState(() => _hasSignature = true);
      }
    });
  }

  @override
  void dispose() {
    _signatureController.dispose();
    super.dispose();
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
      final filePath = 'short_term_signatures/${userId}_${timestamp}_$fileName';

      // Upload to Supabase Storage
      await supabase.storage
          .from('signatures')
          .uploadBinary(filePath, bytes);

      // Get public URL
      final publicUrl = supabase.storage
          .from('signatures')
          .getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      debugPrint('Upload error: $e');
      return null;
    }
  }

  // ================= APPROVE REQUEST WITH SIGNATURE =================
  Future<void> _approveRequest() async {
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

      // Get signature bytes based on mode
      if (_isDrawMode) {
        // Convert drawn signature to PNG
        final signature = await _signatureController.toPngBytes();
        if (signature == null) {
          throw Exception('Failed to generate signature image');
        }
        signatureBytes = signature;
        fileName = 'drawn_signature.png';
      } else {
        // Use uploaded image
        signatureBytes = _uploadedImageBytes;
        fileName = _uploadedFileName ?? 'uploaded_signature.png';
      }

      if (signatureBytes == null) {
        throw Exception('No signature data available');
      }

      // Upload signature to storage
      final signatureUrl = await _uploadSignatureToStorage(signatureBytes, fileName);

      if (signatureUrl == null) {
        throw Exception('Failed to upload signature');
      }

      // Update short_term_borrowing_requests with signature and status
      await supabase.from('short_term_borrowing_requests').update({
        'status': 'approved',
        'signature_url': signatureUrl,
        'reviewed_at': DateTime.now().toIso8601String(),
        'reviewed_by': supabase.auth.currentUser?.id,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.requestId);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request approved successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onApproved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving request: $e'),
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
        width: 700,
        constraints: const BoxConstraints(maxHeight: 700),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Approve Request',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _isLoading ? null : () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 16),

            // User Info
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
                        'Approving request for:',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      Text(
                        widget.userName,
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

            // Mode Toggle
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () {
                      setState(() {
                        _isDrawMode = true;
                        _uploadedImageBytes = null;
                        _uploadedFileName = null;
                        _hasSignature = _signatureController.isNotEmpty;
                      });
                    },
                    icon: const Icon(Icons.draw),
                    label: const Text('Draw Signature'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isDrawMode ? Colors.blue : Colors.grey[300],
                      foregroundColor: _isDrawMode ? Colors.white : Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : () {
                      setState(() {
                        _isDrawMode = false;
                        _hasSignature = _uploadedImageBytes != null;
                      });
                    },
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Upload Signature'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !_isDrawMode ? Colors.blue : Colors.grey[300],
                      foregroundColor: !_isDrawMode ? Colors.white : Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Signature Area
            Expanded(
              child: _isDrawMode ? _buildDrawSignatureArea() : _buildUploadSignatureArea(),
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
                  onPressed: _isLoading || !_hasSignature ? null : _approveRequest,
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
                  label: Text(_isLoading ? 'Approving...' : 'Approve Request'),
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
    );
  }

  // ================= DRAW SIGNATURE AREA =================
  Widget _buildDrawSignatureArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Draw your signature below:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
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
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: _isLoading ? null : () {
                _signatureController.clear();
                setState(() => _hasSignature = false);
              },
              icon: const Icon(Icons.clear),
              label: const Text('Clear'),
            ),
          ],
        ),
      ],
    );
  }

  // ================= UPLOAD SIGNATURE AREA =================
  Widget _buildUploadSignatureArea() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Upload your signature image:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
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
                        Icon(Icons.cloud_upload, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _pickImage,
                          icon: const Icon(Icons.upload_file),
                          label: const Text('Choose Image'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Supports: JPG, PNG, GIF',
                          style: TextStyle(
                            fontSize: 12,
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
                        top: 8,
                        right: 8,
                        child: IconButton(
                          onPressed: _isLoading ? null : () {
                            setState(() {
                              _uploadedImageBytes = null;
                              _uploadedFileName = null;
                              _hasSignature = false;
                            });
                          },
                          icon: const Icon(Icons.close),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.red,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
        if (_uploadedFileName != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'File: $_uploadedFileName',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
      ],
    );
  }
}