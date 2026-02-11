import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:bitemates/core/theme/app_theme.dart';

class ImageCropService {
  /// Crops an image file to a square with preset UI settings.
  static Future<CroppedFile?> cropImage({
    required String sourcePath,
    required BuildContext context,
  }) async {
    return await ImageCropper().cropImage(
      sourcePath: sourcePath,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Photo',
          toolbarColor: AppTheme.primaryColor,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.square,
          lockAspectRatio: true,
          hideBottomControls: false,
          activeControlsWidgetColor: AppTheme.primaryColor,
        ),
        IOSUiSettings(
          title: 'Crop Photo',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
          aspectRatioPickerButtonHidden: true,
          doneButtonTitle: 'Done',
          cancelButtonTitle: 'Cancel',
        ),
      ],
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      compressQuality: 85, // Consistent with ImagePicker quality suggestion
    );
  }
}
