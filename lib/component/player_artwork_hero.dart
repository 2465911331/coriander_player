import 'package:flutter/material.dart';
import '../app_design.dart';

class PlayerArtworkHero extends StatelessWidget {
  const PlayerArtworkHero({super.key, required this.child, this.cover});
  final Widget child;
  final ImageProvider? cover;
  @override
  Widget build(BuildContext context) => HeroMode(
      enabled: AppMotion.enabled(context),
      child: Hero(
          tag: 'coriander-current-artwork',
          createRectTween: (begin, end) =>
              MaterialRectCenterArcTween(begin: begin, end: end),
          flightShuttleBuilder: (context, animation, direction, from, to) {
            final source = (from.widget as Hero).child as _ArtworkContent;
            final destination = (to.widget as Hero).child as _ArtworkContent;
            final image = destination.cover ?? source.cover;
            return Material(
                color: Colors.transparent,
                child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: image == null
                        ? ColoredBox(
                            color:
                                Theme.of(context).colorScheme.primaryContainer,
                            child: const Icon(Icons.music_note_rounded))
                        : Image(
                            image: image,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.music_note_rounded))));
          },
          child: _ArtworkContent(cover: cover, child: child)));
}

class _ArtworkContent extends StatelessWidget {
  const _ArtworkContent({required this.cover, required this.child});
  final ImageProvider? cover;
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}
