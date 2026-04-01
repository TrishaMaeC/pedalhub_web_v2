import 'package:flutter/material.dart';

/// Reusable dialog for declining applications with a required reason
class RejectionReasonDialog extends StatefulWidget {
  final String applicantName;
  final Future<void> Function(String reason) onReject;

  const RejectionReasonDialog({
    super.key,
    required this.applicantName,
    required this.onReject,
  });

  @override
  State<RejectionReasonDialog> createState() => _RejectionReasonDialogState();

  /// Helper method to show the dialog
  static Future<void> show({
    required BuildContext context,
    required String applicantName,
    required Future<void> Function(String reason) onReject,
  }) {
    return showDialog(
      context: context,
      builder: (context) => RejectionReasonDialog(
        applicantName: applicantName,
        onReject: onReject,
      ),
    );
  }
}

class _RejectionReasonDialogState extends State<RejectionReasonDialog> {
  final TextEditingController _reasonController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _handleReject() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      await widget.onReject(_reasonController.text.trim());

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.warning, color: Colors.red[700]),
          const SizedBox(width: 8),
          const Text('Decline Application'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Are you sure you want to decline the application of ${widget.applicantName}?',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Text(
                    'Reason for Rejection',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(width: 4),
                  Text('*',
                      style: TextStyle(
                          color: Colors.red[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ],
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _reasonController,
                enabled: !_isSubmitting,
                decoration: InputDecoration(
                  hintText: 'Provide a detailed reason (min. 10 characters)',
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.all(12),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                maxLines: 4,
                maxLength: 500,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please provide a reason for rejection';
                  }
                  if (value.trim().length < 10) {
                    return 'Provide a more detailed reason (at least 10 characters)';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This reason will be visible to the applicant.',
                        style: TextStyle(fontSize: 12, color: Colors.blue[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          onPressed: _isSubmitting ? null : _handleReject,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey[400],
          ),
          icon: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(Icons.cancel, size: 18),
          label: Text(_isSubmitting ? 'Declining...' : 'Decline Application'),
        ),
      ],
    );
  }
}
