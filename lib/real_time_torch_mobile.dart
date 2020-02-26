import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';


class MyTorchMobile {
  static const MethodChannel _channel = const MethodChannel('com.example.rtod/rttm');
  static List<String> words = [];

  ///Sets pytorch Model path to be used
  static void _getModel(String modelPath) async {
    String absoluteModelPath = await _getAbsoluteModelPath(modelPath);
    _channel.invokeMethod('setModelPath', absoluteModelPath);
  }

  static Future<String> _getAbsoluteModelPath(String modelPath) async {
    Directory directory = await getApplicationDocumentsDirectory();
    String dbPath = join(directory.path, "model.pt");
    ByteData data = await rootBundle.load(modelPath);
    List<int> bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    //write data to file to have a shareable absolute path
    await File(dbPath).writeAsBytes(bytes);
    return dbPath;
  }

  ///Sets pytorch label file path to be used
  static Future<List<String>> _getLabels(String labelPath) async {
    String labelsData = await rootBundle.loadString(labelPath);
    words = labelsData.split('\n');
    return words;
  }

  ///load model and associated labels
  static void loadModel(
      {@required String model, @required String labels}) async {
    _getModel(model);
    _getLabels(labels);
  }

  static Future<String> getPredict(
    {@required List<Uint8List> planes, 
    @required int imgWidth,
    @required int imgHeight,
    @required int inputSize
  }) async {
    final Map args = <String, dynamic> {
      "img": planes,
      "imgWidth": imgWidth,
      "imgHeight": imgHeight,
      "inputSize": inputSize,
    };
    final String result = await _channel.invokeMethod('predict', args);
    List predictions = jsonDecode(result);
    double maxScore = 0;
    int maxScoreIdx = -1;
    for (int i=0; i<predictions.length; i++) {
      if (predictions[i] > maxScore) {
        maxScore = predictions[i];
        maxScoreIdx = i;
      }
    }
    String className = words[maxScoreIdx];
    return className;
  }
}
