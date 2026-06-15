import 'package:flutter/material.dart';

import 'app_search_field.dart';

Future<bool> confirmActionDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmText,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmText),
        ),
      ],
    ),
  );
  return confirmed == true;
}

Future<String?> showAppTextInputDialog(
  BuildContext context, {
  required String title,
  required String hintText,
  required String confirmText,
  String initialValue = '',
  int minLines = 1,
  int maxLines = 12,
  double? width,
  bool autofocus = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _AppTextInputDialog(
      title: title,
      hintText: hintText,
      confirmText: confirmText,
      initialValue: initialValue,
      minLines: minLines,
      maxLines: maxLines,
      width: width,
      autofocus: autofocus,
    ),
  );
}

void showBlockingProgressDialog(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Text(message),
        ],
      ),
    ),
  );
}

class _AppTextInputDialog extends StatefulWidget {
  const _AppTextInputDialog({
    required this.title,
    required this.hintText,
    required this.confirmText,
    required this.initialValue,
    required this.minLines,
    required this.maxLines,
    required this.width,
    required this.autofocus,
  });

  final String title;
  final String hintText;
  final String confirmText;
  final String initialValue;
  final int minLines;
  final int maxLines;
  final double? width;
  final bool autofocus;

  @override
  State<_AppTextInputDialog> createState() => _AppTextInputDialogState();
}

class _AppTextInputDialogState extends State<_AppTextInputDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final field = TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      decoration: AppInputDecoration.flat(context, hintText: widget.hintText),
    );
    final input = widget.width == null
        ? field
        : SizedBox(width: widget.width, child: field);
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: inset),
        child: input,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(widget.confirmText),
        ),
      ],
    );
  }
}
