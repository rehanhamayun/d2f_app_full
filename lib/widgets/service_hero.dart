import 'package:flutter/material.dart';

/// All typography and controls are native Flutter widgets over local artwork.
class ServiceHero extends StatelessWidget {
  final String image, eyebrow, title, description;
  final Color color;
  final bool compact;
  final String? action;
  final VoidCallback? onAction;
  const ServiceHero({
    super.key,
    required this.image,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.color,
    this.compact = false,
    this.action,
    this.onAction,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(28),
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: .19),
          blurRadius: 22,
          offset: const Offset(0, 9),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/services_$image.jpg',
              fit: BoxFit.cover,
              alignment: const Alignment(.4, 0),
              excludeFromSemantics: true,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: .86),
                    color.withValues(alpha: .35),
                    color.withValues(alpha: .12),
                  ],
                  stops: const [0, .6, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, color.withValues(alpha: .93)],
                  stops: const [.3, 1],
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(compact ? 18 : 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeroBadge(text: eyebrow),
                SizedBox(height: compact ? 26 : 45),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 26 : 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1.1,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 9),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 300),
                  child: Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFFF5F5FF),
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: onAction,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: color,
                      minimumSize: const Size(0, 46),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            action!,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Icon(Icons.arrow_forward_rounded, size: 18),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _HeroBadge extends StatelessWidget {
  final String text;
  const _HeroBadge({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: Colors.white.withValues(alpha: .26)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 9,
        letterSpacing: 1,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}
