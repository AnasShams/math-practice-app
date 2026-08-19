
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final supabaseServiceProvider = Provider((ref) => SupabaseService());

class SupabaseService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // -- Curriculum Fetching --

  Future<List<Map<String, dynamic>>> getGrades() async {
    final response = await _supabase
        .from('grades')
        .select('*')
        .order('id');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<List<Map<String, dynamic>>> getUnitsForGrade(int gradeId) async {
    final response = await _supabase
        .from('units')
        .select('*, chapters(*, topics(*))')
        .eq('grade_id', gradeId)
        .order('order_no', ascending: true);
    
    return List<Map<String, dynamic>>.from(response);
  }

  // Fetch questions for a specific chapter
  Future<List<Map<String, dynamic>>> getQuestionsForChapter(String chapterId) async {
    final response = await _supabase
        .from('questions')
        .select('*')
        .eq('chapter_id', chapterId)
        .order('id');
    return List<Map<String, dynamic>>.from(response);
  }
  
  // Fetch questions for a specific topic (if filtered by topic)
  Future<List<Map<String, dynamic>>> getQuestionsForTopic(String topicId) async {
     final response = await _supabase
        .from('questions')
        .select('*')
        .eq('topic_id', topicId)
        .order('id');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<Map<String, dynamic>> getQuestionById(int id) async {
      final response = await _supabase
          .from('questions')
          .select()
          .eq('id', id)
          .single();
      return response;
  }
  Future<void> saveUserProgress({
    required int questionId,
    required bool isCorrect,
    int score = 0,
    String? solutionSubmitted,
    int? hintsUsed,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      debugPrint('Error: User not logged in. Cannot save progress.');
      throw 'User not logged in'; 
    }

    try {
      await _supabase.from('user_progress').insert({
        'user_id': userId,
        'question_id': questionId,
        'is_correct': isCorrect,
        'score': score,
        'solution_submitted': solutionSubmitted,
        'hints_used': hintsUsed ?? 0,
        'attempted_at': DateTime.now().toIso8601String(),
      });
      debugPrint('Progress saved successfully for user: $userId');
    } catch (e) {
      debugPrint('Error saving progress: $e');
      rethrow; 
    }
  }
}
