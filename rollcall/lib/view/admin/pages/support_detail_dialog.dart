import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/utils/theme/colors/app_colors.dart';

class SupportDetailDialog extends StatefulWidget {
  final Map<String, dynamic> request;
  const SupportDetailDialog({super.key, required this.request});

  @override
  State<SupportDetailDialog> createState() => _SupportDetailDialogState();
}

class _SupportDetailDialogState extends State<SupportDetailDialog> {
  final _replyController = TextEditingController();
  bool _isSending = false;
  bool _isReplied = false;

  //ADMİN MAİLi
  final String adminEmail = "ce.ayseaktas@gmail.com";

  @override
  void initState() {
    super.initState();
    _isReplied = widget.request['status'] == 'replied';
    if (_isReplied) {
      _replyController.text = widget.request['admin_reply'] ?? '';
    }
  }

  Future<void> _sendReply() async {
    final reply = _replyController.text.trim();
    if (reply.isEmpty) return;

    setState(() => _isSending = true);

    try {
      // 1. Update Supabase
      await Supabase.instance.client
          .from('support_requests')
          .update({'status': 'replied', 'admin_reply': reply})
          .eq('id', widget.request['id']);

      // 2. Launch Email (Türkçe karakter desteği için encode edildi)
      final String subject = 'RollCall Destek Talebi Hakkında';
      final String bodyText =
          'Sayın ${widget.request['full_name']},\n\n'
          'Gönderdiğiniz destek talebi için cevabımız aşağıdadır:\n\n'
          '$reply\n\n'
          'İyi günler dileriz.\n'
          'RollCall Yönetimi ($adminEmail)';

      final Uri emailLaunchUri = Uri(
        scheme: 'mailto',
        path: widget.request['email'],
        query:
            'subject=${Uri.encodeFull(subject)}&body=${Uri.encodeFull(bodyText)}',
      );

      try {
        if (await canLaunchUrl(emailLaunchUri)) {
          await launchUrl(emailLaunchUri, mode: LaunchMode.externalApplication);
        } else {
          await launchUrl(emailLaunchUri);
        }
      } catch (e) {
        debugPrint('Mail açma hatası: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'E-posta uygulaması açılamadı. Lütfen cihazınızda bir e-posta istemcisi olduğundan emin olun.',
              ),
            ),
          );
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Talep Detayı',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 12),
            _buildInfoRow('Gönderen:', widget.request['full_name'] ?? ''),
            _buildInfoRow('E-posta:', widget.request['email'] ?? ''),
            const SizedBox(height: 16),
            const Text(
              'Sorun:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(12),
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.request['issue'] ?? '',
                style: const TextStyle(fontSize: 14),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Cevabınız:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _replyController,
              maxLines: 4,
              enabled: !_isReplied,
              decoration: InputDecoration(
                hintText: _isReplied ? '' : 'Buraya cevabınızı yazın...',
                filled: true,
                fillColor: _isReplied ? Colors.grey[100] : Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _isReplied ? Colors.transparent : AppColors.border,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (!_isReplied)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _isSending ? null : _sendReply,
                  icon: const Icon(Icons.send_rounded, color: Colors.white),
                  label: Text(
                    _isSending ? 'Gönderiliyor...' : 'CEVAPLA VE E-POSTA AÇ',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, color: AppColors.success),
                    SizedBox(width: 8),
                    Text(
                      'Bu talep cevaplanmıştır.',
                      style: TextStyle(
                        color: AppColors.success,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
