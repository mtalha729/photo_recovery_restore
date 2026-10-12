import 'package:flutter/material.dart';

enum RecoverySourceIntent {
  cameraGallery,
  messaging,
  screenshotsDownloads,
  scopedFolders;

  String get title => switch (this) {
    cameraGallery => 'Camera & Gallery',
    messaging => 'Messaging',
    screenshotsDownloads => 'Screenshots & Downloads',
    scopedFolders => 'SD Card & Other Folders',
  };

  String get description => switch (this) {
    cameraGallery => 'Photos captured by your camera or saved to your gallery.',
    messaging => 'Images from supported messaging and shared-media locations.',
    screenshotsDownloads =>
      'Screenshots and images saved from apps or the web.',
    scopedFolders => 'Choose an authorized SD card or another folder.',
  };

  String get semanticLabel => 'Recover from $title';

  IconData get icon => switch (this) {
    cameraGallery => Icons.photo_camera_outlined,
    messaging => Icons.forum_outlined,
    screenshotsDownloads => Icons.download_for_offline_outlined,
    scopedFolders => Icons.folder_open_outlined,
  };

  String get capabilityMessage => switch (this) {
    cameraGallery =>
      'Camera and Gallery scanning will begin from the next recovery step.',
    messaging =>
      'Messaging media scanning will begin from the next recovery step.',
    screenshotsDownloads =>
      'You will choose Screenshots or Downloads in the next recovery step.',
    scopedFolders => 'Folder authorization and selection will begin from the next recovery step.',
  };
}
