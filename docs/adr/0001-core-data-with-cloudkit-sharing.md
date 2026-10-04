# 1. Core Data with NSPersistentCloudKitContainer, not SwiftData

Date: 2026-10-04 · Status: accepted (pending the two-account device test below)

## Context

HomeCrew has no server. A family's data must be visible and editable from several Apple accounts (two parents, grandparents, a nanny), work offline, and sync when the network returns. That means CloudKit sharing: the owner's records live in their private database and are exposed to others through a `CKShare`, which participants see in their shared database.

## Decision

Use Core Data with `NSPersistentCloudKitContainer`, with two stores on one model:

- `private.sqlite` mirrored to the private CloudKit database (what this account owns);
- `shared.sqlite` mirrored to the shared database (what others shared with this account).

Sharing uses `container.share(_:to:)`, `UICloudSharingController`, and `acceptShareInvitations(from:into:)` from the scene delegate.

## Why not SwiftData

SwiftData's CloudKit sync only mirrors the private database. It has no API to create a `CKShare` or to read a shared database, so the core requirement of the app (a family shared between accounts) cannot be met with it today. Core Data supports this directly, and Apple's own sample for this (Sharing Core Data objects between iCloud users) uses this exact setup.

## Consequences

- The model is defined in code (`HomeCrewModel`) and must stay CloudKit compatible: every attribute optional or defaulted, no unique constraints, relationships optional with inverses. A unit test enforces this.
- Persistent history tracking and remote change notifications are on, so offline edits merge on reconnect.
- The CloudKit schema must be deployed to production in the CloudKit console before TestFlight (ticket 20).
- If SwiftData gains shared database support later, migrating means re-implementing the stack; the model stays the same.

## How to verify on devices (acceptance for ticket 2)

Needs a paid Apple Developer account, the iCloud container `iCloud.com.dmsilva.homecrew` created for the team, and two devices (or a device and a simulator) signed in to different Apple accounts.

1. Account A: Família tab, "Criar família", then the share button, invite account B.
2. Account B: open the invitation link; the family appears.
3. Account B: rename the family. Account A sees the new name.
4. Account B in airplane mode: rename again; turn the network back on; account A sees it.
