import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

// ─── AppTextField (ChaloCampus) ───────────────────────────────────────────────
//
// Professional, animated input field:
// - Focus-driven animated border
// - Inline error text
// - Optional floating label via labelText
// - Password visibility toggle
// - Keyboard flow via nextFocusNode

class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String                hintText;
  final String?               labelText;
  final bool                  isPassword;
  final String?               errorText;
  final TextInputType         keyboardType;
  final TextInputAction       textInputAction;
  final IconData?             prefixIcon;
  final FocusNode?            focusNode;
  final FocusNode?            nextFocusNode;
  final ValueChanged<String>? onChanged;
  final VoidCallback?         onSubmitted;
  final Iterable<String>?     autofillHints;
  final bool                  enabled;

  const AppTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.labelText,
    this.isPassword      = false,
    this.errorText,
    this.keyboardType    = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.prefixIcon,
    this.focusNode,
    this.nextFocusNode,
    this.onChanged,
    this.onSubmitted,
    this.autofillHints,
    this.enabled = true,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscure   = true;
  bool _isFocused = false;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _focus = widget.focusNode ?? FocusNode();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (mounted) setState(() => _isFocused = _focus.hasFocus);
  }

  @override
  void dispose() {
    if (widget.focusNode == null) _focus.dispose();
    super.dispose();
  }

  bool get _hasError => widget.errorText != null && widget.errorText!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final borderColor = _hasError
        ? AppColors.danger
        : _isFocused
            ? AppColors.primary
            : AppColors.border;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.labelText != null) ...[
          Text(
            widget.labelText!,
            style: GoogleFonts.plusJakartaSans(
              color     : _hasError
                  ? AppColors.danger
                  : _isFocused
                      ? AppColors.primary
                      : AppColors.textMuted,
              fontSize  : 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 6),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color       : _isFocused
                ? Colors.white.withOpacity(0.05)
                : Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border      : Border.all(
              color: borderColor,
              width: _isFocused ? 1.5 : 1.0,
            ),
          ),
          child: TextField(
            controller    : widget.controller,
            focusNode     : _focus,
            obscureText   : widget.isPassword && _obscure,
            keyboardType  : widget.keyboardType,
            textInputAction: widget.textInputAction,
            autofillHints : widget.autofillHints,
            enabled       : widget.enabled,
            style         : GoogleFonts.plusJakartaSans(
              color    : AppColors.text,
              fontSize : 15,
            ),
            onChanged: widget.onChanged,
            onSubmitted: (_) {
              if (widget.nextFocusNode != null) {
                widget.nextFocusNode!.requestFocus();
              } else {
                widget.onSubmitted?.call();
              }
            },
            decoration: InputDecoration(
              hintText     : widget.hintText,
              hintStyle    : GoogleFonts.plusJakartaSans(
                color    : AppColors.textMuted,
                fontSize : 14,
              ),
              border       : InputBorder.none,
              prefixIcon   : widget.prefixIcon != null
                  ? Icon(
                      widget.prefixIcon,
                      color: _isFocused
                          ? AppColors.primary
                          : AppColors.textMuted,
                      size: 20,
                    )
                  : null,
              suffixIcon   : widget.isPassword
                  ? IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: AppColors.textMuted,
                        size: 18,
                      ),
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 16),
            ),
          ),
        ),
        if (_hasError) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.danger,
                size : 13,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  widget.errorText!,
                  style: GoogleFonts.plusJakartaSans(
                    color    : AppColors.danger,
                    fontSize : 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

// ─── Backward-compat alias ───────────────────────────────────────────────────

@Deprecated('Use AppTextField instead')
typedef CustomTextField = AppTextField;

