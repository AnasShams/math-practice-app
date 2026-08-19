
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../core/constants.dart';

class PracticeScreen extends ConsumerStatefulWidget {
  final String chapterId;
  final String topicId;
  const PracticeScreen({super.key, required this.chapterId, required this.topicId});

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> {
  List<Map<String, dynamic>> _questions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
  }

  Future<void> _fetchQuestions() async {
    try {
      final questions = await ref.read(supabaseServiceProvider).getQuestionsForTopic(widget.topicId);
      if (mounted) setState(() => _questions = questions);
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Practice Problems')),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: _questions.length,
            itemBuilder: (context, index) {
              final q = _questions[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: AppColors.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                       Row(
                         children: [
                           Container(
                             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                             decoration: BoxDecoration(
                               color: AppColors.secondary.withOpacity(0.1),
                               borderRadius: BorderRadius.circular(8),
                             ),
                             child: Text(
                               "Problem ${index + 1}", 
                               style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.secondary, fontSize: 12),
                             ),
                           ),
                           const Spacer(),
                           const Icon(Icons.access_time, size: 16, color: AppColors.textSecondary),
                           const SizedBox(width: 4),
                           const Text("5 min", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                         ],
                       ),
                       const SizedBox(height: 16),
                       Text(
                         q['question'] ?? 'No question text', 
                         style: AppTextStyles.heading2.copyWith(fontSize: 18, height: 1.5),
                       ),
                       const SizedBox(height: 24),
                       SizedBox(
                         width: double.infinity,
                         child: ElevatedButton(
                           onPressed: () => context.push('/solve/${q['id']}'),
                           style: ElevatedButton.styleFrom(
                             backgroundColor: Colors.white,
                             foregroundColor: AppColors.primary,
                             side: BorderSide(color: AppColors.primary),
                             elevation: 0,
                           ),
                           child: const Text('Solve Now'),
                         ),
                       ),
                    ],
                  ),
                ),
              );
            },
          ),
    );
  }
}
