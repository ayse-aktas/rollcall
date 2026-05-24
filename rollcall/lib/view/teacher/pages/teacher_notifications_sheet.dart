import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/utils/theme/colors/app_colors.dart';

class TeacherNotificationsSheet extends StatefulWidget {
  const TeacherNotificationsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const TeacherNotificationsSheet(),
    );
  }

  @override
  State<TeacherNotificationsSheet> createState() => _TeacherNotificationsSheetState();
}

class _TeacherNotificationsSheetState extends State<TeacherNotificationsSheet> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _notifications = [];

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final uid = _supabase.auth.currentUser?.id;
      final res = await _supabase
          .from('notifications')
          .select('*')
          .eq('user_id', uid!)
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(res);
          _isLoading = false;
        });
      }

      // Mark as read
      await _supabase.from('notifications').update({'is_read': true}).eq('user_id', uid);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteAll() async {
    try {
      final uid = _supabase.auth.currentUser?.id;
      await _supabase.from('notifications').delete().eq('user_id', uid!);
      _loadNotifications();
    } catch (e) {
      debugPrint('Silme hatası: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            
            // Header
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Bildirimler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  if (_notifications.isNotEmpty)
                    TextButton.icon(
                      onPressed: _deleteAll,
                      icon: const Icon(Icons.delete_sweep_rounded, size: 18, color: Colors.redAccent),
                      label: const Text('Tümünü Sil', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),

            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _notifications.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          controller: controller,
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                          itemCount: _notifications.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 12),
                          itemBuilder: (context, index) => _NotificationCard(notification: _notifications[index]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('Bildiriminiz bulunmuyor', style: TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final Map<String, dynamic> notification;
  const _NotificationCard({required this.notification});

  @override
  Widget build(BuildContext context) {
    final title = notification['title'] ?? 'Bildirim';
    final message = notification['message'] ?? '';
    final createdAt = DateTime.parse(notification['created_at']);
    final type = notification['type'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _getColor(type).withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(_getIcon(type), color: _getColor(type), size: 18),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(DateFormat('HH:mm').format(createdAt), style: const TextStyle(color: Colors.grey, fontSize: 10)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(message, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getIcon(String? type) {
    if (type == 'course_assignment') return Icons.assignment_ind_rounded;
    if (type == 'course_revocation') return Icons.assignment_return_rounded;
    return Icons.notifications_active_rounded;
  }

  Color _getColor(String? type) {
    if (type == 'course_assignment') return Colors.blue;
    if (type == 'course_revocation') return Colors.orange;
    return AppColors.primary;
  }
}
