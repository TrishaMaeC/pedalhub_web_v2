import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pedalhub_admin/widgets/app_header.dart';
import 'package:pedalhub_admin/widgets/sdo_drawer.dart';
import 'package:pedalhub_admin/widgets/short_term_signature_approval_dialog.dart';

class ForApprovalPage extends StatefulWidget {
  const ForApprovalPage({super.key});

  @override
  State<ForApprovalPage> createState() => _ForApprovalPageState();
}

class _ForApprovalPageState extends State<ForApprovalPage> {
  final supabase = Supabase.instance.client;
  bool isLoading = true;
  String selectedStatus = 'pending';
  List<Map<String, dynamic>> requests = [];

  @override
  void initState() {
    super.initState();
    fetchRequests();
  }

  // ================= FETCH SHORT-TERM BORROWING REQUESTS =================
  Future<void> fetchRequests() async {
    setState(() => isLoading = true);
    try {
      final List response = await supabase
          .from('short_term_borrowing_requests')
          .select('*')
          .eq('status', selectedStatus)
          .order('created_at', ascending: false);

      requests = List<Map<String, dynamic>>.from(response);
      debugPrint('Fetched ${requests.length} requests with status: $selectedStatus');
    } catch (e) {
      debugPrint('FETCH ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading requests: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    setState(() => isLoading = false);
  }

  // ================= DECLINE REQUEST =================
  Future<void> declineRequest(int id, String rejectionReason) async {
    try {
      await supabase.from('short_term_borrowing_requests').update({
        'status': 'rejected',
        'reviewed_at': DateTime.now().toIso8601String(),
        'reviewed_by': supabase.auth.currentUser?.id,
        'rejection_reason': rejectionReason,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', id);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request declined'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      
      fetchRequests();
    } catch (e) {
      debugPrint('DECLINE ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error declining request: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ================= HELPER: GET STATUS TEXT =================
  String getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Pending Approval';
      case 'approved':
        return 'Approved - Ready to Borrow';
      case 'rejected':
        return 'Rejected';
      default:
        return status;
    }
  }

  // ================= HELPER: GET STATUS COLOR =================
  Color getStatusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'rejected':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // ================= HELPER: CALCULATE TENURE =================
  String calculateTenure(String? startDateStr) {
    if (startDateStr == null) return 'N/A';
    try {
      final startDate = DateTime.parse(startDateStr);
      final now = DateTime.now();
      final difference = now.difference(startDate);
      final years = (difference.inDays / 365).floor();
      final months = ((difference.inDays % 365) / 30).floor();
      
      if (years > 0) {
        return '$years year${years > 1 ? 's' : ''}, $months month${months > 1 ? 's' : ''}';
      } else {
        return '$months month${months > 1 ? 's' : ''}';
      }
    } catch (e) {
      return 'N/A';
    }
  }

  // ================= SHOW SIGNATURE DIALOG FOR APPROVAL =================
  void _showSignatureDialog(Map<String, dynamic> request) {
    final userName = request['full_name'] ?? 'User #${request['user_id']}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ShortTermSignatureApprovalDialog(
        requestId: request['id'],
        userName: userName,
        onApproved: fetchRequests,
      ),
    );
  }

  // ================= SHOW DECLINE CONFIRMATION =================
  void _showDeclineConfirmation(Map<String, dynamic> request) {
    final userName = request['full_name'] ?? 'User #${request['user_id']}';
    final reasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Decline Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to decline the borrowing request from $userName?',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason for rejection (optional)',
                border: OutlineInputBorder(),
                hintText: 'Enter reason...',
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              declineRequest(request['id'], reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Decline'),
          ),
        ],
      ),
    );
  }

