import 'package:flutter/material.dart';

class OldGrooveReadings extends StatelessWidget {
  final String g1;
  final String g2;
  final String g3;
  final String g4;
  const OldGrooveReadings({super.key, required this.g1, required this.g2, required this.g3, required this.g4});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _oldDataField(
            label: "G1 (mm)",
            controller: TextEditingController(
              text: g1,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _oldDataField(
            label: "G2 (mm)",
            controller: TextEditingController(
              text: g2,
            ),
          ),
        ),
        const SizedBox(width: 12),

        Expanded(
          child: _oldDataField(
            label: "G3 (mm)",
            controller: TextEditingController(
              text: g3,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _oldDataField(
            label: "G4 (mm)",
            controller: TextEditingController(
              text: g4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _oldDataField({
    required String label,
    required TextEditingController controller,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          readOnly: false,
          showCursor: false,
          decoration: InputDecoration(
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8.0),
            ),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(width: 2),
              borderRadius: BorderRadius.circular(8.0),
            ),
          ),
        ),
      ],
    );
  }
}
