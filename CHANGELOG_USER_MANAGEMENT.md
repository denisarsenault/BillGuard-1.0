# BillGuard MD - User & Patient Management Update

## Overview
This update adds user authentication, patient management, and a complete billing data model hierarchy.

## New Files to Add to Xcode Project

### Models (add to Models group)

1. **User.swift** - User model for authentication
   - Location: `BillGuard/Models/User.swift`

2. **Patient/** - Create new group "Patient" inside Models
   - `Patient.swift` - Patient model
   - `InsuranceInfo.swift` - Insurance information
   - `Visit.swift` - Medical visits
   - `Office.swift` - Medical offices/facilities
   - `Bill.swift` - Medical bills
   - `Invoice.swift` - Invoices with line items

### Services (add to Services group)

1. **UserManager.swift** - Handles authentication & UserDefaults
   - Location: `BillGuard/Services/UserManager.swift`

2. **PatientDataService.swift** - CloudKit private database operations
   - Location: `BillGuard/Services/PatientDataService.swift`

### Views

1. **Auth/** - Create new group "Auth" inside Views
   - `LoginView.swift` - User login screen
   - `RegistrationView.swift` - New user registration

2. **Patient/** - Create new group "Patient" inside Views
   - `PatientListView.swift` - Patient management

### Modified Files

1. **BillGuardApp.swift** - Updated with auth flow
2. **MainTabView.swift** - Added Bills & Profile tabs

## How to Add Files in Xcode

1. Open `BillGuard.xcodeproj` in Xcode
2. Right-click on the appropriate group (Models, Services, Views)
3. Select "Add Files to BillGuard..."
4. Navigate to the file location and select the file
5. Ensure "Copy items if needed" is unchecked (files are already in place)
6. Ensure "Add to targets: BillGuard" is checked
7. Click "Add"

## Data Model Hierarchy

```
User (UserDefaults + Keychain)
├── username
├── email
├── password (Keychain)
├── preferences
└── patientIds[]

Patient (CloudKit Private)
├── personalInfo
├── insuranceInfo
├── visits[]
│   ├── dateOfService
│   ├── visitType
│   ├── office
│   └── bills[]
│       ├── billNumber
│       ├── status
│       └── invoices[]
│           ├── patientInfo (snapshot)
│           ├── insuranceInfo (snapshot)
│           ├── lineItems[] (scannable codes)
│           │   ├── code
│           │   ├── codeType
│           │   ├── chargedAmount
│           │   ├── insurancePaid
│           │   └── patientResponsibility
│           └── balanceDue
```

## Authentication Flow

1. **First Launch**: Onboarding → Registration/Login → Main App
2. **Returning User**: Auto-login if previously authenticated
3. **Sign Out**: Returns to Login screen

## CloudKit Setup

Data is stored in the **private database** so only the authenticated user can see their data.

Update your CloudKit container identifier in:
- `CloudKitService.swift` - Line 16
- `PatientDataService.swift` - Line 30
- `BillGuard.entitlements`

## UserDefaults Keys Used

- `hasCompletedOnboarding` - Boolean
- `isLoggedIn` - Boolean
- `lastUsername` - String
- `selectedPatientId` - String
- `user_{username}` - Encoded User data
- `allUsernames` - Array of registered usernames

## Keychain

Passwords are stored securely in the iOS Keychain with:
- Service: `com.billguard.auth`
- Account: username (lowercase)

## New Tab Bar

1. **Search** - Medical code lookup
2. **Bills** - View/manage bills for selected patient
3. **Scan** - Camera scanner
4. **Saved** - Favorite codes
5. **Profile** - User info, patients, settings
