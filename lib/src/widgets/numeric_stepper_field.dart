import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A desktop-friendly numeric field with editable text and up/down buttons.
///
/// Arrow buttons always stay inside [minimum] and [maximum]. Typed text is
/// clamped and normalized when Enter is pressed or the field loses focus.
class NumericStepperField extends StatefulWidget {
  const NumericStepperField({
    required this.value,
    required this.minimum,
    required this.maximum,
    required this.step,
    required this.decimalPlaces,
    required this.onChanged,
    this.labelText,
    this.enabled = true,
    super.key,
  });

  final double value;
  final double minimum;
  final double maximum;
  final double step;
  final int decimalPlaces;
  final ValueChanged<double> onChanged;
  final String? labelText;
  final bool enabled;

  @override
  State<NumericStepperField> createState() => _NumericStepperFieldState();
}

class _NumericStepperFieldState extends State<NumericStepperField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _format(widget.value));
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(NumericStepperField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final typedValue = double.tryParse(_controller.text);
      final cameFromThisField = _focusNode.hasFocus &&
          typedValue != null &&
          (typedValue - widget.value).abs() < 0.000001;
      if (!cameFromThisField) _controller.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_focusNode.hasFocus) _commitText();
  }

  void _commitText() {
    final parsed = double.tryParse(_controller.text);
    final normalized = _normalize(parsed ?? widget.value);
    _controller.text = _format(normalized);
    widget.onChanged(normalized);
  }

  void _nudge(double delta) {
    if (!widget.enabled) return;
    final next = _normalize(widget.value + delta);
    _controller.text = _format(next);
    widget.onChanged(next);
  }

  String _format(double value) => value.toStringAsFixed(widget.decimalPlaces);

  double _normalize(double value) {
    final clamped = value.clamp(widget.minimum, widget.maximum).toDouble();
    return double.parse(_format(clamped));
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      keyboardType: TextInputType.numberWithOptions(
        decimal: widget.decimalPlaces > 0,
        signed: widget.minimum < 0,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[-0-9.]')),
      ],
      onSubmitted: (_) => _commitText(),
      onChanged: (text) {
        final parsed = double.tryParse(text);
        if (parsed != null &&
            parsed >= widget.minimum &&
            parsed <= widget.maximum) {
          widget.onChanged(parsed);
        }
      },
      decoration: InputDecoration(
        labelText: widget.labelText,
        suffixIconConstraints: const BoxConstraints.tightFor(width: 30),
        suffixIcon: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ArrowButton(
              icon: Icons.keyboard_arrow_up_rounded,
              onPressed: widget.enabled ? () => _nudge(widget.step) : null,
            ),
            _ArrowButton(
              icon: Icons.keyboard_arrow_down_rounded,
              onPressed: widget.enabled ? () => _nudge(-widget.step) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 26,
      height: 18,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
      ),
    );
  }
}
