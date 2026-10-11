-- =====================================================================
-- SHOOTROOM — DATABASE SCHEMA
-- Naming: PascalCase throughout. Table names plural, column names singular.
-- Maps one-to-one onto EF Core entities: Client, User, UserAccess, Product…
-- MySQL 8.0+ · InnoDB · utf8mb4
-- Derived from shootroom-frd.md and shootroom-prd.md
--
-- MULTI-TENANCY
--   Single schema, shared tables, `ClientId` on every tenant-owned
--   row. Every tenant table carries an index leading with ClientId so
--   the tenant predicate is always sargable.
--
--   The application layer MUST apply the ClientId filter on every
--   query. In .NET Core this is a global query filter on the DbContext
--   (HasQueryFilter) driven by the resolved tenant, plus an integration
--   test that fails if any tenant entity lacks one. A missed filter is
--   a cross-tenant data leak, so it cannot be left to discipline.
--
-- CONVENTIONS
--   ids            CHAR(26) ULID — sortable, opaque, safe in URLs
--   money          DECIMAL(12,2) with an explicit currency column
--   Credits        signed INT; ledger holds deltas, never a mutated total
--   timestamps     DATETIME(3) UTC. CreatedAt / UpdatedAt everywhere
--   soft delete    DeletedAt NULL. Hard delete only on legal erasure
--   enums          MySQL ENUM where the set is owned by us and stable;
--                  lookup tables where the tenant can extend it
--   charset        utf8mb4 / utf8mb4_0900_ai_ci
-- =====================================================================

SET NAMES utf8mb4;
-- Off while creating: some tables reference tables defined later in this file
-- (SegmentModels -> Models). Re-enabled at the end.
SET FOREIGN_KEY_CHECKS = 0;

-- =====================================================================
-- 1. ACCOUNTS, MEMBERS, ACCESS                          FRD §2, §3
-- =====================================================================

