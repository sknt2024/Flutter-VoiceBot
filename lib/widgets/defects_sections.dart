import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/defect.dart';
import '../models/inspection_defect.dart';
import 'defects_dropdown.dart';

class DefectsSections extends StatefulWidget {
  const DefectsSections({super.key});

  @override
  State<DefectsSections> createState() => _DefectsSectionsState();
}

class _DefectsSectionsState extends State<DefectsSections> {
  bool _defectsPresent = false;
  File? _defectImage;

  final ImagePicker _picker = ImagePicker();

  void toggleDefects(bool value) {
    setState(() {
      _defectsPresent = value;
      if (!value) {
        _inspectionDefects
          ..clear()
          ..add(InspectionDefect());
      }
    });
  }

  Future<void> _pickImage(int index) async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 100,
    );

    print("Image: ${image?.path}");

    if (image != null) {
      setState(() {
        _inspectionDefects[index].defectImage = File(image.path);
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _inspectionDefects[index].defectImage = null;
    });
  }

  final List<Defect> defects = [
    Defect(id: "62ab0eaef58cc5a2dd8b759b", name: "Alternate Lug Wear"),
    Defect(id: "62b063992f323e536c71a33a", name: "Both Shoulder Wear"),
    Defect(id: "62b063a12f323e536c71a349", name: "Centre Wear"),
    Defect(id: "62b063aa2f323e536c71a357", name: "Feather Edge Wear"),
    Defect(id: "62b063b52f323e536c71a363", name: "Heel & Toe Wear"),
    Defect(id: "62b063bf2f323e536c71a36f", name: "Inside Edge Wear"),
    Defect(id: "62b064032f323e536c71a3b1", name: "Irregular Wear"),
    Defect(id: "62b0656b2f323e536c71a44c", name: "Rib Pinch Wear"),
    Defect(id: "62b065742f323e536c71a454", name: "Scallop Wear"),
    Defect(id: "62b0657d2f323e536c71a45c", name: "Scrubung Scuffing Wear"),
    Defect(id: "62b065872f323e536c71a464", name: "Spotty Wear"),
    Defect(id: "62b065902f323e536c71a46c", name: "Wavy Wear"),
    Defect(id: "62b0659c2f323e536c71a474", name: "One Side Wear"),
    Defect(id: "62b065a62f323e536c71a47c", name: "Diagonal Wear"),
    Defect(id: "62b065ae2f323e536c71a484", name: "Chipping Wear"),
    Defect(id: "62b065b82f323e536c71a48d", name: "Bulging"),
    Defect(id: "62b065bf2f323e536c71a495", name: "Worn Out"),
    Defect(id: "62b065c72f323e536c71a4a7", name: "Patchy Wear"),
    Defect(id: "62b065d02f323e536c71a4af", name: "Chipping"),
    Defect(id: "62b065d72f323e536c71a4b7", name: "All Good"),
    Defect(id: "63198e1a34f8e69c02ac6c28", name: "Cut Repair"),
    Defect(id: "638f23fe0cc0a310c8892676", name: "Puncher"),
    Defect(id: "63970c4589440543e50abb17", name: "Side Wall cut"),
    Defect(id: "63b413dffcde9bc3234a816d", name: "Missing"),
    Defect(
      id: "63b659f6671b030891ed73e7",
      name: "Wrongly worn due to Alignment",
    ),
    Defect(id: "63c55a8602dfea2de0aa4eb8", name: "Manufacturing"),
    Defect(id: "63d55208d7b631bee33c04b5", name: "Burnout tyre"),
    Defect(id: "63e4bc620300dfab84cc362c", name: "Runflat"),
    Defect(id: "63ef4582f96182ad5523050a", name: "Tread Damage"),
    Defect(id: "63ef458cf96182ad55230511", name: "Wire Expose"),
    Defect(id: "642e657e051f9043375e321d", name: "Scoring"),
    Defect(id: "6603b8f14c1c2146d0ab1734", name: "Zipper Cut"),
    Defect(id: "67dd61b54e4c21cc5966487f", name: "Stencil Not matching"),
  ];

  final List<InspectionDefect> _inspectionDefects = [InspectionDefect()];

  Future<void> showImagePreviewDialog({
    required BuildContext context,
    required File image,
    required VoidCallback onDelete,
  }) {
    final media = MediaQuery.of(context);

    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  /// IMAGE (dynamic & scaled down)
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: media.size.height * 0.65,
                      maxWidth: media.size.width * 0.9,
                    ),
                    child: InteractiveViewer(
                      minScale: 0.8,
                      maxScale: 4,
                      child: Image.file(
                        image,
                        fit: BoxFit.contain,
                        width: double.infinity,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  /// ACTIONS
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          onDelete();
                        },
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                        label: const Text(
                          'Delete',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Is there any defects?"),
            Switch.adaptive(value: _defectsPresent, onChanged: toggleDefects),
          ],
        ),
        const SizedBox(height: 12),

        /// Dropdown
        Visibility(
          visible: _defectsPresent,
          child: Column(
            spacing: 8,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Defects",
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _inspectionDefects.add(InspectionDefect());
                      });
                    },
                    child: Container(
                      padding: EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        borderRadius: BorderRadius.circular(8.0),
                        border: Border.all(
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      child: Icon(Icons.add, color: Colors.white),
                    ),
                  ),
                ],
              ),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _inspectionDefects.length,
                separatorBuilder: (context, index) => SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _inspectionDefects[index];
                  return Row(
                    spacing: 8,
                    children: [
                      /// Defect dropdown
                      Flexible(
                        child: DefectDropdown(
                          defects: defects,
                          value: item.defectId == null
                              ? null
                              : defects.firstWhere(
                                  (d) => d.id == item.defectId,
                                ),
                          onChanged: (Defect? defect) {
                            setState(() {
                              item.defectId = defect?.id;
                              item.defectName = defect?.name;
                            });
                          },
                        ),
                      ),

                      item.defectImage == null
                          ? InkWell(
                              onTap: () => _pickImage(index),
                              child: Container(
                                padding: EdgeInsets.all(16.0),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).primaryColor,
                                  borderRadius: BorderRadius.circular(8.0),
                                  border: Border.all(
                                    color: Theme.of(context).primaryColor,
                                  ),
                                ),
                                child: Icon(
                                  Icons.camera_alt_outlined,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Stack(
                                children: [
                                  InkWell(
                                    onTap: () {
                                      showImagePreviewDialog(
                                        context: context,
                                        image: item.defectImage!,
                                        onDelete: () => _removeImage(index),
                                      );
                                    },
                                    child: Container(
                                      width: kToolbarHeight,
                                      height: kToolbarHeight,
                                      padding: const EdgeInsets.all(2),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).primaryColor,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: Image.file(
                                          item.defectImage!,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                                  ),

                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: InkWell(
                                      onTap: () => _removeImage(index),
                                      child: Container(
                                        alignment: Alignment.center,
                                        padding: EdgeInsets.all(2),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.only(
                                            bottomLeft: Radius.circular(4),
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.close_rounded,
                                          color: Colors.white,
                                          size: 16,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: kToolbarHeight * 2),
      ],
    );
  }
}
