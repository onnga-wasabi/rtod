package com.example.rtod;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.embedding.engine.plugins.shim.ShimPluginRegistry;
import io.flutter.plugin.common.PluginRegistry.Registrar;
import io.flutter.plugins.GeneratedPluginRegistrant;
import io.flutter.plugin.platform.PlatformPlugin;

import org.pytorch.IValue;
import org.pytorch.Module;
import org.pytorch.Tensor;
import org.pytorch.torchvision.TensorImageUtils;

import androidx.annotation.NonNull;
import android.content.Context;
import android.graphics.*;
import android.util.Log;
import android.content.Context;
import android.renderscript.Allocation;
import android.renderscript.Element;
import android.renderscript.RenderScript;
import android.renderscript.ScriptIntrinsicYuvToRGB;
import android.renderscript.Type;
import android.os.Bundle;

import com.google.gson.Gson;

import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.HashMap;
import java.util.List;


public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.example.rtod/rttm";
    private static Module module;
    private static String calledMethod;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        ShimPluginRegistry shimPluginRegistry = new ShimPluginRegistry(flutterEngine);
        GeneratedPluginRegistrant.registerWith(flutterEngine);
        RealTimeTorchMobilePlugin.registerWith(shimPluginRegistry.registrarFor("com.example.rtod.MainActivity"));
    }
}

class RealTimeTorchMobilePlugin implements MethodCallHandler {
    // https://github.com/shaqian/flutter_tflite/blob/f35fd091d324643ea061493e81599b6fb4b1ea7e/android/src/main/java/sq/flutter/tflite/TflitePlugin.java
    private static final String CHANNEL = "com.example.rtod/rttm";
    private static Module module;
    private static String calledMethod;
    private final Registrar mRegistrar;

    public static void registerWith(Registrar registrar) {
        final MethodChannel channel = new MethodChannel(registrar.messenger(), CHANNEL);
        channel.setMethodCallHandler(new RealTimeTorchMobilePlugin(registrar));
    }
    private RealTimeTorchMobilePlugin(Registrar registrar) {
        this.mRegistrar = registrar;
    }
    public Allocation renderScriptNV21ToRGBA888(Context context, int width, int height, byte[] nv21) {
        // https://stackoverflow.com/a/36409748
        RenderScript rs = RenderScript.create(context);
        ScriptIntrinsicYuvToRGB yuvToRgbIntrinsic = ScriptIntrinsicYuvToRGB.create(rs, Element.U8_4(rs));

        Type.Builder yuvType = new Type.Builder(rs, Element.U8(rs)).setX(nv21.length);
        Allocation in = Allocation.createTyped(rs, yuvType.create(), Allocation.USAGE_SCRIPT);

        Type.Builder rgbaType = new Type.Builder(rs, Element.RGBA_8888(rs)).setX(width).setY(height);
        Allocation out = Allocation.createTyped(rs, rgbaType.create(), Allocation.USAGE_SCRIPT);

        in.copyFrom(nv21);

        yuvToRgbIntrinsic.setInput(in);
        yuvToRgbIntrinsic.forEach(out);
        return out;
    }
    private Bitmap planes2Bitmap(List<byte[]> bytesList, int imageWidth, int imageHeight) {
        ByteBuffer Y = ByteBuffer.wrap(bytesList.get(0));
        ByteBuffer U = ByteBuffer.wrap(bytesList.get(1));
        ByteBuffer V = ByteBuffer.wrap(bytesList.get(2));

        int Yb = Y.remaining();
        int Ub = U.remaining();
        int Vb = V.remaining();

        byte[] data = new byte[Yb + Ub + Vb];

        Y.get(data, 0, Yb);
        V.get(data, Yb, Vb);
        U.get(data, Yb + Vb, Ub);

        Bitmap bitmapRaw = Bitmap.createBitmap(imageWidth, imageHeight, Bitmap.Config.ARGB_8888);
        Allocation bmData = renderScriptNV21ToRGBA888(
            mRegistrar.context(),
            imageWidth,
            imageHeight,
            data);
        bmData.copyTo(bitmapRaw);
        return bitmapRaw;
    }

    private Bitmap centerCropResize(Bitmap bitmap, int outsize) {

        int width = bitmap.getWidth();
        int height = bitmap.getHeight();

        int centerX = width / 2;
        int centerY = height / 2;
        int size = Math.min(width, height) / 2;

        Bitmap resultBmp = Bitmap.createBitmap(size*2, size*2, Bitmap.Config.ARGB_8888);
        new Canvas(resultBmp).drawBitmap(bitmap, centerX - size, centerY - size, null);
        resultBmp = Bitmap.createScaledBitmap(resultBmp, outsize, outsize, false);
        return resultBmp;
    }
    @Override
    public void onMethodCall(MethodCall call, Result result) {
        if (call.method.equals("setModelPath")) {
            try {
                module = Module.load((String) call.arguments);
                result.success("set ModelPath method was called");
            } catch (Exception e) {
                Log.d("dame", "dame", e);
            }
        } else if (call.method.equals("predict")) {
            Bitmap bitmap = null;
            try {
                HashMap args = (HashMap) call.arguments;
                List<byte[]> bytesList = (ArrayList) args.get("img");
                int imgWidth = (int) args.get("imgWidth") ;
                int imgHeight = (int) args.get("imgHeight") ;
                int size = (int) args.get("inputSize") ;
                bitmap = planes2Bitmap(bytesList, imgWidth, imgHeight);
                bitmap = centerCropResize(bitmap, size);
            } catch (Exception e) {
                Log.e("TorchMobile", "Error reading assets", e);
            }
            // preparing input tensor
            final Tensor inputTensor = TensorImageUtils.bitmapToFloat32Tensor(bitmap,
                    TensorImageUtils.TORCHVISION_NORM_MEAN_RGB, TensorImageUtils.TORCHVISION_NORM_STD_RGB);
            
            // running the model
            final Tensor outputTensor = module.forward(IValue.from(inputTensor)).toTensor();
            
            // getting tensor content as java array of floats
            final float[] scores = outputTensor.getDataAsFloatArray();
            
            //serialize result
            Gson gson = new Gson();
            String scoresJson = gson.toJson(scores);
            
            result.success(scoresJson);
        } else {
            result.notImplemented();
        }
    }
}