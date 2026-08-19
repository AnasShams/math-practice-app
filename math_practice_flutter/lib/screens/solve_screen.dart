
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../services/supabase_service.dart';
import '../core/constants.dart';

import 'package:signature/signature.dart';
import 'dart:typed_data';

class SolveScreen extends ConsumerStatefulWidget {
  final String problemId;
  const SolveScreen({super.key, required this.problemId});

  @override
  ConsumerState<SolveScreen> createState() => _SolveScreenState();
}

class _SolveScreenState extends ConsumerState<SolveScreen> {
  Map<String, dynamic>? _question;
  bool _isLoading = true;
  bool _isAnalyzing = false;
  bool _isHandwritingMode = true;
  bool _isEraserMode = false;

  // Per-step controllers: TWO layers per step (draw + erase)
  List<TextEditingController> _stepTextControllers = [];
  List<SignatureController> _stepDrawControllers = [];   // Black pen layer
  List<SignatureController> _stepEraserControllers = [];  // White pen layer (on top)
  List<GlobalKey> _stepRepaintKeys = [];  // For capturing combined image
  List<Uint8List?> _stepBackgroundImages = [];  // Flattened backgrounds
  int _activeStepIndex = 0;

  // Per-step feedback
  List<Map<String, dynamic>> _stepFeedback = [];

  @override
  void initState() {
    super.initState();
    _addStep();
    _fetchQuestion();
  }

  @override
  void dispose() {
    for (final c in _stepTextControllers) { c.dispose(); }
    for (final c in _stepDrawControllers) { c.dispose(); }
    for (final c in _stepEraserControllers) { c.dispose(); }
    super.dispose();
  }

  /// Ensure all per-step lists are in sync (handles hot-reload state mismatch)
  void _syncLists() {
    final targetLen = _stepTextControllers.length;
    // If text controllers exist but other lists are short, fill them up
    while (_stepDrawControllers.length < targetLen) {
      _stepDrawControllers.add(SignatureController(
        penStrokeWidth: 3,
        penColor: AppColors.textPrimary,
        exportBackgroundColor: Colors.white,
      ));
    }
    while (_stepEraserControllers.length < targetLen) {
      _stepEraserControllers.add(SignatureController(
        penStrokeWidth: 10,
        penColor: Colors.white,
        exportBackgroundColor: Colors.transparent,
      ));
    }
    while (_stepRepaintKeys.length < targetLen) {
      _stepRepaintKeys.add(GlobalKey());
    }
    while (_stepBackgroundImages.length < targetLen) {
      _stepBackgroundImages.add(null);
    }
    while (_stepFeedback.length < targetLen) {
      _stepFeedback.add({});
    }
    if (_stepTextControllers.isEmpty) {
      _addStep();
    }
  }

  void _addStep() {
    setState(() {
      _stepTextControllers.add(TextEditingController());
      _stepDrawControllers.add(SignatureController(
        penStrokeWidth: 3,
        penColor: AppColors.textPrimary,
        exportBackgroundColor: Colors.white,
      ));
      _stepEraserControllers.add(SignatureController(
        penStrokeWidth: 10,
        penColor: Colors.white,
        exportBackgroundColor: Colors.transparent,
      ));
      _stepRepaintKeys.add(GlobalKey());
      _stepBackgroundImages.add(null);
      _stepFeedback.add({});
      _activeStepIndex = _stepTextControllers.length - 1;
    });
  }

  void _removeStep(int index) {
    if (_stepTextControllers.length <= 1) return;
    setState(() {
      _stepTextControllers[index].dispose();
      _stepDrawControllers[index].dispose();
      _stepEraserControllers[index].dispose();
      _stepTextControllers.removeAt(index);
      _stepDrawControllers.removeAt(index);
      _stepEraserControllers.removeAt(index);
      _stepRepaintKeys.removeAt(index);
      _stepBackgroundImages.removeAt(index);
      _stepFeedback.removeAt(index);
      if (_activeStepIndex >= _stepTextControllers.length) {
        _activeStepIndex = _stepTextControllers.length - 1;
      }
    });
  }

