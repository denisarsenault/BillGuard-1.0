# CloudKit Setup Checklist (iOS)

Pre-ship steps to make the private-database sync actually work. The code is in
`BillGuard/Services/PatientDataService.swift` (`CloudKitSync` + per-collection
sync) and `BillGuard/Services/LocationReminderService.swift` (`FollowUpStore`).

Everything is **best-effort**: without an iCloud account or before these steps,
the app runs normally from its UserDefaults cache — sync just no-ops.

## Container & entitlement

- Container: **`iCloud.com.billguard.BillGuard`** (private database).
- Entitlement already in `BillGuard/BillGuard.entitlements` (iCloud + CloudKit).
- A build must be **signed with the real team** (not the ad-hoc "Sign to Run
  Locally" / `CODE_SIGNING_ALLOWED=NO` CLI build) for the entitlement to be
  provisioned and sync to function.

## Record types

All live in the **private** database.

| Record type | Shape | recordName |
|---|---|---|
| `FollowUpTask` | field-based (kind, title, providerName, providerId, createdAt, dueDate, isCompleted, completedAt, note) | `<task.id>` |
| `Patient` | JSON blob (`payload: Data`, `updatedAt: Date`) | `patient_<id>` |
| `Claim` | JSON blob | `claim_<id>` |
| `InsurancePolicy` | JSON blob | `policy_<id>` |
| `InsuranceCarrier` | JSON blob | `carrier_<id>` |
| `PaymentMethod` | JSON blob | `payment_<id>` |
| `Provider` | JSON blob | `provider_<id>` |
| `Visit` | JSON blob | `visit_<id>` |
| `ScannedDocument` | JSON blob | `document_<id>` |

The schema auto-creates in the **Development** environment the first time each
record type is saved. Conflict resolution is last-write-wins by `updatedAt`
(blob types) / completion-sticky (`FollowUpTask`), with force-overwrite saves
(`CKModifyRecordsOperation` + `.allKeys`).

## ✅ Dashboard checklist

In the [CloudKit Dashboard](https://icloud.developer.apple.com/) for the
container:

1. **Mark `recordName` Queryable** on **every** record type above (all 9). The
   pull uses a `TRUEPREDICATE` query (`NSPredicate(value: true)`), which fails
   until the system `recordName` field is indexed as Queryable. Without this,
   records save but never come back down to other devices.
2. Confirm each record type has the expected fields after a first save
   (`payload` + `updatedAt`, or the `FollowUpTask` fields).
3. **Promote the schema Development → Production** before the App Store build —
   production uses a separate, frozen schema.

## Testing real sync

- Use a **provisioned signed build from Xcode** (your team), on a device or
  simulator **signed into iCloud**.
- Sign two devices/simulators into the **same Apple ID**.
- Create a patient / scan a bill / mint a follow-up on device A; bring device B
  to the foreground → it pulls and merges on `scenePhase == .active` and on
  launch.

## Known limitations / follow-ups

- **Large scanned documents** can exceed CloudKit's ~1 MB per-record limit; those
  blob saves fail silently and the document stays local. If `ScannedDocument`
  starts embedding image data, move the image to a **`CKAsset`** instead of the
  `payload` field.
- **Cross-device deletes** rely on explicit delete calls while online; there's no
  tombstone/subscription, so a delete made entirely offline may not propagate.
  A `CKDatabaseSubscription` + change tokens would make sync push-based and
  handle this.
- Sync pulls on launch/foreground (no silent push notifications yet).
