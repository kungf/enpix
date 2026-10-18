import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Full-screen pinch-zoom viewer for an already-decrypted cloud photo.
class CloudImageViewer extends StatelessWidget {
  const CloudImageViewer({super.key, required this.data});

  final Uint8List data;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black54,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5.0,
          child: Image.memory(data, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
