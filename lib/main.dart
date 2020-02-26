import 'dart:async';

import 'package:camera/camera.dart';
import 'package:rtod/real_time_torch_mobile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:native_device_orientation/native_device_orientation.dart';

List<CameraDescription> cameras = [];

Future<void> main () async {
  try {
    WidgetsFlutterBinding();
    cameras = await availableCameras();
  } on CameraException catch (e) {
    print('Error: $e.code\nError Message: $e.message');
  }
  SystemChrome.setEnabledSystemUIOverlays([]);
  SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]).then((_) {
      runApp(CameraApp());
    });
}

class CameraApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: CameraExampleHome(),
    );
  }
}

class CameraExampleHome extends StatefulWidget {
  @override 
  _CameraExampleState createState() => _CameraExampleState();
}

class _CameraExampleState extends State<CameraExampleHome> 
with WidgetsBindingObserver { // アプリのライフサイクルとかデバイスの向き（縦or横）の取得等するためのインターフェース

  CameraController _controller;
  bool _isDetecting = false; 
  String _className = 'this is text';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    try {
      MyTorchMobile.loadModel(
        model: 'assets/model.pt',
        labels: 'assets/labels.txt'
      );
    } on PlatformException{}

    _controller = CameraController(cameras[0], ResolutionPreset.high);
    _controller.initialize().then((_) {
      if (!mounted)  return;
      _controller.startImageStream((CameraImage availableImage) {
        if (_isDetecting) return;
        _isDetecting = true;
        _makePrediction(availableImage);
        _isDetecting = false;
      });
    });
  }
  Future<void> _makePrediction(CameraImage img) async {
    String prediction; 
    prediction = 'not null';
    try {
      prediction = await MyTorchMobile.getPredict(
        planes: img.planes.map((plane) { return plane.bytes; }).toList(), 
        imgWidth: img.width,
        imgHeight: img.height,
        inputSize: 224,
      );
    } on PlatformException {
      prediction = 'not predicted';
    }
    setState(() {
      _className = prediction;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) { //　アプリがバッググラウンドに移行した直後と、フォアグラウンドに移行した直後に呼ばれる
    // App state changed before we got the chance to initialize.
    if (_controller == null || !_controller.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      _controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller != null) {
        _controller = CameraController(cameras[0], ResolutionPreset.high);
        _controller.initialize().then((_) {
          if (!mounted)  return;
          _controller.startImageStream((CameraImage availableImage) {
            if (_isDetecting) return;
            _isDetecting = true;
            _makePrediction(availableImage);
            _isDetecting = false;
          });
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.value.isInitialized) {
      return Container();
    }
    return Scaffold(
      body: NativeDeviceOrientationReader(builder: (context) {
        NativeDeviceOrientation orientation = 
        NativeDeviceOrientationReader.orientation(context);

        int turns;
        switch (orientation) {
          case NativeDeviceOrientation.landscapeLeft:
            turns = -1;
            break;
          case NativeDeviceOrientation.landscapeRight:
            turns = 1;
            break;
          default:
            turns = 0;
            break;
        }
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Center(
              child: Transform.scale(
                // scale: 1 / _controller.value.aspectRatio,
                scale: 1,
                child: RotatedBox(
                  quarterTurns: turns,
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: CameraPreview(_controller),
                  )
                ),
              ),
            ),
            CustomPaint(painter: BoundingBoxPainter(null)),
            Center(
              child: Text(_className, style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 30,
                color: Colors.cyan,
              ),)
            ),
          ]
        );
      })
    );
  }
}


class BoundingBoxPainter extends CustomPainter {
  Map rect;
  // List<Map> rects;
  BoundingBoxPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    if (rect != null) {
      final paint = Paint();
      paint.color = Colors.red;
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = 2.0;

      double x, y, w, h;
      x = rect["x"];
      y = rect["y"];
      w = rect["w"];
      h = rect["h"];
      Rect boundingBox = Offset(x, y) & Size(w, h); // https://api.flutter.dev/flutter/dart-ui/Rect-class.html
      canvas.drawRect(boundingBox, paint);
    }
  }
  @override
  bool shouldRepaint(BoundingBoxPainter oldDelegate) => true;
}
