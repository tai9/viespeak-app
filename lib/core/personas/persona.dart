/// A read-only persona record served by the backend.
///
/// The system prompt and voice are baked into the ephemeral token server-side
/// when the session is minted — the client cannot override them. This model
/// only carries the fields the UI needs to display.
class Persona {
  final String id;
  final String name;
  final String description;
  final String voice;

  const Persona({
    required this.id,
    required this.name,
    required this.description,
    required this.voice,
  });

  factory Persona.fromJson(Map<String, dynamic> json) {
    return Persona(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      voice: json['voice'] as String? ?? '',
    );
  }
}
