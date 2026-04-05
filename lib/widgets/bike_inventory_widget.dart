import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BikeInventoryWidget extends StatefulWidget {
  final String campus;

  const BikeInventoryWidget({
    super.key,
    required this.campus,
  });

  @override
  State<BikeInventoryWidget> createState() => BikeInventoryWidgetState();
}

class BikeInventoryWidgetState extends State<BikeInventoryWidget>
    with SingleTickerProviderStateMixin {
  final supabase = Supabase.instance.client;

  bool isLoading = true;

  int totalAvailableBikes = 0;
  int totalBikesInUse = 0;
  int totalMaintenance = 0;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _fetchInventory();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(BikeInventoryWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.campus != widget.campus) {
      _fetchInventory();
    }
  }

  Future<void> _fetchInventory() async {
    setState(() => isLoading = true);
    _animController.reset();

    try {
      final availableBikes = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'available')
          .ilike('campus', widget.campus);

      final bikesInUse = await supabase
          .from('bikes')
          .select('id')
          .eq('status', 'in_use')
          .ilike('campus', widget.campus);

      final maintenance = await supabase
          .from('bikes')
          .select('id')
          .inFilter('status', ['maintenance', 'for_maintenance']).ilike(
              'campus', widget.campus);

      if (mounted) {
        setState(() {
          totalAvailableBikes = (availableBikes as List).length;
          totalBikesInUse = (bikesInUse as List).length;
          totalMaintenance = (maintenance as List).length;
          isLoading = false;
        });
        _animController.forward();
      }
    } catch (e) {
      debugPrint('BIKE INVENTORY ERROR: $e');
      if (mounted) {
        setState(() => isLoading = false);
        _animController.forward();
      }
    }
  }

  /// Public method so parent pages can trigger a refresh.
  Future<void> refresh() => _fetchInventory();

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        height: 120,
        child: Center(
          child: CircularProgressIndicator(
            valueColor:
                AlwaysStoppedAnimation<Color>(Color(0xFFD32F2F)),
          ),
        ),
      );
    }

    return FadeTransition(
      opacity: _fadeAnim,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ───────────────────────────────────────
          _SectionHeader(
            label: 'Bike Inventory',
            icon: Icons.pedal_bike_rounded,
            color: const Color(0xFF00695C),
          ),
          const SizedBox(height: 12),

          // ── Stat tiles + fleet overview ──────────────────────────
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  label: 'Available',
                  value: totalAvailableBikes,
                  description: 'Bikes ready to be assigned',
                  icon: Icons.pedal_bike_rounded,
                  color: const Color(0xFF00897B),
                  highlight: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'In Use',
                  value: totalBikesInUse,
                  description: 'Currently borrowed by students',
                  icon: Icons.directions_bike_rounded,
                  color: const Color(0xFF5E35B1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _StatTile(
                  label: 'Under Maintenance',
                  value: totalMaintenance,
                  description:
                      'Being repaired or flagged for maintenance',
                  icon: Icons.build_outlined,
                  color: const Color(0xFFBF360C),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SummaryTile(
                  available: totalAvailableBikes,
                  inUse: totalBikesInUse,
                  maintenance: totalMaintenance,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section Header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _SectionHeader({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
            color: color,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            height: 1,
            color: color.withOpacity(0.15),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat Tile
// ─────────────────────────────────────────────────────────────────────────────

class _StatTile extends StatelessWidget {
  final String label;
  final int value;
  final String description;
  final IconData icon;
  final Color color;
  final bool highlight;

  const _StatTile({
    required this.label,
    required this.value,
    required this.description,
    required this.icon,
    required this.color,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: highlight ? color.withOpacity(0.06) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color:
              highlight ? color.withOpacity(0.4) : Colors.grey.shade200,
          width: highlight ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                  color: color,
                  height: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey[850],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            description,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
              height: 1.4,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary Tile — fleet utilisation overview
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryTile extends StatelessWidget {
  final int available;
  final int inUse;
  final int maintenance;

  const _SummaryTile({
    required this.available,
    required this.inUse,
    required this.maintenance,
  });

  @override
  Widget build(BuildContext context) {
    final total = available + inUse + maintenance;
    final availableRatio = total == 0 ? 0.0 : available / total;
    final inUseRatio = total == 0 ? 0.0 : inUse / total;
    final maintenanceRatio = total == 0 ? 0.0 : maintenance / total;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fleet Overview',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.grey[850],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$total bikes total',
            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
          ),
          const SizedBox(height: 14),

          // Stacked bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (availableRatio > 0)
                    Expanded(
                      flex: (availableRatio * 100).round(),
                      child:
                          Container(color: const Color(0xFF00897B)),
                    ),
                  if (inUseRatio > 0)
                    Expanded(
                      flex: (inUseRatio * 100).round(),
                      child:
                          Container(color: const Color(0xFF5E35B1)),
                    ),
                  if (maintenanceRatio > 0)
                    Expanded(
                      flex: (maintenanceRatio * 100).round(),
                      child:
                          Container(color: const Color(0xFFBF360C)),
                    ),
                  if (total == 0)
                    Expanded(
                        child: Container(
                            color: Colors.grey.shade300)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Legend
          _LegendRow(
              color: const Color(0xFF00897B),
              label: 'Available',
              count: available),
          const SizedBox(height: 6),
          _LegendRow(
              color: const Color(0xFF5E35B1),
              label: 'In Use',
              count: inUse),
          const SizedBox(height: 6),
          _LegendRow(
              color: const Color(0xFFBF360C),
              label: 'Maintenance',
              count: maintenance),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final Color color;
  final String label;
  final int count;

  const _LegendRow({
    required this.color,
    required this.label,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.grey[800],
          ),
        ),
      ],
    );
  }
}