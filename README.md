# ObjectCapture Companion — Production-Ready (iOS + macOS)

## Overview

ObjectCapture Companion is a two-part toolset for creating 3D models from real-world objects using Apple's Object Capture technology. The iOS app captures photos and generates a quick, on-device preview. The macOS app receives capture sets and reconstructs high-quality 3D models.

* **iOS app (`CapturePreview`)**: Guided object capture, `.reduced` detail preview reconstruction, send capture set to macOS via MultipeerConnectivity or AirDrop.
* **macOS app (`ReconstructHQ`)**: Receives zipped capture set, unzips, reconstructs at Medium/Full/RAW quality, exports USDZ or OBJ (+MTL + textures).

## Features

* Unified stage-folder ownership between SwiftUI and capture view controller.
* Background file I/O for image saves.
* Progress indicators and cancellation for both preview and HQ reconstruction.
* Disk space checks before starting reconstruction.
* Temp file cleanup after transfers.
* Streaming ZIP creation with bounded memory.
* Hardened unzip with error capture and file-type filtering.
* UX improvements: shot count, folder size, reveal-in-Finder, open-in-Preview, stop browsing/advertising when done.

## Requirements

* iOS 17+ (tested on iOS 18.6)
* macOS 13+ (tested on macOS 15.4)
* SwiftUI, RealityKit, MultipeerConnectivity frameworks
* No third-party dependencies

## Folder Structure

```
/
├── iOS/         # All iOS app source files
├── macOS/       # All macOS app source files
└── README.md    # This file
```

## How to Build & Run

1. Open the Xcode project.
2. Build the iOS target and deploy to a compatible iPhone or iPad.
3. Build the macOS target and run locally.
4. On iOS, capture the object and preview it.
5. Transfer the capture set to macOS using MultipeerConnectivity or AirDrop.
6. On macOS, reconstruct at desired quality and export.

## QA Checklist

* [ ] Capture works with both walk-around and turntable modes.
* [ ] Preview reconstruction completes on device.
* [ ] MultipeerConnectivity transfer succeeds.
* [ ] AirDrop transfer succeeds.
* [ ] macOS reconstruction completes for Medium, Full, and RAW.
* [ ] OBJ exports include .mtl and textures.
* [ ] Cancel buttons halt reconstruction without crash.
* [ ] Temp files are cleaned up after use.
