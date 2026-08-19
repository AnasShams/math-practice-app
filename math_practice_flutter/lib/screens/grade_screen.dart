
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../core/constants.dart';

class GradeScreen extends ConsumerStatefulWidget {
  final int gradeId;
  const GradeScreen({super.key, required this.gradeId});

  @override
  ConsumerState<GradeScreen> createState() => _GradeScreenState();
}

class _GradeScreenState extends ConsumerState<GradeScreen> {
  List<Map<String, dynamic>> _units = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchUnits();
  }

  Future<void> _fetchUnits() async {
    try {
      final units = await ref.read(supabaseServiceProvider).getUnitsForGrade(widget.gradeId);
      if (units.isNotEmpty) {
        debugPrint('First unit name: ${units.first['name']}');
        final firstChapter = (units.first['chapters'] as List).firstOrNull;
        if (firstChapter != null) {
           debugPrint('First chapter name: ${firstChapter['name']}');
           debugPrint('First chapter topics: ${firstChapter['topics']}');
        }
      }
      if (mounted) setState(() => _units = units);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load curriculum: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Grade ${widget.gradeId} Curriculum')),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : _units.isEmpty
              ? const Center(child: Text("No units found for this grade."))
              : ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: _units.length,
              itemBuilder: (context, index) {
                final unit = _units[index];
                final chapters = unit['chapters'] as List<dynamic>? ?? [];
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 20),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: AppColors.border),
                  ),
                  child: Theme(
                    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      title: Text(
                        "Unit ${unit['order_no']}", 
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14)
                      ),
                      subtitle: Text(
                        unit['name'] ?? 'Untitled Unit', 
                        style: AppTextStyles.heading2.copyWith(fontSize: 18)
                      ),
                      children: chapters.map<Widget>((chapter) {
                        return Container(
                          decoration: BoxDecoration(
                            border: Border(top: BorderSide(color: AppColors.border)),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                            title: Text(chapter['name'] ?? 'Untitled Chapter', style: const TextStyle(fontWeight: FontWeight.w500)),
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.book_outlined, size: 20, color: AppColors.textSecondary),
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textSecondary),
                            onTap: () {
                               final topics = chapter['topics'] as List<dynamic>? ?? [];
                               if (topics.isNotEmpty) {
                                  _showTopicSelection(context, chapter, topics);
                               } else {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No topics found for this chapter")));
                               }
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _showTopicSelection(BuildContext context, Map<String, dynamic> chapter, List<dynamic> topics) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text("Select Topic in ${chapter['name']}", style: AppTextStyles.heading2),
                ),
                ...topics.map((topic) => ListTile(
                  title: Text(topic['name'] ?? 'Untitled Topic'),
                  onTap: () {
                    context.pop(); // close sheet
                    context.push('/practice/${chapter['id']}/${topic['id']}');
                  },
                  trailing: const Icon(Icons.arrow_forward, size: 16, color: AppColors.primary),
                )),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