  // ================= VIEW DETAILS DIALOG =================
  void showRequestDetails(Map<String, dynamic> request) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: 800,
          constraints: const BoxConstraints(maxHeight: 700),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Request Details',
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
              
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Request Type Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.access_time, size: 14, color: Colors.orange[700]),
                            const SizedBox(width: 4),
                            Text(
                              'Short-term Borrowing Request',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.orange[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Profile Picture
                      if (request['profile_pic_url'] != null && request['profile_pic_url'].toString().isNotEmpty) ...[
                        Center(
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.grey[300]!, width: 2),
                            ),
                            child: ClipOval(
                              child: Image.network(
                                request['profile_pic_url'],
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Icon(Icons.person, size: 50, color: Colors.grey[400]);
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      
                      // User Information Section
                      _buildSectionHeader('User Information'),
                      _buildDetailRow('Full Name', request['full_name'] ?? 'N/A'),
                      _buildDetailRow('User Type', request['user_type']?.toUpperCase() ?? 'N/A'),
                      
                      if (request['user_type'] == 'student') ...[
                        _buildDetailRow('SR Code', request['sr_code'] ?? 'N/A'),
                      ] else if (request['user_type'] == 'staff') ...[
                        _buildDetailRow('Employee No.', request['employee_no'] ?? 'N/A'),
                        _buildDetailRow('Field of Work', request['field_of_work'] ?? 'N/A'),
                        if (request['start_date'] != null) ...[
                          _buildDetailRow('Start Date', request['start_date'].toString().split('T')[0]),
                          _buildDetailRow('Tenure', calculateTenure(request['start_date'])),
                        ],
                      ],
                      
                      _buildDetailRow('Phone Number', request['phone_number'] ?? 'N/A'),
                      
                      if (request['birthday'] != null)
                        _buildDetailRow('Birthday', request['birthday'].toString().split('T')[0]),
                      
                      if (request['sex'] != null)
                        _buildDetailRow('Sex', request['sex']),
                      
                      if (request['location_address'] != null && request['location_address'].toString().isNotEmpty)
                        _buildDetailRow('Address', request['location_address']),
                      
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      
                      // Request Information Section
                      _buildSectionHeader('Request Information'),
                      _buildDetailRow('Request ID', '#${request['id']}'),
                      _buildDetailRow('Status', getStatusText(request['status'])),
                      _buildDetailRow('Destination Name', request['destination_name'] ?? 'N/A'),
                      _buildDetailRow('Destination Address', request['destination_address'] ?? 'N/A'),
                      
                      if (request['destination_lat'] != null && request['destination_lng'] != null) ...[
                        _buildDetailRow('Coordinates', 
                          '${request['destination_lat']?.toStringAsFixed(6)}, ${request['destination_lng']?.toStringAsFixed(6)}'),
                      ],
                      
                      _buildDetailRow('Duration', '${request['selected_duration_minutes']} minutes'),
                      
                      if (request['borrowing_description'] != null && request['borrowing_description'].toString().isNotEmpty)
                        _buildDetailRow('Purpose/Description', request['borrowing_description']),
                      
                      _buildDetailRow('Created At', request['created_at'].toString().split('.')[0]),
                      
                      if (request['reviewed_at'] != null) ...[
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                        _buildDetailRow('Reviewed At', request['reviewed_at'].toString().split('.')[0]),
                      ],
                      
                      if (request['rejection_reason'] != null && request['rejection_reason'].toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        _buildDetailRow('Rejection Reason', request['rejection_reason']),
                      ],
                      
                      if (request['signature_url'] != null && request['signature_url'].toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),
                        const Text(
                          'Signature:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              request['signature_url'],
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Center(
                                  child: Text('Failed to load signature'),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.blue[800],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  // ================= STATUS BUTTON =================
  Widget statusButton(String value, String label, Color color) {
    final isSelected = selectedStatus == value;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: isSelected ? color : Colors.grey[400],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          elevation: isSelected ? 4 : 1,
        ),
        onPressed: () {
          setState(() => selectedStatus = value);
          fetchRequests();
        },
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  // ================= REQUEST CARD =================
  Widget requestCard(Map<String, dynamic> request) {
    final fullName = request['full_name'] ?? 'Unknown User';
    final userType = request['user_type'] ?? '';
    final identifier = userType == 'student' 
        ? (request['sr_code'] ?? 'N/A')
        : (request['employee_no'] ?? 'N/A');
    final status = request['status'] as String;
    
    // Get initials from full name
    String getInitials(String name) {
      final parts = name.trim().split(' ');
      if (parts.length >= 2) {
        return parts[0][0] + parts[parts.length - 1][0];
      } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
        return parts[0][0];
      }
      return 'U';
    }

    // Check if new staff (less than 1 year)
    bool isNewStaff = false;
    if (userType == 'staff' && request['start_date'] != null) {
      try {
        final startDate = DateTime.parse(request['start_date']);
        final now = DateTime.now();
        final difference = now.difference(startDate);
        isNewStaff = (difference.inDays / 365) < 1;
      } catch (e) {
        // ignore
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar with profile pic or initials
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: getStatusColor(status).withOpacity(0.2),
                border: Border.all(
                  color: getStatusColor(status),
                  width: 2,
                ),
              ),
              child: request['profile_pic_url'] != null && request['profile_pic_url'].toString().isNotEmpty
                  ? ClipOval(
                      child: Image.network(
                        request['profile_pic_url'],
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Center(
                            child: Text(
                              getInitials(fullName),
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: getStatusColor(status),
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  : Center(
                      child: Text(
                        getInitials(fullName),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: getStatusColor(status),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 16),

            // INFO
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          fullName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isNewStaff) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'NEW STAFF',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: userType == 'student' ? Colors.blue[100] : Colors.green[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          userType.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: userType == 'student' ? Colors.blue[900] : Colors.green[900],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${userType == 'student' ? 'SR' : 'Emp'}: $identifier',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Request ID: #${request['id']}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          request['destination_name'] ?? 'N/A',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.timer, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${request['selected_duration_minutes']} minutes',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Request Type Badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Short-term',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ACTIONS
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (selectedStatus == 'pending') ...[
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _showSignatureDialog(request),
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: const Text('Approve'),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _showDeclineConfirmation(request),
                    icon: const Icon(Icons.cancel, size: 18),
                    label: const Text('Decline'),
                  ),
                ],
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => showRequestDetails(request),
                  icon: const Icon(Icons.visibility, size: 18),
                  label: const Text('View Details'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================= UI =================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      drawer: const SDODrawer(),
      body: Column(
        children: [
          // Header with Menu Button
          Stack(
            children: [
              const AppHeader(),
              Positioned(
                top: 16,
                left: 16,
                child: Builder(
                  builder: (context) => IconButton(
                    icon: const Icon(Icons.menu),
                    color: Colors.red,
                    iconSize: 30,
                    onPressed: () {
                      Scaffold.of(context).openDrawer();
                    },
                  ),
                ),
              ),
            ],
          ),

          // Page Title with Type Indicator
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'For Approval',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          'Short-term Borrowing Requests → Signature Required',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: fetchRequests,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),

          // STATUS TABS
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                statusButton('pending', 'Pending', Colors.orange),
                statusButton('approved', 'Approved', Colors.green),
                statusButton('rejected', 'Declined', Colors.red),
              ],
            ),
          ),

          // CONTENT
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : requests.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.inbox_outlined,
                              size: 80,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No $selectedStatus short-term requests',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: requests.length,
                        itemBuilder: (context, index) {
                          return requestCard(requests[index]);
                        },
                      ),
          ),
        ],
      ),
    );
  }
}