import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'markdown_renderer.dart';

class NotePreviewQuadrant extends StatelessWidget {
  final TextEditingController controller;

  const NotePreviewQuadrant({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF10B981);
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
                const Icon(
                  Icons.preview_outlined,
                  color: activeColor,
                  size: 22,
                ),
                const SizedBox(width: 10),
                const Text(
                  'Live Markdown Preview',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Color(0xFFF8FAFC),
                  ),
                ),
                const Spacer(),
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
