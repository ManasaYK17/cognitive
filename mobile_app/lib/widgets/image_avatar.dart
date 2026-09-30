import 'package:flutter/material.dart';

class ImageAvatar extends StatelessWidget {
  final String? imageUrl;
  final String? bearerToken;
  final double radius;
  final Widget? placeholder;
  final Color? backgroundColor;

  const ImageAvatar({
    required this.imageUrl,
    this.bearerToken,
    this.radius = 24,
    this.placeholder,
    this.backgroundColor,
    super.key,
  });

  Map<String, String>? get _headers => bearerToken == null
      ? null
      : {'Authorization': 'Bearer $bearerToken'};

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    final hasImage = url != null && url.isNotEmpty;
    final fallback = Center(child: placeholder);
    return GestureDetector(
      onTap: hasImage ? () => _showPhoto(context, url) : null,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor ?? Theme.of(context).colorScheme.primary.withAlpha(46),
        child: hasImage
            ? ClipOval(
                child: Image.network(
                  url,
                  width: radius * 2,
                  height: radius * 2,
                  fit: BoxFit.cover,
                  headers: _headers,
                  errorBuilder: (_, __, ___) => fallback,
                  loadingBuilder: (_, child, progress) => progress == null ? child : fallback,
                ),
              )
            : fallback,
      ),
    );
  }

  Future<void> _showPhoto(BuildContext context, String url) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: GestureDetector(
          onTap: () => Navigator.of(dialogContext).pop(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340, maxHeight: 440),
              child: Image.network(
                url,
                fit: BoxFit.contain,
                headers: _headers,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}