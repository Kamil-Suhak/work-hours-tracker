import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'markdown_renderer.dart';

class NotePreviewQuadrant extends StatelessWidget {
  final TextEditingController controller;
  final bool isEditingPastShift;
  final String? shiftDateLabel;
  final VoidCallback? onReturnToCurrentShift;

  const NotePreviewQuadrant({
    super.key,
    required this.controller,
    this.isEditingPastShift = false,
    this.shiftDateLabel,
    this.onReturnToCurrentShift,
  });

  @override
  Widget build(BuildContext context) {
    final activeColor =
        isEditingPastShift ? const Color(0xFF38BDF8) : const Color(0xFF10B981);
    const slateDark = Color(0xFF1E293B);

    return Container(
      decoration: BoxDecoration(
        color: slateDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF334155),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  isEditingPastShift
                      ? Icons.history_edu
                      : Icons.preview_outlined,
                  color: activeColor,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    isEditingPastShift && shiftDateLabel != null
                        ? 'Markdown Preview | Shift on $shiftDateLabel'
                        : 'Markdown Preview',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: Color(0xFFF8FAFC),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                if (isEditingPastShift && onReturnToCurrentShift != null) ...[
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: const Color(0xFF38BDF8),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: const Icon(Icons.arrow_back, size: 14),
                    label: const Text(
                      'Current Shift',
                      style:
                          TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    onPressed: onReturnToCurrentShift,
                  ),
                  const SizedBox(width: 4),
                ],
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final hasContent = controller.text.trim().isNotEmpty;
                    if (!hasContent) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copy Note Markdown',
                      color: const Color(0xFF94A3B8),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: controller.text));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Note copied to clipboard!'),
                            duration: Duration(seconds: 1),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
          const Divider(color: Color(0xFF334155), height: 1),

          // Preview Body
          Expanded(
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) {
                final text = controller.text;
                if (text.trim().isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.visibility_outlined,
                            size: 40,
                            color: Color(0xFF475569),
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No notes to preview',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Type in the editor above to preview formatted markdown here in real time.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: MarkdownText(
                    markdown: text,
                    baseStyle: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      color: Color(0xFFE2E8F0),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
