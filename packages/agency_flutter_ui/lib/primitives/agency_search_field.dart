import 'package:flutter/material.dart';

class AgencySearchField extends StatelessWidget {
  const AgencySearchField({
    super.key,
    this.hintText = 'Search',
    this.controller,
    this.onChanged,
    this.onSubmitted,
  });

  final String hintText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search),
      ),
    );
  }
}