CREATE TABLE Clients (
  Id                      CHAR(26)     NOT NULL,
  Name                    VARCHAR(200) NOT NULL,
  CountryCode             CHAR(2)      NOT NULL,
  CurrencyCode            CHAR(3)      NOT NULL DEFAULT 'INR',
  -- FRD §2.1 — gates every request before role is considered
  State                   ENUM('unactivated','trial','active','past_due',
                             'cancelled','suspended') NOT NULL DEFAULT 'unactivated',
  StateReason             VARCHAR(255) NULL,
  StateChangedAt          DATETIME(3)  NULL,
  TrialStartedAt          DATETIME(3)  NULL,
  TrialEndsAt             DATETIME(3)  NULL,
  TermsVersion            VARCHAR(40)  NULL,
  TermsAcceptedAt         DATETIME(3)  NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  DeletedAt               DATETIME(3)  NULL,
  PurgeAfter              DATETIME(3)  NULL,          -- FR-ACC-26, 30-day grace
  PRIMARY KEY (Id),
  KEY IX_Clients_State (State),
  KEY IX_Clients_PurgeAfter (PurgeAfter)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE Users (
  Id                      CHAR(26)     NOT NULL,
  Email                   VARCHAR(320) NOT NULL,
  EmailNormalised         VARCHAR(320) NOT NULL,      -- lowercased, for uniqueness
  PasswordHash            VARCHAR(255) NOT NULL,
  PasswordChangedAt       DATETIME(3)  NULL,
  FullName                VARCHAR(200) NOT NULL,
  AvatarUri               VARCHAR(500) NULL,
  EmailVerifiedAt         DATETIME(3)  NULL,
  LockedUntil             DATETIME(3)  NULL,          -- FR-ACC-15
  FailedLoginCount        SMALLINT     NOT NULL DEFAULT 0,
  LastLoginAt             DATETIME(3)  NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  DeletedAt               DATETIME(3)  NULL,
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Users_EmailNormalised (EmailNormalised)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- A user may belong to more than one Clients. Role lives on the link.
CREATE TABLE UserAccess (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  UserId                  CHAR(26)     NOT NULL,
  Role                    ENUM('owner','admin','producer','viewer') NOT NULL DEFAULT 'producer',
  CreditCapMonthly        INT          NULL,          -- FR-ROL-13, NULL = uncapped
  -- Stored rather than derived from Role, so promoting a Viewer is an explicit
  -- billing event and the history of what was charged stays readable.
  IsBillable              TINYINT(1)   NOT NULL DEFAULT 1,   -- Viewers false, all others true
  Status                  ENUM('active','revoked') NOT NULL DEFAULT 'active',
  InvitedBy               CHAR(26)     NULL,
  JoinedAt                DATETIME(3)  NULL,
  LastActiveAt            DATETIME(3)  NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_UserAccess_ClientIdUserId (ClientId, UserId),
  KEY IX_UserAccess_ClientIdRoleStatus (ClientId, Role, Status),
  KEY IX_UserAccess_ClientIdIsBillableStatus (ClientId, IsBillable, Status),   -- seat count
  CONSTRAINT FK_UserAccess_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id),
  CONSTRAINT FK_UserAccess_UserId FOREIGN KEY (UserId) REFERENCES Users(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- FR-ROL-05 (last owner cannot be removed) is enforced in application Code.
-- MySQL cannot express "at least one row matching a predicate" as a constraint.

CREATE TABLE Invitations (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  EmailNormalised         VARCHAR(320) NOT NULL,
  Role                    ENUM('owner','admin','producer','viewer') NOT NULL DEFAULT 'producer',
  TokenHash               CHAR(64)     NOT NULL,
  InvitedBy               CHAR(26)     NOT NULL,
  ExpiresAt               DATETIME(3)  NOT NULL,      -- FR-ROL-09, 7 days
  AcceptedAt              DATETIME(3)  NULL,
  RevokedAt               DATETIME(3)  NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Invitations_TokenHash (TokenHash),
  KEY IX_Invitations_ClientIdEmailNormalised (ClientId, EmailNormalised),
  CONSTRAINT FK_Invitations_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Activation, password reset OTP, Email change. One table, typed.
CREATE TABLE AuthTokens (
  Id                      CHAR(26)     NOT NULL,
  UserId                  CHAR(26)     NOT NULL,
  Kind                    ENUM('activation','password_reset_otp','email_change') NOT NULL,
  TokenHash               CHAR(64)     NOT NULL,      -- never store the raw value
  TargetEmail             VARCHAR(320) NULL,          -- email_change only
  Attempts                SMALLINT     NOT NULL DEFAULT 0,   -- FR-ACC-17, max 3
  ExpiresAt               DATETIME(3)  NOT NULL,
  ConsumedAt              DATETIME(3)  NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  KEY IX_AuthTokens_UserIdKindConsumedAt (UserId, Kind, ConsumedAt),
  KEY IX_AuthTokens_TokenHash (TokenHash),
  CONSTRAINT FK_AuthTokens_UserId FOREIGN KEY (UserId) REFERENCES Users(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE Sessions (
  Id                      CHAR(26)     NOT NULL,
  UserId                  CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NULL,          -- active tenant for this session
  RefreshTokenHash        CHAR(64)     NOT NULL,
  UserAgent               VARCHAR(400) NULL,
  IpAddress               VARBINARY(16) NULL,
  LocationLabel           VARCHAR(120) NULL,
  -- impersonation, FR-ROL-20
  ImpersonatedBy          CHAR(26)     NULL,
  ImpersonationReason     VARCHAR(400) NULL,
  ExpiresAt               DATETIME(3)  NOT NULL,
  RevokedAt               DATETIME(3)  NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  LastSeenAt              DATETIME(3)  NULL,
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Sessions_RefreshTokenHash (RefreshTokenHash),
  KEY IX_Sessions_UserIdRevokedAt (UserId, RevokedAt),
  CONSTRAINT FK_Sessions_UserId FOREIGN KEY (UserId) REFERENCES Users(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Internal staff. Deliberately a separate identity space — FRD §2.3.
CREATE TABLE StaffUsers (
  Id                      CHAR(26)     NOT NULL,
  Email                   VARCHAR(320) NOT NULL,
  FullName                VARCHAR(200) NOT NULL,
  Status                  ENUM('active','disabled') NOT NULL DEFAULT 'active',
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_StaffUsers_Email (Email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE StaffRoles (
  StaffUserId             CHAR(26)     NOT NULL,
  Role                    ENUM('support','platform_admin','studio_operator',
                             'library_reviewer','super_admin') NOT NULL,
  GrantedBy               CHAR(26)     NULL,
  GrantedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (StaffUserId, Role),           -- FR-ROL-22, roles are additive
  CONSTRAINT FK_StaffRoles_StaffUserId FOREIGN KEY (StaffUserId) REFERENCES StaffUsers(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 2. SETTINGS                                     FRD §7.2, §10
-- =====================================================================

CREATE TABLE ClientSettings (
  ClientId                CHAR(26)     NOT NULL,
  -- approval, FRD §7.1
  RequireApproval         TINYINT(1)   NOT NULL DEFAULT 0,
  -- disclosure, FRD §7.2
  WatermarkEnabled        TINYINT(1)   NOT NULL DEFAULT 0,
  WatermarkText           VARCHAR(200) NULL,       -- FR-DIS-02, never hard-coded
  WatermarkPosition       ENUM('top_left','top_right','bottom_left','bottom_right','centre')
                            NOT NULL DEFAULT 'bottom_right',
  WatermarkOpacity        DECIMAL(3,2) NOT NULL DEFAULT 0.70,
  DisclosureDecision      ENUM('pending','enabled','declined') NOT NULL DEFAULT 'pending',
  DisclosureDecidedBy     CHAR(26)     NULL,
  DisclosureDecidedAt     DATETIME(3)  NULL,
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (ClientId),
  CONSTRAINT FK_ClientSettings_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE NotificationPreferences (
  ClientId                CHAR(26)     NOT NULL,
  UserId                  CHAR(26)     NOT NULL,
  Category                ENUM('shoot_complete','shoot_failed','approval_requested',
                             'approval_decided','credit_warning','product_updates') NOT NULL,
  EmailEnabled            TINYINT(1)   NOT NULL DEFAULT 1,
  InAppEnabled            TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (ClientId, UserId, Category)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- Transactional mail is deliberately absent. FR-NTF-06: receipts, password
-- resets and activation cannot be disabled, so a row would imply a switch
-- that does not exist.
--
-- FR-NTF-08: absence of a row means "use the category default", defined in
-- code. Never read a missing row as off — that silently mutes a user.
--
-- InAppEnabled is stored from launch even though the in-app centre ships
-- behind Features:InAppNotifications (FRD §13.1). The column costs nothing
-- and avoids a migration when the flag is turned on.
--
-- FEATURE FLAGS ARE NOT IN THE DATABASE. They live in appsettings and
-- environment variables, global per environment. Per-client variation is
-- ClientEntitlements, not a flag.

-- =====================================================================
-- 3. BILLING AND CREDITS                          FRD §4, §9 · Stripe
-- =====================================================================
-- Stripe is the source of truth for money. These tables mirror it so the
-- Products can read Plans State, entitlements and history without a network
-- call, and so invoices survive a Provider change. Never compute money
-- here that Stripe has already computed.

CREATE TABLE Plans (
  Id                      CHAR(26)     NOT NULL,
  Code                    VARCHAR(40)  NOT NULL,      -- 'starter','studio','brand'
  Name                    VARCHAR(80)  NOT NULL,
  StripeProductId         VARCHAR(80)  NULL,
  MonthlyCredits          INT          NOT NULL,
  RolloverCapCredits      INT          NULL,        -- max carried into the next month.
                                                    -- NULL = uncapped. Usually a multiple of
                                                    -- MonthlyCredits, e.g. 2x
  MaxPauseDays            SMALLINT     NULL,        -- NULL falls back to the system default
  ProductLimit            INT          NULL,          -- NULL = unlimited
  StorageGb               INT          NULL,
  IncludedSeats           SMALLINT     NOT NULL DEFAULT 1,  -- billable seats in the price
  MaxPaidSeats            SMALLINT     NULL,                 -- cap on extras. NULL = uncapped
  ViewerLimit             SMALLINT     NOT NULL DEFAULT 10,  -- free, non-billable. Capped so an
                                                             -- account cannot invite 200 for free
  BookableModels          SMALLINT     NOT NULL DEFAULT 0,   -- FR-CAST-01
  IsPublic                TINYINT(1)   NOT NULL DEFAULT 1,
  SortOrder               SMALLINT     NOT NULL DEFAULT 0,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Plans_Code (Code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE PlanPrices (
  Id                      CHAR(26)     NOT NULL,
  PlanId                  CHAR(26)     NOT NULL,
  ItemType                ENUM('base','seat') NOT NULL DEFAULT 'base',  -- base plan fee, or the
                                                                       -- per-seat price above IncludedSeats
  StripePriceId           VARCHAR(80)  NOT NULL,
  CurrencyCode            CHAR(3)      NOT NULL,
  IntervalUnit            ENUM('month','year') NOT NULL,
  AmountMinor             INT          NOT NULL,      -- paise / cents
  IsActive                TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (Id),
  UNIQUE KEY UX_PlanPrices_StripePriceId (StripePriceId),
  KEY IX_PlanPrices_PlanIdItemTypeCurrencyCodeIntervalUnit (PlanId, ItemType, CurrencyCode, IntervalUnit, IsActive),
  CONSTRAINT FK_PlanPrices_PlanId FOREIGN KEY (PlanId) REFERENCES Plans(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE Subscriptions (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  PlanId                  CHAR(26)     NOT NULL,
  PlanPriceId             CHAR(26)     NOT NULL,
  StripeSubscriptionId    VARCHAR(80)  NOT NULL,
  -- StripeCustomerId deliberately absent: it lives on BillingProfiles. A client
  -- has one Stripe customer for life, including before and after any subscription.
  Status                  ENUM('trialing','active','past_due','paused',
                               'canceled','incomplete') NOT NULL,
  IntervalUnit            ENUM('month','year') NOT NULL,
  CurrentPeriodStart      DATETIME(3)  NOT NULL,
  CurrentPeriodEnd        DATETIME(3)  NOT NULL,
  -- seats: IncludedSeats come with the plan; PaidSeats are billed per seat
  -- through a second Stripe subscription item. Viewers never consume a seat.
  IncludedSeats           SMALLINT     NOT NULL DEFAULT 1,
  PaidSeats               SMALLINT     NOT NULL DEFAULT 0,
  StripeSeatItemId        VARCHAR(80)  NULL,
  -- FR-BIL-10a: annual is billed once, Credits release monthly
  NextCreditReleaseAt     DATETIME(3)  NULL,
  ReleasesRemaining       SMALLINT     NULL,       -- annual only; 12 at start, 0 at end
  -- pause: length capped by a system config value; the resume job reads PauseEndsAt
  PausedAt                DATETIME(3)  NULL,
  PauseEndsAt             DATETIME(3)  NULL,
  PauseDaysUsedThisYear   SMALLINT     NOT NULL DEFAULT 0,
  CancelAtPeriodEnd       TINYINT(1)   NOT NULL DEFAULT 0,
  CanceledAt              DATETIME(3)  NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Subscriptions_StripeSubscriptionId (StripeSubscriptionId),
  KEY IX_Subscriptions_ClientIdStatus (ClientId, Status),
  KEY IX_Subscriptions_StatusNextCreditReleaseAt (Status, NextCreditReleaseAt),  -- the release job
  KEY IX_Subscriptions_StatusPauseEndsAt (Status, PauseEndsAt),                 -- the resume job
  CONSTRAINT FK_Subscriptions_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id),
  CONSTRAINT FK_Subscriptions_PlanPriceId FOREIGN KEY (PlanPriceId) REFERENCES PlanPrices(Id),
  CONSTRAINT FK_Subscriptions_PlanId FOREIGN KEY (PlanId) REFERENCES Plans(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE CreditPacks (
  Id                      CHAR(26)     NOT NULL,
  Code                    VARCHAR(40)  NOT NULL,
  Credits                 INT          NOT NULL,
  StripePriceId           VARCHAR(80)  NOT NULL,
  CurrencyCode            CHAR(3)      NOT NULL,
  AmountMinor             INT          NOT NULL,
  IsActive                TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (Id),
  UNIQUE KEY UX_CreditPacks_Code (Code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- The ledger is the source of truth for the Balance. Append only.
-- Balance = SUM(Delta) WHERE ClientId = ? AND (ExpiresAt IS NULL OR ExpiresAt > NOW()).
-- CreditBalances below is a maintained cache, not an authority.
CREATE TABLE CreditLedger (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  UserAccessId            CHAR(26)     NULL,          -- who acted, FR-ROL-26
  EntryType               ENUM('trial_grant','plan_release','pack_purchase',
                             'run_reservation','run_commit','run_release',
                             'regeneration','admin_grant','admin_deduction',
                             'expiry','rollover') NOT NULL,
  Delta                   INT          NOT NULL,      -- signed
  BalanceAfter            INT          NOT NULL,      -- snapshot for statement rendering
  CreditSource            ENUM('trial','plan','pack','grant') NOT NULL,
  ExpiresAt               DATETIME(3)  NULL,          -- trial Credits, FR-CR-09
  RunId                   CHAR(26)     NULL,
  RunImageId              CHAR(26)     NULL,
  InvoiceId               CHAR(26)     NULL,
  Reason                  VARCHAR(400) NULL,          -- mandatory on admin entries, FR-ADM-02
  CreatedByStaffId        CHAR(26)     NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  KEY IX_CreditLedger_ClientIdCreatedAt (ClientId, CreatedAt),
  KEY IX_CreditLedger_RunId (RunId),
  KEY IX_CreditLedger_ClientIdExpiresAt (ClientId, ExpiresAt),
  KEY IX_CreditLedger_ClientIdUserAccessIdCreatedAt (ClientId, UserAccessId, CreatedAt),  -- credit caps
  CONSTRAINT FK_CreditLedger_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Cache. Rebuilt from CreditLedger; never written to directly by feature code.
--
-- KNOWN SCALING LIMIT — revisit before Phase 2 batch shoots
--   This is the hottest row in the schema. One run touches it ~26 times: one
--   reservation, one commit per delivered image, one release per failure.
--   Every write takes the optimistic Version check, so two writers on the same
--   ClientId serialise and the loser retries.
--
--   Fine at launch. Contention is per client, not global, and one client
--   cannot start enough concurrent runs to contend on their own row. Total
--   customer count does not make this worse.
--
--   It degrades when ONE client runs large batches in parallel, which is
--   exactly the shape of Phase 2 batch shoots. Symptoms: rising version-check
--   retries, slow run starts, timeouts on the reservation path.
--
--   FIX WHEN IT HAPPENS, in order of preference:
--     1. Batch the commits — one RunCommit per run on completion, or one per
--        batch of images, instead of one per image. ~26 writes becomes 2.
--        No new infrastructure, no display lag.
--     2. Coalesce a client's concurrent runs into a single reservation.
--     3. Only then consider sharding the balance into per-client buckets.
--
--   DO NOT make the reservation asynchronous. It is a CHECK, not a write:
--   "does this client have 24 credits" must be answered inside the same
--   transaction that takes them. Queue it and two runs both pass the check and
--   the client overdraws. Commits could in principle be queued, but the gain is
--   small and the displayed balance would lag reality. An in-memory broker is
--   doubly wrong — a restart loses queued movements, and nothing touching a
--   balance may be non-durable.
CREATE TABLE CreditBalances (
  ClientId                CHAR(26)     NOT NULL,
  Balance                 INT          NOT NULL DEFAULT 0,
  Reserved                INT          NOT NULL DEFAULT 0,   -- in-flight runs
  TrialBalance            INT          NOT NULL DEFAULT 0,   -- consumed first, FR-CR-13
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  Version                 INT          NOT NULL DEFAULT 0,   -- optimistic concurrency
  PRIMARY KEY (ClientId),
  CONSTRAINT FK_CreditBalances_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Mirrored from the payment provider, which raises the invoice, applies tax,
-- generates the PDF and collects. Nothing here is calculated locally.
--
-- RELATIONSHIP TO SubscriptionPeriods is many-to-one, not one-to-one:
--   · a period may have no invoice        — trial, paused, or not yet settled
--   · an invoice may have no period       — a credit pack purchase
--   · one invoice may cover two periods   — a mid-period upgrade settles both
--
-- REVENUE COMES FROM THIS TABLE, never from summing SubscriptionPeriods.
-- Summing periods double-counts upgrades and omits pack purchases entirely.
-- SubscriptionPeriods answers what they were subscribed to; Invoices answers
-- what was billed and collected.
--
-- PdfUri: the provider's hosted PDF is a signed, expiring URL. Either refresh
-- it on demand or copy the file into our own storage. The second is safer for
-- the same reason this table exists at all.
CREATE TABLE Invoices (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  StripeInvoiceId         VARCHAR(80)  NOT NULL,
  Number                  VARCHAR(40)  NOT NULL,
  Description             VARCHAR(255) NULL,
  CurrencyCode            CHAR(3)      NOT NULL,
  SubtotalMinor           INT          NOT NULL,
  TaxMinor                INT          NOT NULL DEFAULT 0,
  TotalMinor              INT          NOT NULL,
  Status                  ENUM('draft','open','paid','void','uncollectible') NOT NULL,
  IssuedAt                DATETIME(3)  NULL,
  PaidAt                  DATETIME(3)  NULL,
  PdfUri                  VARCHAR(500) NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Invoices_StripeInvoiceId (StripeInvoiceId),
  KEY IX_Invoices_ClientIdIssuedAt (ClientId, IssuedAt)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Who is billed and where. Separate from Clients because the brand name and
-- the registered entity are rarely the same — "Label Nine" may be billed as
-- "Nine Retail Private Limited" at a different address.
--
-- POPULATED FROM THE PROVIDER, NOT FROM OUR OWN FORM. Billing details are
-- collected on the provider's hosted checkout, so card data never touches our
-- servers and tax id validation is theirs. We receive the details on
-- checkout.session.completed, then fetch the customer object once to get the
-- full record. customer.updated keeps the mirror current afterwards.
--
-- No row exists until first checkout — no provider customer is created at
-- registration. Every read must handle its absence.
--
-- StripeCustomerId lives HERE and nowhere else. A client has one provider
-- customer for life, including before and after any subscription. On
-- Subscriptions it would duplicate across rows and orphan on cancellation.
--
-- CountryCode and StateRegion drive GST treatment: same-state is CGST+SGST,
-- inter-state is IGST. The provider calculates it, but from this data.
--
-- A mirror, like Invoices. If it disagrees with the provider, the provider
-- wins. Its value is availability and portability, not authority.
CREATE TABLE BillingProfiles (
  ClientId                CHAR(26)     NOT NULL,
  LegalName               VARCHAR(200) NULL,
  BillingEmail            VARCHAR(320) NULL,          -- FR-BIL-12
  AddressLine1            VARCHAR(200) NULL,
  AddressLine2            VARCHAR(200) NULL,
  City                    VARCHAR(120) NULL,
  StateRegion             VARCHAR(120) NULL,
  PostalCode              VARCHAR(20)  NULL,
  CountryCode             CHAR(2)      NULL,
  TaxIdType               VARCHAR(20)  NULL,          -- 'in_gst', 'eu_vat'
  TaxIdValue              VARCHAR(60)  NULL,
  StripeCustomerId        VARCHAR(80)  NULL,
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (ClientId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Provider webhooks. Idempotency is not optional — the provider retries on
-- timeout, slow response or network failure, so the same event arrives twice.
-- Processing invoice.paid twice would release the monthly credits twice.
--
-- THE PRIMARY KEY IS THE GUARANTEE. StripeEventId is the provider's own id, so
-- a duplicate delivery hits a constraint violation and stops there. Idempotency
-- is enforced by the database, not by application logic.
--
-- STORE FIRST, ACT SECOND. Insert the row, return 200 immediately, process
-- asynchronously. The provider times out at 20 seconds; processing inline
-- invites a retry while the first attempt is still running.
--
-- ClientId and StripeCustomerId are denormalised from the payload so that
-- "every provider event for this client" is a query rather than a JSON scan.
-- Both are nullable and legitimately so:
--   · price.updated is account-level and has no customer
--   · checkout.session.completed arrives BEFORE the billing profile exists,
--     so it resolves the client from the session metadata instead
-- Always put our own ClientId in the checkout session metadata, so an event
-- can be attributed even when the profile lookup fails.
CREATE TABLE StripeEvents (
  StripeEventId           VARCHAR(80)  NOT NULL,
  Type                    VARCHAR(80)  NOT NULL,
  ClientId                CHAR(26)     NULL,        -- resolved during processing
  StripeCustomerId        VARCHAR(80)  NULL,        -- extracted from the payload
  Payload                 JSON         NOT NULL,    -- kept so a fixed handler can replay
  Attempts                SMALLINT     NOT NULL DEFAULT 0,
  ProcessedAt             DATETIME(3)  NULL,        -- NULL means not yet handled
  Error                   TEXT         NULL,
  ReceivedAt              DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (StripeEventId),
  KEY IX_StripeEvents_ProcessedAtReceivedAt (ProcessedAt, ReceivedAt),   -- the worker queue
  KEY IX_StripeEvents_ClientIdReceivedAt (ClientId, ReceivedAt),         -- support lookups
  KEY IX_StripeEvents_StripeCustomerId (StripeCustomerId),
  KEY IX_StripeEvents_AttemptsProcessedAt (Attempts, ProcessedAt)        -- stuck events
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- No FK on ClientId: the event may arrive before the client is resolvable, and
-- a failed constraint must never reject a webhook the provider considers
-- delivered.
--
-- RETENTION. This table grows without bound and carries a full payload on every
-- row, so it becomes the largest in the schema. Clear Payload after 90 days but
-- keep the row — the id is the idempotency guard and must outlive the payload.
--
-- ALERTING. Attempts above a threshold with ProcessedAt still null means a
-- handler is failing repeatedly. That is a paying customer waiting on credits,
-- so it needs an alert rather than a row nobody reads.

-- One row per billing cycle. Subscriptions holds current state; this holds the
-- history. Monthly plans produce twelve rows a year, annual plans one. Answers
-- "what plan were they on in June" as an indexed lookup rather than by
-- replaying provider events.
CREATE TABLE SubscriptionPeriods (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  SubscriptionId          CHAR(26)     NOT NULL,
  PeriodStart             DATETIME(3)  NOT NULL,
  PeriodEnd               DATETIME(3)  NOT NULL,
  PlanId                  CHAR(26)     NOT NULL,    -- the plan as it was then
  PlanPriceId             CHAR(26)     NOT NULL,
  IntervalUnit            ENUM('month','year') NOT NULL,
  IncludedSeats           SMALLINT     NOT NULL DEFAULT 0,
  PaidSeats               SMALLINT     NOT NULL DEFAULT 0,
  PlanAmountMinor         INT          NOT NULL DEFAULT 0,
  SeatAmountMinor         INT          NOT NULL DEFAULT 0,
  TotalAmountMinor        INT          NOT NULL DEFAULT 0,
  CurrencyCode            CHAR(3)      NOT NULL,
  InvoiceId               CHAR(26)     NULL,
  ChangeReason            ENUM('new','renewal','upgrade','downgrade',
                               'seat_change','pause','resume','cancellation') NOT NULL,
  Status                  ENUM('active','completed','superseded') NOT NULL DEFAULT 'active',
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  KEY IX_SubscriptionPeriods_ClientIdPeriodStart (ClientId, PeriodStart),
  KEY IX_SubscriptionPeriods_SubscriptionIdPeriodStart (SubscriptionId, PeriodStart),
  CONSTRAINT FK_SubscriptionPeriods_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id),
  CONSTRAINT FK_SubscriptionPeriods_SubscriptionId FOREIGN KEY (SubscriptionId) REFERENCES Subscriptions(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- An upgrade mid-period closes the current row as 'superseded' and opens a new
-- one. Rows are never edited, so the record of what was charged survives.

-- One row per client per month, written by a job on the first of the month.
-- ClientUsage is a live counter and answers only "today". This answers "June",
-- without aggregating CreditLedger or RunImages, both of which grow unbounded.
CREATE TABLE UsageSnapshots (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  PeriodYear              SMALLINT     NOT NULL,
  PeriodMonth             SMALLINT     NOT NULL,
  CreditsOpening          INT          NOT NULL DEFAULT 0,
  CreditsGranted          INT          NOT NULL DEFAULT 0,
  CreditsPurchased        INT          NOT NULL DEFAULT 0,
  CreditsConsumed         INT          NOT NULL DEFAULT 0,
  CreditsExpired          INT          NOT NULL DEFAULT 0,
  CreditsRolledOver       INT          NOT NULL DEFAULT 0,
  CreditsClosing          INT          NOT NULL DEFAULT 0,
  RunsStarted             INT          NOT NULL DEFAULT 0,
  RunsCompleted           INT          NOT NULL DEFAULT 0,
  ImagesDelivered         INT          NOT NULL DEFAULT 0,
  ProductsAdded           INT          NOT NULL DEFAULT 0,
  StorageBytesEnd         BIGINT       NOT NULL DEFAULT 0,
  BillableSeats           SMALLINT     NOT NULL DEFAULT 0,
  ViewerSeats             SMALLINT     NOT NULL DEFAULT 0,
  ActiveUsers             SMALLINT     NOT NULL DEFAULT 0,
  CapturedAt              DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_UsageSnapshots_ClientIdPeriodYearPeriodMonth (ClientId, PeriodYear, PeriodMonth),
  KEY IX_UsageSnapshots_PeriodYearPeriodMonth (PeriodYear, PeriodMonth),
  CONSTRAINT FK_UsageSnapshots_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- Opening + Granted + Purchased - Consumed - Expired = Closing. If that does not
-- balance, the ledger and the cache have drifted, so the snapshot job doubles as
-- a reconciliation check.

-- =====================================================================
-- 4a. CATALOGUE TAXONOMY                                    FRD §5.5
-- =====================================================================
-- SEGMENTS ARE A SAFETY BOUNDARY, NOT A MARKETING LABEL.
--
--   Segment      Menswear, Womenswear, Swimwear, Nightwear.
--                Global, Super admin only, granted per client. Controls both
--                which products a client may shoot AND which models may be
--                paired with them. This is the mechanism that makes an
--                offensive garment-and-model combination impossible.
--   Category     Shirts, Jeans, Dresses. Descriptive, for filtering. Carries
--                PlateType as a quiet system field the user never picks.
--   SubCategory  Optional third level, only where it does real work.
--
-- PlateType (T/B/F) is a separate axis from segment and answers a different
-- question. Plate type says which half of the body the try-on replaces.
-- Segment says what kind of shoot it is. A bridal lehenga and a fast-fashion
-- maxi dress are both FullWear — same plate, entirely different casting.
--
-- OWNERSHIP. These four tables are maintained by Super admin only. No
-- client role may create, rename or reparent any level. That is what
-- prevents a client naming their way around an approval gate.
--
-- Any level may carry RequiresApproval. Anything not flagged is enabled
-- for every client on registration. Anything flagged stays off until a
-- Super admin grants it, which is how a newly introduced category is
-- held back until it has been tested.

CREATE TABLE Segments (
  Id                      CHAR(26)     NOT NULL,
  Code                    VARCHAR(40)  NOT NULL,
  Name                    VARCHAR(120) NOT NULL,
  RequiresApproval        TINYINT(1)   NOT NULL DEFAULT 0,
  -- A sensitive segment additionally requires an explicit model pairing.
  -- Swimwear and Nightwear are sensitive; Menswear and Womenswear are not.
  IsSensitive             TINYINT(1)   NOT NULL DEFAULT 0,
  RequiresModelPairing    TINYINT(1)   NOT NULL DEFAULT 0,
  IsActive                TINYINT(1)   NOT NULL DEFAULT 1,
  SortOrder               SMALLINT     NOT NULL DEFAULT 0,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Segments_Code (Code),
  KEY IX_Segments_IsActiveRequiresApproval (IsActive, RequiresApproval)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE Categories (
  Id                      CHAR(26)     NOT NULL,
  Code                    VARCHAR(40)  NOT NULL,
  Name                    VARCHAR(120) NOT NULL,
  PlateType               ENUM('T','B','F') NOT NULL,   -- the whole reason this level exists
  RequiresApproval        TINYINT(1)   NOT NULL DEFAULT 0,
  IsActive                TINYINT(1)   NOT NULL DEFAULT 1,
  SortOrder               SMALLINT     NOT NULL DEFAULT 0,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Categories_Code (Code),
  KEY IX_Categories_IsActive (IsActive)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- SUB-CATEGORIES SHAPE THE PLATE. They are not descriptive.
--
-- Established by testing: a crop top mapped onto a plate wearing a full-length
-- tank leaves the tank visible below the crop. A knee-length skirt onto
-- full-length trousers leaves the trouser legs showing. The base garment must
-- end where the real garment ends.
--
-- BaseCut is therefore the real key to plate selection, not PlateType. Many
-- sub-categories share a cut — what matters is where the garment ends, not
-- what it is called.
CREATE TABLE SubCategories (
  Id                      CHAR(26)     NOT NULL,
  CategoryId              CHAR(26)     NOT NULL,
  Code                    VARCHAR(40)  NOT NULL,
  Name                    VARCHAR(120) NOT NULL,
  BaseCut                 ENUM('top_standard','top_cropped','top_long',
                               'bottom_full','bottom_knee','bottom_short',
                               'full') NOT NULL,
  -- Some cuts apply to one gender presentation only. Crop tops are feminine,
  -- so no masculine model needs a cropped plate. Trims the library and
  -- prevents a nonsensical plate being generated at all.
  GenderApplicability     ENUM('any','feminine','masculine') NOT NULL DEFAULT 'any',
  RequiresApproval        TINYINT(1)   NOT NULL DEFAULT 0,
  IsActive                TINYINT(1)   NOT NULL DEFAULT 1,
  SortOrder               SMALLINT     NOT NULL DEFAULT 0,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_SubCategories_Code (Code),
  KEY IX_SubCategories_CategoryIdIsActive (CategoryId, IsActive),
  KEY IX_SubCategories_BaseCutIsActive (BaseCut, IsActive),
  CONSTRAINT FK_SubCategories_CategoryId FOREIGN KEY (CategoryId) REFERENCES Categories(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Which models may be used in which segment. THE PAIRING IS THE CONTROL.
--
-- Granting a client a segment is not sufficient. A client permitted to shoot
-- Swimwear must still only be offered models explicitly cleared for Swimwear.
-- The unsafe outcome is never a segment on its own or a model on its own — it
-- is a combination. This table is where that combination is authorised.
--
-- REVIEW WORKFLOW. Enabling a new segment creates a pending row for every
-- model in the library. A reviewer works the queue and sets each to approved
-- or rejected. Only 'approved' is ever visible to a client.
--
-- THE FILTER READS Status = 'approved' AND RevokedAt IS NULL. Nothing else.
-- Pending, rejected and revoked are all equally invisible. Never write a
-- filter that treats a missing row, or any other status, as permitted.
CREATE TABLE SegmentModels (
  SegmentId               CHAR(26)     NOT NULL,
  ModelId                 CHAR(26)     NOT NULL,
  Status                  ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  DecidedByStaffId        CHAR(26)     NULL,        -- never automatic, never a migration
  DecidedAt               DATETIME(3)  NULL,
  DecisionNotes           VARCHAR(600) NULL,        -- the basis, kept for rejections too
  -- Revocation preserves the history. A revoked row is treated as absent by
  -- the filter, but who granted it and who withdrew it both survive, which is
  -- what an incident review needs.
  RevokedByStaffId        CHAR(26)     NULL,
  RevokedAt               DATETIME(3)  NULL,
  RevocationReason        VARCHAR(600) NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (SegmentId, ModelId),
  KEY IX_SegmentModels_SegmentIdStatus (SegmentId, Status, RevokedAt),   -- the browse filter
  KEY IX_SegmentModels_StatusSegmentId (Status, SegmentId),              -- the review queue
  KEY IX_SegmentModels_ModelId (ModelId),
  CONSTRAINT FK_SegmentModels_SegmentId FOREIGN KEY (SegmentId) REFERENCES Segments(Id),
  CONSTRAINT FK_SegmentModels_ModelId FOREIGN KEY (ModelId) REFERENCES Models(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- One row per approval-gated item a client has been granted, or has asked
-- for. Absence of a row means not granted. Items with RequiresApproval = 0
-- are available to everyone and are never listed here.
CREATE TABLE ClientEntitlements (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  ScopeType               ENUM('segment','category','subcategory') NOT NULL,
  ScopeId                 CHAR(26)     NOT NULL,
  Status                  ENUM('requested','granted','revoked') NOT NULL DEFAULT 'requested',
  RequestedBy             CHAR(26)     NULL,        -- UserAccess
  RequestedAt             DATETIME(3)  NULL,
  DecidedByStaffId        CHAR(26)     NULL,
  DecidedAt               DATETIME(3)  NULL,
  Notes                   VARCHAR(600) NULL,        -- eligibility basis, kept for audit
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_ClientEntitlements_ClientIdScopeTypeScopeId (ClientId, ScopeType, ScopeId),
  KEY IX_ClientEntitlements_ClientIdStatus (ClientId, Status),
  KEY IX_ClientEntitlements_StatusCreatedAt (Status, CreatedAt),   -- the approval queue
  CONSTRAINT FK_ClientEntitlements_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- RESOLUTION RULE. A client may use a sub-category only when all three of
-- its segment, category and sub-category are permitted. A level is
-- permitted when RequiresApproval = 0, or when a granted entitlement row
-- exists for it. Granting a segment does not imply its sub-categories —
-- each flagged level is granted on its own.

-- =====================================================================
-- 4. MASTER DATA                                            FRD §5.3
-- =====================================================================
-- Tenant-owned lookups. Values in use are archived, never deleted
-- (FR-MD-02), so every reference is by Id and nothing dangles.

-- CLIENT-OWNED MASTER DATA. Brands, Colours, Fabrics, Seasons, SizeSets all
-- share one shape: tenant-scoped, unique name per client, archived rather than
-- deleted when in use (FR-MD-02), editable by Owner and Admin only.
--
-- All five carry CreatedBy / UpdatedBy / ArchivedBy referencing UserAccess.
-- A rename propagates everywhere the value is referenced, so knowing who
-- changed "Ivory" to "Off-white" across four hundred products matters. The
-- audit log holds the full history; these columns answer the common question
-- without a join.
CREATE TABLE Brands (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  Name                    VARCHAR(120) NOT NULL,
  Code                    VARCHAR(20)  NULL,
  Status                  ENUM('active','archived') NOT NULL DEFAULT 'active',
  ArchivedBy              CHAR(26)     NULL,
  ArchivedAt              DATETIME(3)  NULL,
  CreatedBy               CHAR(26)     NULL,        -- UserAccess of the author
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedBy               CHAR(26)     NULL,        -- UserAccess of the last editor
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Brands_ClientIdName (ClientId, Name),
  KEY IX_Brands_ClientIdStatus (ClientId, Status),
  CONSTRAINT FK_Brands_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE Colours (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  Name                    VARCHAR(120) NOT NULL,
  Hex                     CHAR(7)      NULL,
  Status                  ENUM('active','archived') NOT NULL DEFAULT 'active',
  ArchivedBy              CHAR(26)     NULL,
  ArchivedAt              DATETIME(3)  NULL,
  CreatedBy               CHAR(26)     NULL,        -- UserAccess of the author
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedBy               CHAR(26)     NULL,        -- UserAccess of the last editor
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Colours_ClientIdName (ClientId, Name),
  KEY IX_Colours_ClientIdStatus (ClientId, Status),
  CONSTRAINT FK_Colours_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE Fabrics (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  Name                    VARCHAR(120) NOT NULL,
  Notes                   VARCHAR(255) NULL,
  IsSheer                 TINYINT(1)   NOT NULL DEFAULT 0,    -- FR-CAT-03
  Status                  ENUM('active','archived') NOT NULL DEFAULT 'active',
  ArchivedBy              CHAR(26)     NULL,
  ArchivedAt              DATETIME(3)  NULL,
  CreatedBy               CHAR(26)     NULL,        -- UserAccess of the author
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedBy               CHAR(26)     NULL,        -- UserAccess of the last editor
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Fabrics_ClientIdName (ClientId, Name),
  KEY IX_Fabrics_ClientIdStatus (ClientId, Status),
  CONSTRAINT FK_Fabrics_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE Seasons (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  Name                    VARCHAR(120) NOT NULL,
  Year                    SMALLINT     NULL,
  Status                  ENUM('active','archived') NOT NULL DEFAULT 'active',
  ArchivedBy              CHAR(26)     NULL,
  ArchivedAt              DATETIME(3)  NULL,
  CreatedBy               CHAR(26)     NULL,        -- UserAccess of the author
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedBy               CHAR(26)     NULL,        -- UserAccess of the last editor
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Seasons_ClientIdNameYear (ClientId, Name, Year),
  KEY IX_Seasons_ClientIdStatus (ClientId, Status),
  CONSTRAINT FK_Seasons_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE SizeSets (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  Name                    VARCHAR(120) NOT NULL,
  Sizes                   JSON         NOT NULL,              -- ["XS","S","M","L"]
  Status                  ENUM('active','archived') NOT NULL DEFAULT 'active',
  ArchivedBy              CHAR(26)     NULL,
  ArchivedAt              DATETIME(3)  NULL,
  CreatedBy               CHAR(26)     NULL,        -- UserAccess of the author
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedBy               CHAR(26)     NULL,        -- UserAccess of the last editor
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_SizeSets_ClientIdName (ClientId, Name),
  KEY IX_SizeSets_ClientIdStatus (ClientId, Status),
  CONSTRAINT FK_SizeSets_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 5. PRODUCTS AND IMAGES                              FRD §5, §5.4
-- =====================================================================

CREATE TABLE Products (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  Name                    VARCHAR(200) NOT NULL,
  Sku                     VARCHAR(80)  NOT NULL,    -- the STYLE code. Colour-level SKUs live on
                                                    -- ProductVariants
  ExternalId              VARCHAR(120) NULL,
  SegmentId               CHAR(26)     NOT NULL,    -- Menswear, Swimwear, Nightwear…
                                                    -- NOT NULL: a product with no segment cannot
                                                    -- be safety-checked, so it cannot be shot
  Gender                  ENUM('womenswear','menswear','unisex') NOT NULL,
                                                    -- narrows the casting at model browse;
                                                    -- must be compatible with
                                                    -- SubCategories.GenderApplicability
  CategoryId              CHAR(26)     NOT NULL,    -- TopWear, BottomWear, FullWear
  SubCategoryId           CHAR(26)     NOT NULL,    -- Shirts, Jeans, Crop tops
  BaseCut                 ENUM('top_standard','top_cropped','top_long',
                               'bottom_full','bottom_knee','bottom_short',
                               'full') NOT NULL,      -- snapshot from SubCategories
  PlateType               ENUM('T','B','F') NOT NULL,  -- snapshot of Categories.PlateType at
                                                       -- creation, so re-typing a category never
                                                       -- changes the plate type of past products
  BrandId                 CHAR(26)     NULL,
  FabricId                CHAR(26)     NULL,
  SeasonId                CHAR(26)     NULL,
  SizeSetId               CHAR(26)     NULL,
  Description             TEXT         NULL,
  -- Fit is the only descriptive attribute kept as a column. It is genuinely
  -- single-valued, applies to every garment, and changes how the try-on drapes.
  -- Sleeve length, neckline, hem, garment length and pattern were columns and
  -- are now tags: they are multi-valued (a sleeve can be half AND puff AND
  -- raglan), mostly null on any given garment, and adding a new one should be
  -- data entry rather than a migration.
  Fit                     ENUM('slim','regular','relaxed','oversized') NULL,
  PriceMinor              INT          NULL,
  CurrencyCode            CHAR(3)      NULL,
  Status                  ENUM('draft','active','archived') NOT NULL DEFAULT 'draft',
  -- denormalised roll-up across all colourways, for list views and the dashboard;
  -- maintained on Runs completion
  ShootCount              INT          NOT NULL DEFAULT 0,
  LastShotAt              DATETIME(3)  NULL,
  IsStale                 TINYINT(1)   NOT NULL DEFAULT 0,       -- FR-IMG-13
  CreatedBy               CHAR(26)     NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  DeletedAt               DATETIME(3)  NULL,
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Products_ClientIdSku (ClientId, Sku),
  KEY IX_Products_ClientIdStatusCategoryId (ClientId, Status, CategoryId),
  KEY IX_Products_ClientIdShootCountStatus (ClientId, ShootCount, Status),        -- "waiting to shoot"
  KEY IX_Products_ClientIdIsStale (ClientId, IsStale),
  KEY IX_Products_ClientIdName (ClientId, Name),
  CONSTRAINT FK_Products_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id),
  CONSTRAINT FK_Products_SegmentId FOREIGN KEY (SegmentId) REFERENCES Segments(Id),
  CONSTRAINT FK_Products_CategoryId FOREIGN KEY (CategoryId) REFERENCES Categories(Id),
  CONSTRAINT FK_Products_SubCategoryId FOREIGN KEY (SubCategoryId) REFERENCES SubCategories(Id),
  CONSTRAINT FK_Products_BrandId FOREIGN KEY (BrandId) REFERENCES Brands(Id),
  CONSTRAINT FK_Products_FabricId FOREIGN KEY (FabricId) REFERENCES Fabrics(Id),
  CONSTRAINT FK_Products_SeasonId FOREIGN KEY (SeasonId) REFERENCES Seasons(Id),
  CONSTRAINT FK_Products_SizeSetId FOREIGN KEY (SizeSetId) REFERENCES SizeSets(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Colourways. Products is the STYLE; each colour it comes in is one row here.
-- Every product has at least one variant: a single-colour product is a product
-- with one variant, so nothing downstream needs a "no variants" special case.
-- Variants are by COLOUR only — sizes need no imagery of their own and stay on
-- Products.SizeSetId. Everything that decides the plate (segment, gender,
-- sub-category, base cut) is on the style, so all colours shoot on the same
-- plates and the same eligible models.
CREATE TABLE ProductVariants (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  ProductId               CHAR(26)     NOT NULL,
  ColourId                CHAR(26)     NOT NULL,
  Sku                     VARCHAR(80)  NULL,       -- optional colour SKU. NULL = the style code
                                                   -- identifies it (one SKU per style catalogues).
                                                   -- NULLs do not collide in the unique key
  PriceMinor              INT          NULL,       -- overrides Products.PriceMinor when set
  SortOrder               SMALLINT     NOT NULL DEFAULT 0,
  Status                  ENUM('active','archived') NOT NULL DEFAULT 'active',
  ShootCount              INT          NOT NULL DEFAULT 0,
  LastShotAt              DATETIME(3)  NULL,
  IsStale                 TINYINT(1)   NOT NULL DEFAULT 0,   -- FR-IMG-13, per colour
  CreatedBy               CHAR(26)     NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  DeletedAt               DATETIME(3)  NULL,
  PRIMARY KEY (Id),
  UNIQUE KEY UX_ProductVariants_ProductIdColourId (ProductId, ColourId),   -- a colour once per style
  UNIQUE KEY UX_ProductVariants_ClientIdSku (ClientId, Sku),
  KEY IX_ProductVariants_ClientIdProductId (ClientId, ProductId),
  KEY IX_ProductVariants_ClientIdColourId (ClientId, ColourId),
  CONSTRAINT FK_ProductVariants_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id),
  CONSTRAINT FK_ProductVariants_ProductId FOREIGN KEY (ProductId) REFERENCES Products(Id),
  CONSTRAINT FK_ProductVariants_ColourId FOREIGN KEY (ColourId) REFERENCES Colours(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- GLOBAL AND SUPER-ADMIN OWNED, not client master data.
--
-- Tags feed the generation prompt. Once a tag is mapped to a sub-category, the
-- prompt logic for that garment is fixed against it — so the vocabulary cannot
-- be something each client edits, or the same garment would generate
-- differently for two customers and no prompt could be tuned centrally.
--
-- Clients select tags. They do not create, rename or map them.
CREATE TABLE Tags (
  Id                      CHAR(26)     NOT NULL,
  Code                    VARCHAR(40)  NOT NULL,
  Name                    VARCHAR(80)  NOT NULL,
  Kind                    ENUM('sleeve','neckline','hem','length','pattern',
                               'detail','occasion','other') NOT NULL DEFAULT 'other',
  PromptFragment          VARCHAR(160) NULL,   -- how it reads in a prompt, if not the name
  IsActive                TINYINT(1)   NOT NULL DEFAULT 1,
  SortOrder               SMALLINT     NOT NULL DEFAULT 0,
  CreatedByStaffId        CHAR(26)     NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedByStaffId        CHAR(26)     NULL,
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Tags_Code (Code),
  KEY IX_Tags_KindIsActive (Kind, IsActive)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Which tags are offered for which garment. A polo offers collar and half
-- sleeves; it does not offer floor length. Without this, every tag shows for
-- every garment and a nonsensical value can reach the generation prompt.
--
-- Authored by Super admin alongside the sub-category itself. Roughly a dozen
-- rows per sub-category. Seed a new sub-category by copying an existing one's
-- set — "Polo, like T-shirt" — then adjust, rather than starting from nothing.
CREATE TABLE SubCategoryTags (
  SubCategoryId           CHAR(26)     NOT NULL,
  TagId                   CHAR(26)     NOT NULL,
  IsDefault               TINYINT(1)   NOT NULL DEFAULT 0,  -- pre-selected on a new product
  SortOrder               SMALLINT     NOT NULL DEFAULT 0,
  PRIMARY KEY (SubCategoryId, TagId),
  KEY IX_SubCategoryTags_TagId (TagId),
  CONSTRAINT FK_SubCategoryTags_SubCategoryId FOREIGN KEY (SubCategoryId) REFERENCES SubCategories(Id),
  CONSTRAINT FK_SubCategoryTags_TagId FOREIGN KEY (TagId) REFERENCES Tags(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- A tag not mapped to the product's sub-category is NOT SHOWN — hidden, not
-- greyed. A list of things you cannot pick reads as broken.

CREATE TABLE ProductTags (
  ProductId               CHAR(26)     NOT NULL,
  TagId                   CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,   -- denormalised for the tenant filter
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (ProductId, TagId),
  KEY IX_ProductTags_ClientIdTagId (ClientId, TagId),
  CONSTRAINT FK_ProductTags_ProductId FOREIGN KEY (ProductId) REFERENCES Products(Id),
  CONSTRAINT FK_ProductTags_TagId FOREIGN KEY (TagId) REFERENCES Tags(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- FRD §5.4 — primary images are versioned, never overwritten.
-- Exactly one active per Products (FR-IMG-03), enforced by the generated
-- column below: active rows carry the ProductId, inactive rows carry NULL,
-- so the unique index permits many inactive and only one active.
CREATE TABLE ProductImages (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  ProductId               CHAR(26)     NOT NULL,   -- denormalised from the variant
  ProductVariantId        CHAR(26)     NOT NULL,   -- images belong to a COLOUR, not the style
  -- FRONT is required and drives most poses. BACK is optional and is the only
  -- source for a back-view pose — a back plate cannot be dressed from a front
  -- garment image. ADDITIONAL images are reference only and never generate.
  Role                    ENUM('front','back','additional') NOT NULL DEFAULT 'front',
  Uri                     VARCHAR(500) NOT NULL,
  WidthPx                 INT          NULL,
  HeightPx                INT          NULL,
  ByteSize                INT          NULL,
  ContentType             VARCHAR(60)  NULL,
  IsActive                TINYINT(1)   NOT NULL DEFAULT 1,
  -- One active image per role per colourway. Active rows carry a composite key,
  -- inactive rows carry NULL, so the unique index permits many archived images
  -- and exactly one live front and one live back.
  ActiveRoleKey           VARCHAR(40) GENERATED ALWAYS AS
                          (CASE WHEN IsActive = 1 AND Role IN ('front','back')
                                THEN CONCAT(ProductVariantId, ':', Role) ELSE NULL END) STORED,
  ShootCount              INT          NOT NULL DEFAULT 0,       -- FR-IMG-07
  UploadedBy              CHAR(26)     NULL,
  UploadedAt              DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  ReplacedAt              DATETIME(3)  NULL,
  ReplacedBy              CHAR(26)     NULL,
  ModerationStatus        ENUM('pending','passed','blocked') NOT NULL DEFAULT 'pending',
  ModerationReason        VARCHAR(255) NULL,
  PRIMARY KEY (Id),
  UNIQUE KEY UX_ProductImages_ActiveRoleKey (ActiveRoleKey),
  KEY IX_ProductImages_ProductVariantIdRoleIsActive (ProductVariantId, Role, IsActive),
  KEY IX_ProductImages_ProductId (ProductId),
  KEY IX_ProductImages_ClientId (ClientId),
  CONSTRAINT FK_ProductImages_ProductId FOREIGN KEY (ProductId) REFERENCES Products(Id),
  CONSTRAINT FK_ProductImages_ProductVariantId FOREIGN KEY (ProductVariantId) REFERENCES ProductVariants(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 6. MODEL LIBRARY                                  PRD §7 · FRD §6.1
-- =====================================================================
-- Global, not tenant-owned. ClientId appears only on reservation.

CREATE TABLE Models (
  Id                      CHAR(26)     NOT NULL,
  Code                    VARCHAR(20)  NOT NULL,      -- 'bm_014'
  DisplayName             VARCHAR(120) NULL,
  Status                  ENUM('draft','approved','retired') NOT NULL DEFAULT 'draft',
  StoragePrefix           VARCHAR(300) NOT NULL,      -- /models/{Code}/
  VocabularyVersion       VARCHAR(20)  NOT NULL,
  PromptTemplateId        CHAR(26)     NULL,
  GenerationSeed          VARCHAR(80)  NULL,          -- reproducibility, PRD T5
  -- FRD §6.1 Availability
  Availability            ENUM('shared','reserved','exclusive','cooling','retired')
                        NOT NULL DEFAULT 'shared',
  ReservedToClientId      CHAR(26)     NULL,
  ReservedFrom            DATETIME(3)  NULL,
  ReservedUntil           DATETIME(3)  NULL,
  CoolingUntil            DATETIME(3)  NULL,
  UsageCount              INT          NOT NULL DEFAULT 0,
  LastUsedAt              DATETIME(3)  NULL,
  ApprovedBy              CHAR(26)     NULL,
  ApprovedAt              DATETIME(3)  NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Models_Code (Code),
  -- FR-CAST-08: browse Filters on (Status, Availability, ReservedToClientId)
  KEY IX_Models_StatusAvailabilityReservedToClientId (Status, Availability, ReservedToClientId),
  KEY IX_Models_AvailabilityCoolingUntil (Availability, CoolingUntil)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Controlled vocabulary, PRD §7.2. Owned by us, versioned.
CREATE TABLE AttributeVocabulary (
  Id                      CHAR(26)     NOT NULL,
  Namespace               VARCHAR(40)  NOT NULL,          -- 'identity','Body','skin'
  AttrKey                 VARCHAR(60)  NOT NULL,
  AttrValue               VARCHAR(120) NOT NULL,
  Label                   VARCHAR(120) NOT NULL,
  SortOrder               SMALLINT     NOT NULL DEFAULT 0,
  FitRelevant             TINYINT(1)   NOT NULL DEFAULT 0,   -- drives relaxation order
  IsFilterable            TINYINT(1)   NOT NULL DEFAULT 0,   -- FR-CAT / F2.2 rail
  Version                 VARCHAR(20)  NOT NULL,
  DeprecatedAt            DATETIME(3)  NULL,
  PRIMARY KEY (Id),
  UNIQUE KEY UX_AttributeVocabulary_NamespaceAttrKeyAttrValueVersion (Namespace, AttrKey, AttrValue, Version),
  KEY IX_AttributeVocabulary_NamespaceAttrKeyDeprecatedAt (Namespace, AttrKey, DeprecatedAt)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- The filter index. One row per attribute per Models.
CREATE TABLE ModelTags (
  ModelId                 CHAR(26)     NOT NULL,
  Namespace               VARCHAR(40)  NOT NULL,
  AttrKey                 VARCHAR(60)  NOT NULL,
  AttrValue               VARCHAR(120) NOT NULL,
  PRIMARY KEY (ModelId, Namespace, AttrKey),
  KEY IX_ModelTags_NamespaceAttrKeyAttrValueModelId (Namespace, AttrKey, AttrValue, ModelId),   -- PRD T4
  CONSTRAINT FK_ModelTags_ModelId FOREIGN KEY (ModelId) REFERENCES Models(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE Poses (
  Id                      CHAR(26)     NOT NULL,
  Code                    VARCHAR(20)  NOT NULL,              -- 'ps_01'
  Label                   VARCHAR(120) NOT NULL,
  Description             VARCHAR(500) NULL,
  TryOnSafe               TINYINT(1)   NOT NULL DEFAULT 0,
  -- A back-view pose cannot be produced from a front garment image. Poses that
  -- need one are unavailable unless the product holds a back image.
  RequiresBackImage       TINYINT(1)   NOT NULL DEFAULT 0,
  SortOrder               SMALLINT     NOT NULL DEFAULT 0,
  IsActive                TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Poses_Code (Code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE Scenes (
  Id                      CHAR(26)     NOT NULL,
  Code                    VARCHAR(30)  NOT NULL,
  Label                   VARCHAR(120) NOT NULL,
  RelightPrompt           TEXT         NULL,
  NegativePrompt          TEXT         NULL,
  IsActive                TINYINT(1)   NOT NULL DEFAULT 1,
  SortOrder               SMALLINT     NOT NULL DEFAULT 0,
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Scenes_Code (Code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE PlateVariants (
  Id                      CHAR(26)     NOT NULL,
  Code                    VARCHAR(20)  NOT NULL,      -- 'bt_01','ew_03'
  Kind                    ENUM('bottom','top','eyewear') NOT NULL,
  Label                   VARCHAR(120) NOT NULL,
  SwatchHex               CHAR(7)      NULL,
  BundledFootwear         VARCHAR(120) NULL,
  InpaintPrompt           TEXT         NULL,
  NegativePrompt          TEXT         NULL,
  IsActive                TINYINT(1)   NOT NULL DEFAULT 1,
  PRIMARY KEY (Id),
  UNIQUE KEY UX_PlateVariants_Code (Code),
  KEY IX_PlateVariants_KindIsActive (Kind, IsActive)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Approved canonical plates. PRD §7.7 storage layout.
CREATE TABLE Plates (
  Id                      CHAR(26)     NOT NULL,
  ModelId                 CHAR(26)     NOT NULL,
  PlateType               ENUM('T','B','F') NOT NULL,
  -- The plate is generated for a specific base cut, not merely a plate type.
  -- PLATE.T is not one asset: a standard tank and a cropped tank are different
  -- plates because the base must end where the real garment ends.
  BaseCut                 ENUM('top_standard','top_cropped','top_long',
                               'bottom_full','bottom_knee','bottom_short',
                               'full') NOT NULL,
  PoseId                  CHAR(26)     NOT NULL,
  ImageUri                VARCHAR(500) NOT NULL,
  QaStatus                ENUM('pending','passed','failed') NOT NULL DEFAULT 'pending',
  QaNotes                 TEXT         NULL,
  GeneratedBy             CHAR(26)     NULL,              -- studio_operator
  ApprovedBy              CHAR(26)     NULL,              -- library_reviewer, FR-ROL-18
  ApprovedAt              DATETIME(3)  NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_Plates_ModelIdBaseCutPoseId (ModelId, BaseCut, PoseId),
  KEY IX_Plates_BaseCutQaStatusModelId (BaseCut, QaStatus, ModelId),   -- browse filter
  KEY IX_Plates_QaStatus (QaStatus),
  CONSTRAINT FK_Plates_ModelId FOREIGN KEY (ModelId) REFERENCES Models(Id),
  CONSTRAINT FK_Plates_PoseId FOREIGN KEY (PoseId) REFERENCES Poses(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
-- FR-ROL-18 (GeneratedBy <> ApprovedBy) is enforced in application code.
--
-- MODEL BROWSE FILTERS THROUGH THIS TABLE. A model is shown for a shoot only
-- if it holds an approved plate of the required BASE CUT (FR-CUT-04, FR-SHT-02a),
-- resolved from the product's sub-category — not merely of the right plate type. A Topwear
-- shoot needs PLATE.T, whose base carries a fixed bottom that survives into
-- the final image; Bottomwear needs PLATE.B, whose fixed top survives; FullWear
-- needs PLATE.F, whose base is wholly replaced. Without this filter a
-- merchandiser can select a model whose shoot will fail at generation for a
-- reason that was knowable at selection.

-- Stage-02 cache. PRD §8: key is Model + PlateType + PlateVariant + Pose.
CREATE TABLE PlateVariantRenders (
  Id                      CHAR(26)     NOT NULL,
  CacheKey                VARCHAR(120) NOT NULL,
  PlateId                 CHAR(26)     NOT NULL,
  PlateVariantId          CHAR(26)     NOT NULL,
  ImageUri                VARCHAR(500) NOT NULL,
  HitCount                INT          NOT NULL DEFAULT 0,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  LastUsedAt              DATETIME(3)  NULL,
  PRIMARY KEY (Id),
  UNIQUE KEY UX_PlateVariantRenders_CacheKey (CacheKey),
  KEY IX_PlateVariantRenders_PlateIdPlateVariantId (PlateId, PlateVariantId),
  CONSTRAINT FK_PlateVariantRenders_PlateId FOREIGN KEY (PlateId) REFERENCES Plates(Id),
  CONSTRAINT FK_PlateVariantRenders_PlateVariantId FOREIGN KEY (PlateVariantId) REFERENCES PlateVariants(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE ModelFavourites (
  ClientId                CHAR(26)     NOT NULL,
  ModelId                 CHAR(26)     NOT NULL,
  UserAccessId            CHAR(26)     NOT NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (ClientId, ModelId, UserAccessId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE ModelBookings (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  ModelId                 CHAR(26)     NOT NULL,
  BookedBy                CHAR(26)     NOT NULL,
  BookedAt                DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  ReleasedAt              DATETIME(3)  NULL,
  ReleaseReason           ENUM('unbooked','cancelled','admin') NULL,
  CoolingUntil            DATETIME(3)  NULL,              -- FR-CAST-12, 90 days
  PRIMARY KEY (Id),
  KEY IX_ModelBookings_ClientIdReleasedAt (ClientId, ReleasedAt),
  KEY IX_ModelBookings_ModelIdReleasedAt (ModelId, ReleasedAt),
  CONSTRAINT FK_ModelBookings_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id),
  CONSTRAINT FK_ModelBookings_ModelId FOREIGN KEY (ModelId) REFERENCES Models(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE CastingRequests (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  UserAccessId            CHAR(26)     NULL,
  Filters                 JSON         NOT NULL,      -- the exact combination that returned nothing
  Note                    VARCHAR(500) NULL,
  Status                  ENUM('open','queued','generated','declined') NOT NULL DEFAULT 'open',
  FulfilledModelId        CHAR(26)     NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  ResolvedAt              DATETIME(3)  NULL,
  PRIMARY KEY (Id),
  KEY IX_CastingRequests_StatusCreatedAt (Status, CreatedAt),
  KEY IX_CastingRequests_ClientIdCreatedAt (ClientId, CreatedAt)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 7. SHOOTS                                     FRD §6, §7 · PRD §8
-- =====================================================================

-- Garment-independent. FRD §1: steps 1–3 describe the Plates.
CREATE TABLE ShootConfigurations (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  Name                    VARCHAR(160) NULL,
  CategoryId              CHAR(26)     NULL,
  PlateType               ENUM('T','B','F') NOT NULL,
  ModelId                 CHAR(26)     NULL,
  PlateVariantId          CHAR(26)     NULL,
  SceneId                 CHAR(26)     NULL,
  PoseIds                 JSON         NULL,          -- ordered; order is render order
  Formats                 JSON         NULL,          -- ["9:16","4:5"]
  IsSaved                 TINYINT(1)   NOT NULL DEFAULT 0,   -- FR-SHT-06
  CreatedBy               CHAR(26)     NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  KEY IX_ShootConfigurations_ClientIdIsSaved (ClientId, IsSaved),
  CONSTRAINT FK_ShootConfigurations_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE Runs (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  ConfigurationId         CHAR(26)     NULL,
  UserAccessId            CHAR(26)     NOT NULL,  -- FR-ROL-26, always recorded
  ProductId               CHAR(26)     NULL,
  ProductVariantId        CHAR(26)     NULL,      -- the colourway shot. A multi-colour shoot is
                                                  -- one run per colour sharing a ConfigurationId
  ProductImageId          CHAR(26)     NULL,      -- FR-SHT-04a, the FRONT image used
  ProductBackImageId      CHAR(26)     NULL,      -- the BACK image, when back poses were selected
  AdHocGarmentUri         VARCHAR(500) NULL,      -- when not from a Products
  CategoryId              CHAR(26)     NULL,
  PlateType               ENUM('T','B','F') NOT NULL,
  ModelId                 CHAR(26)     NOT NULL,
  PlateVariantId          CHAR(26)     NULL,
  SceneId                 CHAR(26)     NULL,
  PoseIds                 JSON         NOT NULL,
  Formats                 JSON         NOT NULL,
  IsPreview               TINYINT(1)   NOT NULL DEFAULT 0,   -- FR-CR-11
  IsDemo                  TINYINT(1)   NOT NULL DEFAULT 0,   -- FR-ACC-30, no Credits
  ImageCountExpected      SMALLINT     NOT NULL,
  ImageCountDelivered     SMALLINT     NOT NULL DEFAULT 0,
  CreditsReserved         INT          NOT NULL DEFAULT 0,
  CreditsCommitted        INT          NOT NULL DEFAULT 0,
  Status                  ENUM('draft','queued','running','partial',
                                 'complete','failed','cancelled') NOT NULL DEFAULT 'draft',
  FailureReason           VARCHAR(400) NULL,
  -- FRD §7.1
  ApprovalState           ENUM('not_required','awaiting_approval',
                                 'changes_requested','approved') NOT NULL DEFAULT 'not_required',
  SubmittedAt             DATETIME(3)  NULL,
  DecidedBy               CHAR(26)     NULL,
  DecidedAt               DATETIME(3)  NULL,
  DecisionNote            VARCHAR(600) NULL,
  ApprovedOnCreation      TINYINT(1)   NOT NULL DEFAULT 0,   -- FR-APP-04
  QueuedAt                DATETIME(3)  NULL,
  StartedAt               DATETIME(3)  NULL,
  CompletedAt             DATETIME(3)  NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  KEY IX_Runs_ClientIdCreatedAt (ClientId, CreatedAt),
  KEY IX_Runs_ProductIdCreatedAt (ProductId, CreatedAt),
  KEY IX_Runs_ProductVariantIdCreatedAt (ProductVariantId, CreatedAt),
  KEY IX_Runs_ConfigurationId (ConfigurationId),
  KEY IX_Runs_StatusQueuedAt (Status, QueuedAt),                       -- queue worker
  KEY IX_Runs_ClientIdApprovalStateSubmittedAt (ClientId, ApprovalState, SubmittedAt),
  KEY IX_Runs_ClientIdUserAccessIdCreatedAt (ClientId, UserAccessId, CreatedAt),
  CONSTRAINT FK_Runs_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id),
  CONSTRAINT FK_Runs_ModelId FOREIGN KEY (ModelId) REFERENCES Models(Id),
  CONSTRAINT FK_Runs_ProductId FOREIGN KEY (ProductId) REFERENCES Products(Id),
  CONSTRAINT FK_Runs_ProductVariantId FOREIGN KEY (ProductVariantId) REFERENCES ProductVariants(Id),
  CONSTRAINT FK_Runs_ProductImageId FOREIGN KEY (ProductImageId) REFERENCES ProductImages(Id),
  CONSTRAINT FK_Runs_ProductBackImageId FOREIGN KEY (ProductBackImageId) REFERENCES ProductImages(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE RunImages (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  RunId                   CHAR(26)     NOT NULL,
  PoseId                  CHAR(26)     NOT NULL,
  Format                  VARCHAR(10)  NOT NULL,      -- '9:16'
  SequenceNo              SMALLINT     NOT NULL,
  ImageUri                VARCHAR(500) NULL,
  WidthPx                 INT          NULL,
  HeightPx                INT          NULL,
  ByteSize                INT          NULL,          -- storage tracking, rolled up into ClientUsage
  Status                  ENUM('queued','generating','delivered','failed','cancelled')
                        NOT NULL DEFAULT 'queued',
  FailureStage            ENUM('plate','variant','tryon','scene') NULL,
  FailureType             ENUM('system','provider','policy','timeout') NULL,
  FailureDetail           VARCHAR(400) NULL,
  Charged                 TINYINT(1)   NOT NULL DEFAULT 0,       -- FR-CR-02
  IsSelected              TINYINT(1)   NOT NULL DEFAULT 0,       -- FR-AST-07
  ApprovalState           ENUM('inherit','approved','rejected') NOT NULL DEFAULT 'inherit',
  RegeneratedFromId       CHAR(26)     NULL,
  Provenance              JSON         NULL,          -- PRD P6, full Stage record
  DeliveredAt             DATETIME(3)  NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  UNIQUE KEY UX_RunImages_RunIdPoseIdFormatSequenceNo (RunId, PoseId, Format, SequenceNo),
  KEY IX_RunImages_ClientIdCreatedAt (ClientId, CreatedAt),
  KEY IX_RunImages_RunIdStatus (RunId, Status),
  KEY IX_RunImages_ClientIdIsSelected (ClientId, IsSelected),
  CONSTRAINT FK_RunImages_RunId FOREIGN KEY (RunId) REFERENCES Runs(Id),
  CONSTRAINT FK_RunImages_PoseId FOREIGN KEY (PoseId) REFERENCES Poses(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Per-Stage record. Needed for partial-failure handling and cost attribution.
CREATE TABLE RunImageStages (
  Id                      CHAR(26)     NOT NULL,
  RunImageId              CHAR(26)     NOT NULL,
  Stage                   ENUM('plate','variant','tryon','scene') NOT NULL,
  Status                  ENUM('pending','running','succeeded','failed','skipped','cache_hit')
                    NOT NULL DEFAULT 'pending',
  Provider                VARCHAR(60)  NULL,
  ProviderRef             VARCHAR(120) NULL,
  Attempt                 SMALLINT     NOT NULL DEFAULT 1,
  DurationMs              INT          NULL,
  CostMinor               INT          NULL,              -- Provider cost, for margin reporting
  ErrorCode               VARCHAR(80)  NULL,
  ErrorDetail             TEXT         NULL,
  StartedAt               DATETIME(3)  NULL,
  FinishedAt              DATETIME(3)  NULL,
  PRIMARY KEY (Id),
  KEY IX_RunImageStages_RunImageIdStage (RunImageId, Stage),
  CONSTRAINT FK_RunImageStages_RunImageId FOREIGN KEY (RunImageId) REFERENCES RunImages(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Running totals per client, so the dashboard and the allowance check never
-- aggregate RunImages. Maintained on delivery and on deletion, with a nightly
-- reconciliation job — the same pattern as CreditBalances.
CREATE TABLE ClientUsage (
  ClientId                CHAR(26)     NOT NULL,
  StorageBytes            BIGINT       NOT NULL DEFAULT 0,
  ImageCount              INT          NOT NULL DEFAULT 0,
  ProductCount            INT          NOT NULL DEFAULT 0,
  BillableSeatCount       SMALLINT     NOT NULL DEFAULT 0,
  ViewerCount             SMALLINT     NOT NULL DEFAULT 0,
  RecalculatedAt          DATETIME(3)  NULL,
  UpdatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  Version                 INT          NOT NULL DEFAULT 0,
  PRIMARY KEY (ClientId),
  CONSTRAINT FK_ClientUsage_ClientId FOREIGN KEY (ClientId) REFERENCES Clients(Id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- 8. NOTIFICATIONS, SUPPORT, AUDIT
-- =====================================================================

CREATE TABLE Notifications (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  UserId                  CHAR(26)     NOT NULL,
  Category                VARCHAR(40)  NOT NULL,
  Title                   VARCHAR(200) NOT NULL,
  Body                    VARCHAR(600) NULL,
  LinkUri                 VARCHAR(400) NULL,
  ReadAt                  DATETIME(3)  NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  KEY IX_Notifications_ClientIdUserIdReadAtCreatedAt (ClientId, UserId, ReadAt, CreatedAt)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE SupportTickets (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NOT NULL,
  UserAccessId            CHAR(26)     NULL,
  Subject                 VARCHAR(200) NOT NULL,
  Body                    TEXT         NOT NULL,
  RunId                   CHAR(26)     NULL,
  RunImageId              CHAR(26)     NULL,
  -- FR-CR-20: tagged so failure data survives without an in-Products flag
  TagModelId              CHAR(26)     NULL,
  TagCategory             ENUM('top','bottom','full') NULL,
  TagPlateType            ENUM('T','B','F') NULL,
  Status                  ENUM('open','in_progress','resolved','closed') NOT NULL DEFAULT 'open',
  Resolution              VARCHAR(600) NULL,
  CreditsGranted          INT          NOT NULL DEFAULT 0,
  HandledBy               CHAR(26)     NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  ResolvedAt              DATETIME(3)  NULL,
  PRIMARY KEY (Id),
  KEY IX_SupportTickets_ClientIdStatusCreatedAt (ClientId, Status, CreatedAt),
  KEY IX_SupportTickets_TagModelIdTagCategory (TagModelId, TagCategory)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ONE LOG, EVERY ACTOR. Members, staff and system jobs alike. Customer actions
-- are logged as thoroughly as staff actions — "who changed this and what was it
-- before" is asked about a client's own users far more often than about ours.
--
-- APPEND ONLY. No application path issues UPDATE or DELETE, and the database
-- grants must enforce that rather than relying on discipline.
--
-- A FAILED AUDIT WRITE FAILS THE OPERATION IT DESCRIBES (FR-AUD-08). An
-- unlogged change is worse than a rejected one.
--
-- BeforeState and AfterState hold the CHANGED FIELDS ONLY, not whole records.
-- Products is a wide table and storing it twice per edit would dwarf the data.
--
-- GROWS WITHOUT BOUND. Partition by month from the outset; retrofitting a
-- partition scheme onto a large audit table is painful. Align the partition
-- boundary with the archive boundary so ageing out a period is cheap.
--
-- RETENTION IS CONFIGURATION, NOT CODE (FRD §11.1). Named buckets carry an age
-- threshold, a backup retention period and a list of entities. ANYTHING NOT
-- LISTED IS KEPT FOREVER — omission must never cause deletion.
--
-- The 90-day bucket is for OPERATIONAL NOISE ONLY: sign-in attempts, password
-- reset attempts, token issue and consumption, session lifecycle, processed
-- webhook payloads, read notifications. High volume, no lasting meaning.
--
-- It must NOT contain anything describing a change to a customer's data —
-- product edits, image replacements, run activity, role changes, master data
-- renames. A merchandiser asking in March why a February shoot used the wrong
-- colour needs that trail. When in doubt, leave it unlisted.
--
-- The archive job: archive, verify, THEN delete. Batched, idempotent,
-- resumable, and it refuses to remove a row still referenced by live data.
--
-- NEVER ELIGIBLE FOR ANY BUCKET, whatever the configuration says:
--   CreditLedger, Invoices, SubscriptionPeriods, Plates, Models, RunImages.
-- These are the record, not the trail.
CREATE TABLE AuditLogs (
  Id                      CHAR(26)     NOT NULL,
  ClientId                CHAR(26)     NULL,              -- NULL for platform-level actions
  ActorType               ENUM('member','staff','system') NOT NULL,
  ActorId                 CHAR(26)     NULL,
  ImpersonatedBy          CHAR(26)     NULL,
  Action                  VARCHAR(80)  NOT NULL,          -- 'product.deleted','credits.granted'
  ActorJob                VARCHAR(80)  NULL,              -- FR-AUD-06: the job or handler, when ActorType='system'
  Category                ENUM('general','transient','financial','safety') NOT NULL DEFAULT 'general',
                                                          -- FR-AUD-18: picks the retention bucket.
                                                          -- 'general' is in no bucket, so it is kept forever
  EntityType              VARCHAR(60)  NOT NULL,
  EntityId                CHAR(26)     NULL,
  Reason                  VARCHAR(600) NULL,              -- mandatory on staff actions
  BeforeState             JSON         NULL,
  AfterState              JSON         NULL,
  IpAddress               VARBINARY(16) NULL,
  CreatedAt               DATETIME(3)  NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (Id),
  KEY IX_AuditLogs_ClientIdCreatedAt (ClientId, CreatedAt),
  KEY IX_AuditLogs_EntityTypeEntityIdCreatedAt (EntityType, EntityId, CreatedAt),
  KEY IX_AuditLogs_ActorTypeActorIdCreatedAt (ActorType, ActorId, CreatedAt),
  KEY IX_AuditLogs_CategoryCreatedAt (Category, CreatedAt)   -- the archive job
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =====================================================================
-- NOTES FOR IMPLEMENTATION
-- =====================================================================
-- 1. TENANT ISOLATION. Add a DbContext global query filter for every
--    entity carrying ClientId, and an integration test that reflects
--    over the Models and fails if one is missing.
--
-- 2. CREDIT CONCURRENCY. Two runs starting at once must not both pass
--    the Balance check. Reserve inside a transaction that updates
--    CreditBalances with an optimistic Version check, then
--    writes the ledger row. Never read-then-write without the Version.
--
-- 3. THE LEDGER IS THE AUTHORITY. CreditBalances is a cache.
--    Provide a reconciliation job that rebuilds it from CreditLedger
--    and alerts on drift — drift means a bug, not a data problem.
--
-- 4. RULES MYSQL CANNOT EXPRESS, enforce in Code and cover with tests:
--    · last owner cannot be removed or demoted        (FR-ROL-05)
--    · a Plates's GeneratedBy <> ApprovedBy          (FR-ROL-18)
--    · Reserved models excluded from browse queries   (FR-CAST-08)
--    · shared pool floor before allowing a booking    (FR-CAST-17)
--    · a client may use a category only when its segment is permitted (FR-TAX-05)
--    · SEGMENT-MODEL PAIRING. A run may only start when a SegmentModels row
--      exists for the product's segment and the chosen model. Absence means
--      refuse. This is a safety control, not a convenience filter, so it is
--      checked at model browse AND again immediately before generation — a
--      model may be un-approved for a segment between the two.  (FR-SEG-*)
--
-- 5. BROWSE QUERY SHAPE. Filtering is an intersection over ModelTags.
--    At library Sizes under ~2,000 models, load the visible library
--    into memory and filter there rather than composing N joins.
--    Revisit only when that stops holding.
--
-- 6. STALENESS. Products.IsStale is maintained on image replacement and
--    on Runs completion. A nightly job recomputes it as a safety net:
--    stale when the newest completed Runs for a Products used an image
--    that is no longer active.
--
-- 7. SOFT DELETE. DeletedAt excludes a row from the Products surface but
--    never from audit, billing or generated assets. Hard deletion happens
--    only through the erasure path after the FR-ACC-26 grace period.
--
-- 8. ENTITLEMENT RESOLUTION. Absence of a ClientEntitlements row means
--    not granted. Do not treat NULL as permitted. Cache the resolved set
--    per client — it changes rarely and is read on every product form.
--
-- 9. NOT YET MODELLED — open decisions in the FRD:
--    · asset retention after cancellation           (F6)
--    · queue priority by Plans                       (gap)
--    · multi-currency tax beyond GST                (gap)

SET FOREIGN_KEY_CHECKS = 1;