  void _toggleEraserMode() async {
    if (_isEraserMode) {
      // Switching FROM eraser TO draw: flatten layers into background image
      for (int i = 0; i < _stepDrawControllers.length; i++) {
        if (!_stepDrawControllers[i].isEmpty || !_stepEraserControllers[i].isEmpty || _stepBackgroundImages[i] != null) {
          final captured = await _captureStepImage(i);
          if (captured != null) {
            _stepBackgroundImages[i] = captured;
          }
          // Clear both layers so new drawing is on top of flattened image
          _stepDrawControllers[i].clear();
          _stepEraserControllers[i].clear();
        }
      }
    }
    setState(() {
      _isEraserMode = !_isEraserMode;
    });
  }

  /// Capture the combined draw+erase layers as a PNG image
  Future<Uint8List?> _captureStepImage(int index) async {
    try {
      final boundary = _stepRepaintKeys[index].currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error capturing step $index: $e');
      return null;
    }
  }

  Future<void> _fetchQuestion() async {
    try {
      final q = await ref.read(supabaseServiceProvider).getQuestionById(int.parse(widget.problemId));
      if (mounted) setState(() => _question = q);
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkAnswer() async {
    // Validate: at least one step has content
    bool hasContent = false;
    for (int i = 0; i < _stepTextControllers.length; i++) {
      if (_isHandwritingMode && !_stepDrawControllers[i].isEmpty) { hasContent = true; break; }
      if (!_isHandwritingMode && _stepTextControllers[i].text.trim().isNotEmpty) { hasContent = true; break; }
    }
    if (!hasContent) return;

    setState(() {
      _isAnalyzing = true;
      _stepFeedback = List.generate(_stepTextControllers.length, (_) => {});
    });

    try {
      final backendUrl = dotenv.env['GRADING_API_URL'];
      if (backendUrl == null) throw 'Backend URL not configured';

      final questionText = _question?['question'] ?? 'Unknown question';

      if (_isHandwritingMode) {
        // Hybrid Approach: Send images to backend for OCR + grading
        List<Map<String, dynamic>> steps = [];

        for (int i = 0; i < _stepDrawControllers.length; i++) {
          if (_stepDrawControllers[i].isEmpty) {
            steps.add({
              'stepNumber': i + 1,
              'imageBase64': ''
            });
          } else {
            final Uint8List? imageBytes = await _captureStepImage(i);
            if (imageBytes == null) continue;
            
            final base64Image = base64Encode(imageBytes);
            final imageUrl = 'data:image/png;base64,$base64Image';
            
            steps.add({
              'stepNumber': i + 1,
              'imageBase64': imageUrl
            });
          }
        }

        // Send to backend
        final response = await http.post(
          Uri.parse('$backendUrl/grade'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'questionId': int.tryParse(widget.problemId) ?? 0,
            'questionText': questionText,
            'steps': steps
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data['success'] == true && data['steps'] != null) {
            final List gradingSteps = data['steps'];
            setState(() {
              for (int i = 0; i < gradingSteps.length && i < _stepFeedback.length; i++) {
                _stepFeedback[i] = Map<String, dynamic>.from(gradingSteps[i]);
              }
            });
          } else {
            throw 'Backend returned error: ${data['error'] ?? 'Unknown error'}';
          }
        } else {
          throw 'Failed to grade: ${response.statusCode} - ${response.body}';
        }
      } else {
        // Text mode: Send directly to backend
        List<Map<String, dynamic>> steps = [];
        for (int i = 0; i < _stepTextControllers.length; i++) {
          steps.add({
            'stepNumber': i + 1,
            'text': _stepTextControllers[i].text
          });
        }

        final response = await http.post(
          Uri.parse('$backendUrl/grade'),
          headers: {
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'questionId': int.tryParse(widget.problemId) ?? 0,
            'questionText': questionText,
            'steps': steps
          }),
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          
          if (data['success'] == true && data['steps'] != null) {
            final List gradingSteps = data['steps'];
            setState(() {
              for (int i = 0; i < gradingSteps.length && i < _stepFeedback.length; i++) {
                _stepFeedback[i] = Map<String, dynamic>.from(gradingSteps[i]);
              }
            });
          } else {
            throw 'Backend returned error: ${data['error'] ?? 'Unknown error'}';
          }
        } else {
          throw 'Failed to grade: ${response.statusCode} - ${response.body}';
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      debugPrint('Grading error: $e');
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  Future<void> _submitGrade() async {
    // If no feedback generated yet, run check first
    bool hasFeedback = _stepFeedback.any((f) => f.isNotEmpty);
    if (!hasFeedback) {
      await _checkAnswer();
      hasFeedback = _stepFeedback.any((f) => f.isNotEmpty);
      if (!hasFeedback) return;
    }

    final isCorrect = _stepFeedback.every((f) => f['correct'] == true);
    final score = isCorrect ? 10 : 0;

    // Collect all step text for storage
    String fullSolution = "";
    for (int i = 0; i < _stepTextControllers.length; i++) {
      if (_isHandwritingMode) {
        fullSolution += "Step ${i + 1}: [Handwriting Image]\n";
      } else {
        fullSolution += "Step ${i + 1}: ${_stepTextControllers[i].text}\n";
      }
    }

    try {
      await ref.read(supabaseServiceProvider).saveUserProgress(
        questionId: int.parse(widget.problemId),
        isCorrect: isCorrect,
        score: score,
        solutionSubmitted: fullSolution,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Progress Saved!')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to save progress: $e')));
    }
  }

  void _insertText(String text) {
    if (_isHandwritingMode) return;
    final controller = _stepTextControllers[_activeStepIndex];
    final textSelection = controller.selection;
    final newText = controller.text.replaceRange(
      textSelection.start >= 0 ? textSelection.start : controller.text.length,
      textSelection.end >= 0 ? textSelection.end : controller.text.length,
      text,
    );
    final myTextLength = text.length;
    controller.text = newText;
    controller.selection = textSelection.copyWith(
      baseOffset: (textSelection.start >= 0 ? textSelection.start : newText.length) + myTextLength,
      extentOffset: (textSelection.start >= 0 ? textSelection.start : newText.length) + myTextLength,
    );
  }

  void _backspace() {
    if (_isHandwritingMode) return;
    final controller = _stepTextControllers[_activeStepIndex];
    final textSelection = controller.selection;
    final text = controller.text;
    if (textSelection.start < 0) {
      if (text.isNotEmpty) {
        controller.text = text.substring(0, text.length - 1);
        controller.selection = TextSelection.fromPosition(TextPosition(offset: controller.text.length));
      }
      return;
    }
    if (textSelection.start == textSelection.end) {
      if (textSelection.start > 0) {
        final newText = text.replaceRange(textSelection.start - 1, textSelection.start, '');
        controller.text = newText;
        controller.selection = TextSelection.fromPosition(TextPosition(offset: textSelection.start - 1));
      }
    } else {
      final newText = text.replaceRange(textSelection.start, textSelection.end, '');
      controller.text = newText;
      controller.selection = TextSelection.fromPosition(TextPosition(offset: textSelection.start));
    }
  }

  Widget _buildStepCard(int index) {
    final isActive = _activeStepIndex == index;
    final feedback = _stepFeedback[index];
    final hasFeedback = feedback.isNotEmpty;

    return GestureDetector(
      onTap: () => setState(() => _activeStepIndex = index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive ? AppColors.primary : AppColors.border,
            width: isActive ? 2 : 1,
          ),
          boxShadow: [
            if (isActive)
              BoxShadow(color: AppColors.primary.withOpacity(0.1), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Step Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary.withOpacity(0.06) : const Color(0xFFF8FAFC),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
              ),
              child: Row(
                children: [
                  Icon(Icons.drag_indicator, size: 16, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Text(
                    "Step ${index + 1}",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isActive ? AppColors.primary : AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  if (hasFeedback)
                    Icon(
                      feedback['correct'] == true ? Icons.check_circle : Icons.cancel,
                      size: 18,
                      color: feedback['correct'] == true ? Colors.green : Colors.red,
                    ),
                  if (_stepTextControllers.length > 1)
                    IconButton(
                      icon: Icon(Icons.close, size: 16, color: Colors.grey.shade500),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _removeStep(index),
                      tooltip: 'Remove Step',
                    ),
                ],
              ),
            ),

            // Input Area
            SizedBox(
              height: 150,
              child: _isHandwritingMode
                  ? RepaintBoundary(
                      key: _stepRepaintKeys[index],
                      child: Stack(
                        children: [
                          // Background: Flattened image from previous draw+erase
                          if (_stepBackgroundImages[index] != null)
                            Image.memory(
                              _stepBackgroundImages[index]!,
                              height: 150,
                              width: double.infinity,
                              fit: BoxFit.fill,
                            )
                          else
                            Container(height: 150, color: Colors.white),
                          // Draw layer (black pen, transparent bg so background shows through)
                          IgnorePointer(
                            ignoring: _isEraserMode,
                            child: Signature(
                              controller: _stepDrawControllers[index],
                              backgroundColor: Colors.transparent,
                              height: 150,
                              width: double.infinity,
                            ),
                          ),
                          // Erase layer (white pen, transparent bg)
                          IgnorePointer(
                            ignoring: !_isEraserMode,
                            child: Signature(
                              controller: _stepEraserControllers[index],
                              backgroundColor: Colors.transparent,
                              height: 150,
                              width: double.infinity,
                            ),
                          ),
                        ],
                      ),
                    )
                  : TextField(
                      controller: _stepTextControllers[index],
                      readOnly: true,
                      showCursor: true,
                      maxLines: null,
                      expands: true,
                      onTap: () => setState(() => _activeStepIndex = index),
                      decoration: InputDecoration(
                        hintText: "Write step ${index + 1} here...",
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(14),
                        filled: false,
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.5, fontFamily: 'Inter'),
                    ),
            ),

            // Per-step feedback
            if (hasFeedback)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: feedback['correct'] == true ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      feedback['correct'] == true ? Icons.check_circle_outline : Icons.error_outline,
                      size: 18,
                      color: feedback['correct'] == true ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        feedback['feedback'] ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: feedback['correct'] == true ? Colors.green.shade900 : Colors.red.shade900,
                        ),
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

  @override
  Widget build(BuildContext context) {
    _syncLists(); // Ensure all lists are in sync (hot-reload safety)
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Solve Problem', style: TextStyle(color: AppColors.textPrimary)),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: Icon(_isHandwritingMode ? Icons.keyboard : Icons.edit, color: AppColors.primary),
            onPressed: () => setState(() => _isHandwritingMode = !_isHandwritingMode),
            tooltip: _isHandwritingMode ? 'Switch to Keyboard' : 'Switch to Handwriting',
          ),
          if (_isHandwritingMode) ...[
            IconButton(
              icon: const Icon(Icons.undo, color: AppColors.textPrimary),
              onPressed: () {
                if (_isEraserMode) {
                  _stepEraserControllers[_activeStepIndex].undo();
                } else {
                  _stepDrawControllers[_activeStepIndex].undo();
                }
              },
              tooltip: 'Undo',
            ),
            IconButton(
              icon: Icon(
                _isEraserMode ? Icons.auto_fix_high : Icons.auto_fix_off,
                color: _isEraserMode ? Colors.orange : AppColors.textPrimary,
              ),
              onPressed: _toggleEraserMode,
              tooltip: _isEraserMode ? 'Switch to Draw' : 'Switch to Eraser',
            ),
            IconButton(
              icon: const Icon(Icons.redo, color: AppColors.textPrimary),
              onPressed: () {
                if (_isEraserMode) {
                  _stepEraserControllers[_activeStepIndex].redo();
                } else {
                  _stepDrawControllers[_activeStepIndex].redo();
                }
              },
              tooltip: 'Redo',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: () {
                _stepDrawControllers[_activeStepIndex].clear();
                _stepEraserControllers[_activeStepIndex].clear();
              },
              tooltip: 'Clear Step',
            ),
          ],
        ],
      ),
      body: _isLoading
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            children: [
              // 1. Scrollable Content
              Positioned.fill(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 350),
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Question Card
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("Question", style: AppTextStyles.heading2.copyWith(color: AppColors.primary, fontSize: 14)),
                            const SizedBox(height: 10),
                            Text(
                              _question?['question'] ?? '',
                              style: const TextStyle(fontSize: 18, height: 1.6, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // "Your Solution" header
                      Text("Your Solution", style: AppTextStyles.heading2.copyWith(fontSize: 16)),
                      const SizedBox(height: 10),

                      // Step Cards
                      ...List.generate(_stepTextControllers.length, (i) => _buildStepCard(i)),

                      // Add Step Button
                      Center(
                        child: TextButton.icon(
                          onPressed: _addStep,
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                          label: const Text("Add Step"),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),

              // 2. Floating Controls (Buttons + Keypad)
              Positioned(
                bottom: 0,
                right: 0,
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Active step indicator
                      Padding(
                        padding: const EdgeInsets.only(right: 16.0, bottom: 4.0),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "Editing Step ${_activeStepIndex + 1}",
                            style: TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),

                      // Action Buttons
                      Padding(
                        padding: const EdgeInsets.only(right: 16.0, bottom: 8.0),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Submit Button
                            SizedBox(
                              width: _isHandwritingMode
                                  ? MediaQuery.of(context).size.width * 0.35
                                  : (MediaQuery.of(context).size.width * 0.35 - 4) / 2,
                              child: ElevatedButton.icon(
                                onPressed: _isAnalyzing ? null : _submitGrade,
                                icon: const Icon(Icons.save_alt, size: 16),
                                label: const Text("Submit", style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            // Check Button
                            SizedBox(
                              width: _isHandwritingMode
                                  ? MediaQuery.of(context).size.width * 0.35
                                  : (MediaQuery.of(context).size.width * 0.35 - 4) / 2,
                              child: ElevatedButton.icon(
                                onPressed: _isAnalyzing ? null : _checkAnswer,
                                icon: _isAnalyzing
                                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.auto_awesome, size: 16),
                                label: Text(
                                  _isAnalyzing ? "..." : "Check",
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Keypad
                      if (!_isHandwritingMode)
                        Align(
                          alignment: Alignment.bottomRight,
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width * 0.35,
                            height: MediaQuery.of(context).size.height * 0.35,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final width = constraints.maxWidth;
                                final height = constraints.maxHeight;
                                final buttonWidth = (width - 4) / 5;
                                final buttonHeight = (height - 5) / 6;
                                final ratio = buttonWidth / buttonHeight;

                                return Container(
                                  color: const Color(0xFFF1F5F9),
                                  padding: const EdgeInsets.all(2),
                                  child: GridView.count(
                                    physics: const NeverScrollableScrollPhysics(),
                                    crossAxisCount: 5,
                                    mainAxisSpacing: 1,
                                    crossAxisSpacing: 1,
                                    childAspectRatio: ratio,
                                    children: [
                                      'sin', 'cos', 'tan', '(', ')',
                                      'x²', '√', '^', 'log', '÷',
                                      '7', '8', '9', '⌫', '×',
                                      '4', '5', '6', 'Enter', '-',
                                      '1', '2', '3', '.', '+',
                                      '0', 'π', 'θ', 'Space', '='
                                    ].map((key) {
                                      final isOperator = ['÷', '×', '-', '+', '=', '^', '(', ')'].contains(key);
                                      final isFunction = ['sin', 'cos', 'tan', 'log', 'x²', '√', 'π', 'θ'].contains(key);
                                      final isAction = ['Enter', '⌫', 'Space'].contains(key);

                                      return Material(
                                        color: isAction ? const Color(0xFFCBD5E1) : (isOperator ? const Color(0xFFE2E8F0) : Colors.white),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(4),
                                          side: BorderSide(color: Colors.black.withOpacity(0.05)),
                                        ),
                                        elevation: 0,
                                        child: InkWell(
                                          onTap: () {
                                            if (key == 'Enter') {
                                              _insertText('\n');
                                            } else if (key == 'Space') {
                                              _insertText(' ');
                                            } else if (key == '⌫') {
                                              _backspace();
                                            } else if (['sin', 'cos', 'tan', 'log'].contains(key)) {
                                              _insertText('$key(');
                                            } else if (key == 'x²') {
                                              _insertText('^2');
                                            } else if (key == '√') {
                                              _insertText('√(');
                                            } else {
                                              _insertText(key);
                                            }
                                          },
                                          child: Center(
                                            child: isAction && key == '⌫'
                                                ? const Icon(Icons.backspace_outlined, size: 14, color: AppColors.textPrimary)
                                                : isAction && key == 'Enter'
                                                    ? const Icon(Icons.keyboard_return, size: 14, color: AppColors.textPrimary)
                                                    : isAction && key == 'Space'
                                                        ? const Icon(Icons.space_bar, size: 14, color: AppColors.textPrimary)
                                                        : Text(
                                                            key,
                                                            style: TextStyle(
                                                              fontSize: 12,
                                                              fontWeight: isOperator || isAction ? FontWeight.bold : FontWeight.w600,
                                                              color: isFunction ? AppColors.primary : AppColors.textPrimary,
                                                            ),
                                                          ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
    );
  }
}
