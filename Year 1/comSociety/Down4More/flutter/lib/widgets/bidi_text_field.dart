import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A near-drop-in replacement for [TextField] that flips its caret position
/// and text alignment to RTL when the current text contains right-to-left
/// characters (Arabic, Hebrew, Persian, Syriac, Thaana).
///
/// Plain [TextField] inherits its direction from the ambient [Directionality],
/// which means typing Arabic into an LTR app leaves the caret on the wrong
/// side and the text reads backwards. Detecting direction from content fixes
/// both for the common case where a single field may legitimately receive
/// either script.
class BidiTextField extends StatefulWidget {
  const BidiTextField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.minLines,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.decoration,
    this.style,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool autofocus;
  final int? maxLines;
  final int? minLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final InputDecoration? decoration;
  final TextStyle? style;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;

  /// True if [text] contains at least one strong right-to-left character.
  ///
  /// Covers the four most-used RTL Unicode blocks: Hebrew (U+0590–U+05FF),
  /// Arabic + supplements (U+0600–U+06FF, U+0750–U+077F, U+08A0–U+08FF),
  /// Syriac (U+0700–U+074F), Thaana (U+0780–U+07BF), and the Arabic
  /// presentation forms (U+FB50–U+FDFF, U+FE70–U+FEFF).
  static bool isRtl(String text) {
    for (final code in text.runes) {
      if ((code >= 0x0590 && code <= 0x05FF) ||
          (code >= 0x0600 && code <= 0x06FF) ||
          (code >= 0x0700 && code <= 0x074F) ||
          (code >= 0x0750 && code <= 0x077F) ||
          (code >= 0x0780 && code <= 0x07BF) ||
          (code >= 0x08A0 && code <= 0x08FF) ||
          (code >= 0xFB50 && code <= 0xFDFF) ||
          (code >= 0xFE70 && code <= 0xFEFF)) {
        return true;
      }
    }
    return false;
  }

  @override
  State<BidiTextField> createState() => _BidiTextFieldState();
}

class _BidiTextFieldState extends State<BidiTextField> {
  late bool _rtl;

  @override
  void initState() {
    super.initState();
    _rtl = BidiTextField.isRtl(widget.controller.text);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant BidiTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _onControllerChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final next = BidiTextField.isRtl(widget.controller.text);
    if (next != _rtl) setState(() => _rtl = next);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      decoration: widget.decoration,
      style: widget.style,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      focusNode: widget.focusNode,
      textDirection: _rtl ? TextDirection.rtl : TextDirection.ltr,
      textAlign: _rtl ? TextAlign.right : TextAlign.left,
    );
  }
}
