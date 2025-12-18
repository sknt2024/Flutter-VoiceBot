import 'package:flutter/material.dart';

import '../models/defect.dart';

class DefectDropdown extends StatelessWidget {
  final List<Defect> defects;
  final Defect? value;
  final ValueChanged<Defect?>? onChanged;

  const DefectDropdown({
    super.key,
    required this.defects,
    this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<Defect>(
      value: value,
      hint: const Text('Select Defect'),
      isExpanded: true,
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.0),
        ),
      ),
      items: defects.map((defect) {
        return DropdownMenuItem<Defect>(
          value: defect,
          child: Text(defect.name),
        );
      }).toList(),
      onChanged: onChanged,
    );
  }
}
