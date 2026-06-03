# BillGuard MD

A medical billing code lookup app for iOS that helps patients understand their medical bills.

## Features

- **Search Medical Codes**: Look up CPT, ICD-10, ICD-10-PCS, and HCPCS codes
- **Plain English Descriptions**: Understand what procedures and diagnoses mean
- **Price Transparency**: See typical price ranges for procedures
- **Camera Scanner**: Scan codes directly from bills and documents
- **Favorites**: Save frequently referenced codes
- **Offline Support**: Works without internet connection

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 6.0

## Installation

1. Open `BillGuard.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Build and run on your device or simulator

## Database

The app includes 421 medical codes:
- 44 CPT codes (procedures)
- 16 ICD-10 codes (diagnoses)
- 355 ICD-10-PCS codes (inpatient procedures)
- 6 HCPCS codes (supplies/services)

## Architecture

- **SwiftUI** for the user interface
- **Swift 6.0** with strict concurrency
- **VisionKit** for document scanning
- **CloudKit** ready for future sync features

## License

© 2025 BillGuard MD. All rights reserved.
