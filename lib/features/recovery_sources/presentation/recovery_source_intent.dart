import 'package:flutter/material.dart';

enum RecoverySourceIntent {
  cameraGallery,
  messaging,
  screenshotsDownloads,
  sdCard;

  String get title => switch (this) {
    cameraGallery => 'Camera & Gallery',
    messaging => 'Messaging',
    screenshotsDownloads => 'Screenshots & Downloads',
    sdCard => 'SD Card',
  };

  String get description => switch (this) {
    cameraGallery => 'Photos captured by your camera or saved to your gallery.',
    messaging => 'Images from supported messaging and shared-media locations.',
    screenshotsDownloads =>
      'Screenshots and images saved from apps or the web.',
    sdCard => 'Photos on removable storage, when available.',
  };

  String get semanticLabel => 'Recover from $title';

  IconData get icon => switch (this) {
    cameraGallery => Icons.photo_camera_outlined,
    messaging => Icons.forum_outlined,
    screenshotsDownloads => Icons.download_for_offline_outlined,
    sdCard => Icons.sd_card_outlined,
  };

  String get capabilityMessage => switch (this) {
    cameraGallery =>
      'Camera and Gallery scanning will begin from the next recovery step.',
    messaging =>
      'Messaging media scanning will begin from the next recovery step.',
    screenshotsDownloads =>
      'You will choose Screenshots or Downloads in the next recovery step.',
    sdCard => 'SD card recovery will begin from the next recovery step.',
  };
}
