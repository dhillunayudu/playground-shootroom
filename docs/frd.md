# Shootroom — Functional Requirements

**Version** 1.0 · Draft for review
**Scope** Whole application. Functionality only — no architecture, no data model, no infrastructure.
**Companions** `shootroom-prd.md` (product definition, model library, pipeline) · Technical Requirements (to follow)

---

## 1. Purpose

This document defines what the application does, screen by screen and behaviour by behaviour. It covers the full product surface: account, products, shoots, assets, dashboard, billing and administration.

It deliberately excludes how any of it is built. Where a requirement implies a technical decision, that decision belongs in the Technical Requirements.

**Requirement IDs** are `FR-<module>-<n>`. Priority is Must, Should or Could. Anything marked Phase 2 is out of scope for launch but recorded so the design does not preclude it.

---

## 2. Roles and permissions

Three separate axes govern what a request is allowed to do. Conflating them is a common source of bugs, so they are defined independently and evaluated in order: **account state, then customer role, then internal role.**

A request is permitted only if the account state allows it **and** the actor's role allows it. State always wins — an Admin on a past-due account still cannot spend credits.

### 2.1 Account state

Not a role. It gates the whole account regardless of who is asking.

| State | Browse and view | Download assets | Create products | Run shoots | Billing |
|---|---|---|---|---|---|
| Unactivated | — | — | — | — | — |
| Trial | ✓ | ✓ | ✓ | ✓ (trial credits) | Upgrade only |
| Active | ✓ | ✓ | ✓ | ✓ | ✓ |
| Past due | ✓ | ✓ | ✓ | — | ✓ |
| Cancelled | ✓ | ✓ | — | — | Reactivate only |
| Suspended | — | — | — | — | — |

| ID | Requirement | Priority |
|---|---|---|
| FR-ROL-01 | Account state is evaluated before role on every request | Must |
| FR-ROL-02 | **Past due degrades to read-only, never to lockout.** A customer whose payment failed retains access to imagery they have already paid for | Must |
| FR-ROL-02a | Read-only means: browse models, view products, view runs, view and **download every existing asset**, view billing and pay. It means: no new runs, no new products, no credit spend, no new members | Must |
| FR-ROL-02b | The grace period runs for the full duration of the payment provider's retry schedule. Access is not withdrawn earlier | Must |
| FR-ROL-02c | The reason and the resolution route are stated on every blocked action, not only on the billing page | Must |
| FR-ROL-02d | Paying restores full access immediately, without waiting for a scheduled job | Must |
| FR-ROL-03 | A blocked action states which axis blocked it — account state or role — and what to do next | Must |
| FR-ROL-04 | State transitions are recorded with actor, reason and timestamp | Must |

### 2.2 Customer roles

Four roles within an account. **Producer is the default for new invitees.**

| Capability | Owner | Admin | Producer | Viewer |
|---|:---:|:---:|:---:|:---:|
| Browse models, view products and assets | ✓ | ✓ | ✓ | ✓ |
| Download **approved** images | ✓ | ✓ | ✓ | ✓ |
| Download images awaiting approval | ✓ | ✓ | Watermarked preview only | — |
| Submit a run for approval | ✓ | ✓ | ✓ | — |
| **Approve a run or image** | ✓ | ✓ | — | — |
| Request changes on a run | ✓ | ✓ | — | — |
| Create and edit products | ✓ | ✓ | ✓ | — |
| Import products by CSV | ✓ | ✓ | ✓ | — |
| **Run shoots (spends credits)** | ✓ | ✓ | ✓ | — |
| Regenerate a single image | ✓ | ✓ | ✓ | — |
| Delete products | ✓ | ✓ | — | — |
| Delete generated assets | ✓ | ✓ | own runs only | — |
| Submit casting requests | ✓ | ✓ | ✓ | — |
| Edit master data (§5.4) | ✓ | ✓ | — | — |
| Invite and remove members | ✓ | ✓ | — | — |
| Assign roles | ✓ | ✓ (cannot grant Owner) | — | — |
| View plan and invoices | ✓ | View only | — | — |
| Change plan, purchase credits | ✓ | — | — | — |
| Payment method and tax details | ✓ | — | — | — |
| Disclosure and watermark settings | ✓ | ✓ | — | — |
| Set member credit caps | ✓ | — | — | — |
| Export account data | ✓ | — | — | — |
| Delete account | ✓ | — | — | — |

**Role intent.** *Owner* holds commercial authority — one per account minimum, usually the person who signed up. *Admin* runs the workspace day to day without touching money. *Producer* is the working role: the merchandiser who adds products and runs shoots. *Viewer* exists for agencies, freelance marketers and stakeholders who need the output but must not be able to spend.

| ID | Requirement | Priority |
|---|---|---|
| FR-ROL-05 | Every account has at least one Owner. The last Owner cannot be removed or demoted | Must |
| FR-ROL-06 | An Admin cannot promote themselves or anyone else to Owner. Ownership transfer is initiated by the current Owner and confirmed by the recipient | Must |
| FR-ROL-07 | Producers may delete assets from runs they started, not from runs started by others | Must |
| FR-ROL-08 | Role changes take effect on the member's next request; active sessions are re-evaluated rather than left stale | Must |
| FR-ROL-09 | Invitations carry a role, are single use, and expire after 7 days | Must |
| FR-ROL-10 | Removing a member revokes access immediately but retains their products, shoots and assets under the account | Must |
| FR-ROL-11 | Seats are a plan limit. Inviting beyond the limit is blocked with an upgrade route | Must |
| FR-ROL-12 | A member list shows role, last active, and credits consumed this period | Should |

**Credit spend control.** Credits are money, so an unrestricted Producer can consume a month's allowance in an afternoon.

| ID | Requirement | Priority |
|---|---|---|
| FR-ROL-13 | The Owner may set an optional **monthly credit cap per member**. Unset means uncapped | Must |
| FR-ROL-14 | A run that would exceed a member's cap is blocked before generation, showing the cap, consumption to date and the shortfall | Must |
| FR-ROL-15 | Caps reset with the billing period and are visible to the member, not only the Owner | Must |
| FR-ROL-16 | The Owner may raise a cap mid-period; the change applies immediately | Must |
| FR-ROL-17 | Approval workflow for runs above a threshold | Could — Phase 3. Caps are preferred at launch because they need no second party to be online |

### 2.3 Internal roles

Shootroom staff only, held in a separate identity space from customer accounts. An internal user never appears in a customer's member list.

| Capability | Support | Platform admin | Studio operator | Library reviewer | Super admin |
|---|:---:|:---:|:---:|:---:|:---:|
| Search and view customer accounts | ✓ | ✓ | — | — | ✓ |
| Impersonate a user *(deferred — D1)* | ? | ✓ | — | — | ✓ |
| View a customer's assets for support | ✓ | ✓ | — | — | ✓ |
| Grant, adjust or expire credits | — | ✓ | — | — | ✓ |
| Issue refunds and credit notes | — | ✓ | — | — | ✓ |
| Suspend or reinstate an account | — | ✓ | — | — | ✓ |
| Plate Console — generate plates | — | — | ✓ | ✓ | ✓ |
| **Approve plates into the library** | — | — | — | ✓ | ✓ |
| Publish, unpublish or retire models | — | ✓ | — | ✓ | ✓ |
| Review the casting request queue | — | ✓ | ✓ | ✓ | ✓ |
| Review output-quality tickets | ✓ | ✓ | — | ✓ | ✓ |
| Override a content-moderation block | ✓ | ✓ | — | — | ✓ |
| Platform metrics | ✓ | ✓ | — | — | ✓ |
| Grant or revoke a client entitlement (§5.3) | — | ✓ | — | — | ✓ |
| **Edit the catalogue taxonomy** — segments, categories, sub-categories | — | — | — | — | ✓ |
| Manage internal roles | — | — | — | — | ✓ |

| ID | Requirement | Priority |
|---|---|---|
| FR-ROL-18 | **Studio operator and Library reviewer are separate roles and one person cannot approve their own plate.** This turns the §7.6 QA gate from a convention into a permission | Must |
| FR-ROL-19 | Support can diagnose but cannot move money. Credit grants and refunds belong to Platform admin | Must |
| FR-ROL-20 | Impersonation requires a recorded reason, is time-boxed, is visible to the customer in their session list, and is fully audit logged | **Deferred — see D1.** Not in Phase 1 scope until the design is settled |
| FR-ROL-21 | Impersonating users cannot change billing, delete an account, or purchase credits under any circumstances | **Deferred — see D1** |
| FR-ROL-22 | Internal roles are additive; a user may hold several | Should |
| FR-ROL-23 | Every internal action is audit logged with actor, target, timestamp and reason. Logs are immutable and separately retained | Must |
| FR-ROL-24 | Super admin is limited to a named list, reviewed quarterly | Must |

### 2.4 Phase 1 scope

Teams may ship after launch, but **the data model must assume them from day one** — retrofitting an actor onto ownership, audit and billing is materially harder than building it in.

| ID | Requirement | Priority |
|---|---|---|
| FR-ROL-25 | Phase 1 may present a single user per account, with that user holding Owner | Must |
| FR-ROL-26 | Every product, shoot, asset and credit transaction records the acting member from launch, whether or not teams are exposed | Must |
| FR-ROL-27 | Permission checks are written against the full role model from launch, even where only Owner exists in the UI | Must |
| FR-ROL-28 | Enabling teams later requires no data migration of existing records | Must |

## 3. Module A — Account and access

### 3.1 Registration

| ID | Requirement | Priority |
|---|---|---|
| FR-ACC-01 | Visitor registers with full name, work email, password, company name, country | Must |
| FR-ACC-02 | Password rules stated before submission; strength shown live | Must |
| FR-ACC-03 | Terms and privacy policy must be explicitly accepted; version recorded | Must |
| FR-ACC-04 | Duplicate email is rejected with a message that does not confirm whether the address is registered | Must |
| FR-ACC-05 | Registration creates an unactivated account. No product access until activated | Must |
| FR-ACC-05a | Registration creates **three records in a single transaction**: the Client in `unactivated` state, the User with an unverified email, and a UserAccess record granting that user the **Owner** role. If any one fails, none are created | Must |
| FR-ACC-05b | The registering person is always the Owner. A client can never exist without one (FR-ROL-05) | Must |
| FR-ACC-05c | No invitation is involved in self-registration. Invitations (§3.6) exist only to add further people to a client that already exists | Must |
| FR-ACC-05d | The credentials submitted at registration are the credentials used to sign in after activation. No second account is created and no second password is set | Must |
| FR-ACC-06 | Optional at registration: business type, catalogue size, how they heard about us | Could |
| FR-ACC-07 | Social or SSO sign-in | Could — Phase 2 |

### 3.2 Activation

| ID | Requirement | Priority |
|---|---|---|
| FR-ACC-08 | Welcome email sent on registration containing a single-use activation link | Must |
| FR-ACC-09 | Activation link expires after 72 hours; an expired link offers to resend | Must |
| FR-ACC-10 | On activation the account is granted **free trial credits, valid for a fixed period** from activation. No card and no payment provider record is created | Must |
| FR-ACC-10c | **No payment provider customer is created at registration.** It is created when the client first proceeds to checkout, so a client who never subscribes leaves no record with the provider | Must |
| FR-ACC-10a | Activation **creates nothing**. The Client, User and Owner access already exist from registration (FR-ACC-05a). Activation verifies the email, moves the Client from `unactivated` to `trial`, and grants the trial credits | Must |
| FR-ACC-10b | Access is gated by `Client.state`, not by the absence of records. An unactivated client holds complete records that can do nothing (§2.1) | Must |
| FR-ACC-11 | Activation logs the user in and lands them on first-run onboarding, not the dashboard | Must |
| FR-ACC-12 | User may request a new activation email; rate limited | Must |
| FR-ACC-13 | Unactivated accounts are purged after 30 days, removing the Client, User and UserAccess records together | Should |
| FR-ACC-13a | Purging frees the email address for re-registration | Should |

### 3.3 Sign in and recovery

| ID | Requirement | Priority |
|---|---|---|
| FR-ACC-14 | Sign in with email and password | Must |
| FR-ACC-15 | Failed attempts are rate limited. After 5 consecutive failures the account locks for 15 minutes and an unlock email is sent | Must |
| FR-ACC-15a | The failure counter resets on successful sign-in | Must |
| FR-ACC-15b | Sign-in responses do not reveal whether an email is registered. Wrong email and wrong password return the same message and take the same time | Must |
| FR-ACC-19 | Password reset invalidates all other active sessions and sends a confirmation email to the registered address | Must |
| FR-ACC-19a | Changing a password while signed in preserves the current session and revokes all others | Must |
| FR-ACC-20 | Two-factor authentication at sign-in | Could — Phase 2 |

### 3.3.1 Password reset by OTP

| ID | Requirement | Priority |
|---|---|---|
| FR-ACC-16 | Forgot password sends a **6-digit numeric OTP** to the registered email, valid **10 minutes**, single use | Must |
| FR-ACC-16a | The OTP is generated from a cryptographically secure random source. Never a timestamp, sequence or predictable derivation | Must |
| FR-ACC-16b | The request confirms "if that address is registered, a code has been sent" whether or not it exists | Must |
| FR-ACC-17 | Three verification attempts. On the third failure the code is invalidated and a new one must be requested | Must |
| FR-ACC-17a | **Issuing a new OTP invalidates every outstanding OTP for that user.** Without this, repeated requests accumulate live codes and defeat the attempt cap | Must |
| FR-ACC-17b | **A maximum of 5 OTPs may be requested per user per hour**, and 10 per day. Beyond that, further requests are refused with the same neutral message | Must |
| FR-ACC-17c | Rate limits are enforced per user and per source address independently, so rotating addresses does not bypass them | Must |
| FR-ACC-18 | Successful verification opens password reset. The new password cannot equal the previous one | Must |
| FR-ACC-18a | The verified OTP is consumed at the point of verification and cannot be reused to reset again | Must |
| FR-ACC-18b | The reset must be completed within 15 minutes of verification, or the OTP must be requested again | Must |

**Why the limits are specified together.** A 6-digit code is one million combinations. The three-attempt cap alone is defeated by requesting a new code after every third guess, so FR-ACC-17, 17a and 17b only work as a set. Implementing one without the others provides no protection.

### 3.3.2 Token handling

Applies to every emailed credential: activation links, password reset OTPs, email-change verification, and invitations.

| ID | Requirement | Priority |
|---|---|---|
| FR-ACC-41 | **Only a hash of the token is stored.** The raw value exists in the outbound email and nowhere else. A database dump must not permit account takeover | Must |
| FR-ACC-42 | Tokens are compared using a constant-time comparison | Must |
| FR-ACC-43 | Every token is **single use**. Consumption is recorded with a timestamp and the token cannot be replayed | Must |
| FR-ACC-44 | **Issuing a token of a given kind invalidates any outstanding token of that kind for the same user.** A resent activation link kills the previous one | Must |
| FR-ACC-45 | Link tokens are at least 128 bits of entropy from a cryptographically secure source | Must |
| FR-ACC-46 | Expired and consumed tokens are purged after 30 days | Should |
| FR-ACC-47 | Token issue and consumption are logged with kind, user, source address and outcome — never the token value | Must |
| FR-ACC-48 | Token kinds and lifetimes: activation 72 hours, password reset OTP 10 minutes, email change 24 hours, invitation 7 days | Must |

### 3.4 Account settings

| ID | Requirement | Priority |
|---|---|---|
| FR-ACC-21 | View and edit profile: name, company, country, avatar | Must |
| FR-ACC-22 | Change password with current password confirmation | Must |
| FR-ACC-23 | Change email, verified by a link sent to the **new** address and a notification to the old | Must |
| FR-ACC-23a | The change takes effect only when the new address is verified. Until then sign-in continues to use the old address | Must |
| FR-ACC-23b | The notification to the old address includes a route to reverse the change, in case the account is compromised | Must |
| FR-ACC-23c | The new address must not already be registered | Must |
| FR-ACC-24 | View active sessions and sign out of all devices | Should |
| FR-ACC-24a | Disclosure settings — watermark on or off, wording, placement — editable by Owner and Admin (§7.2) | Must |
| FR-ACC-25 | Export account data — products, shoot history, generated images | Should |
| FR-ACC-26 | Delete account. Warns about data loss and any active subscription; 30-day grace before hard deletion | Must |
| FR-ACC-27 | Invite members by email, assign a role per §2.2, revoke access | Should — Phase 2 |

### 3.5 Onboarding

| ID | Requirement | Priority |
|---|---|---|
| FR-ACC-28 | First-run flow explains the four-step shoot in under a minute and states the trial allowance and expiry date | Must |
| FR-ACC-28a | First run includes the disclosure checklist step (§7.2) | Must |
| FR-ACC-29 | Offers two paths: add a first product, or run a demo shoot on a sample garment | Must |
| FR-ACC-30 | A demo shoot consumes no credits and is clearly labelled as a sample | Should |
| FR-ACC-31 | Onboarding is skippable and re-openable from help | Must |

### 3.6 Invitations

Invitations exist **only to add a person to a client that already exists.** They are not part of self-registration.

| ID | Requirement | Priority |
|---|---|---|
| FR-ACC-32 | An Owner or Admin invites a person by email with a role (§2.2) | Should — Phase 2 |
| FR-ACC-33 | The invitation is stored against the client with a hashed single-use token and a 7-day expiry. **No User record is created** — the invitee may not have an account yet | Must |
| FR-ACC-34 | Accepting an invitation creates the User if none exists, or links the existing User, and creates a UserAccess record with the invited role | Must |
| FR-ACC-35 | An expired, revoked or already-accepted invitation grants nothing and offers to request a new one | Must |
| FR-ACC-36 | A person already holding access to that client cannot be re-invited | Must |
| FR-ACC-37 | An invitee who already has a Shootroom login accepts with their existing credentials and gains a second client, rather than creating a second account | Must |

#### Sales-led client creation

| ID | Requirement | Priority |
|---|---|---|
| FR-ACC-38 | Staff may create a Client in `unactivated` state and issue an **Owner invitation** to a named email, for sales-led onboarding | Could — Phase 2 |
| FR-ACC-39 | Accepting an Owner invitation creates the User, creates UserAccess with role Owner, and activates the Client — the same end state as self-registration | Must, if built |
| FR-ACC-40 | A client with no members may hold **only one** outstanding Owner invitation, so two people cannot race to own the same brand | Must, if built |

---

## 4. Module B — Credits and trial

### 4.1 Credit model

**One credit produces one image.** It is the only unit, so a customer can predict cost before pressing generate.

**Credits are charged on success only.** An image is charged when its full pipeline completes and the file is delivered. Anything that fails on the way — a stage error, a timeout, a policy refusal — costs nothing and requires no decision from anyone.

| ID | Requirement | Priority |
|---|---|---|
| FR-CR-01 | A run costs `poses × formats` credits, shown before confirmation | Must |
| FR-CR-02 | Credits are reserved when a run starts and **committed per image only on successful delivery** | Must |
| FR-CR-03 | Any image that fails for system, provider or policy reasons is **not charged**. Reserved credits for it are released | Must |
| FR-CR-04 | A partially successful run charges only for the images delivered, and says so | Must |
| FR-CR-05 | A user-requested regeneration costs 1 credit, regardless of why it was requested | Must |
| FR-CR-06 | A run cannot start without sufficient credits. **The check is at run level, before generation begins** — never mid-run | Must |
| FR-CR-06a | The block states the cost, the balance and the exact shortfall | Must |
| FR-CR-06b | The top-up offered **leads with the smallest pack that covers the shortfall**, with other packs available | Must |
| FR-CR-06c | After purchase the customer returns to the same step with the shoot configuration intact and ready to generate | Must |
| FR-CR-06d | The block also offers to **reduce the run** — dropping a format or a pose — showing which combinations fit the current balance | Should |
| FR-CR-06e | **There is no overage.** Runs are blocked at zero rather than billed beyond the balance, so no customer receives an unexpected charge | Must |
| FR-CR-07 | Balance is visible in the header on every screen | Must |
| FR-CR-08 | Credit ledger lists every grant, purchase, consumption, release and expiry with date, run reference and running balance | Must |
| FR-CR-09 | Released reservations appear in the ledger, so a customer can see they were not charged for a failure | Must |
| FR-CR-10 | Warn at 20% remaining and at zero, in-app and by email | Should |

**Regeneration is deliberately unconditional.** It costs one credit whether the image was defective or simply not what the customer wanted. Judging fault per image would require a defect standard and a review process; charging one credit is cheaper for the customer than either and needs no adjudication.

### 4.1.1 Preview run

The single most effective control on wasted spend. Most dissatisfaction is a wrong model, pose or scene rather than a failed generation, and it is only visible once the customer sees the actual combination.

| ID | Requirement | Priority |
|---|---|---|
| FR-CR-11 | At step 4 the customer may generate a **single preview image for 1 credit** before committing to the full run | Must |
| FR-CR-12 | The preview uses the first selected pose and the first selected format, with the real model, garment and scene | Must |
| FR-CR-13 | From the preview the customer may change any earlier step and preview again, or proceed to the full run | Must |
| FR-CR-14 | The preview is a real generated image, retained in the run and counted in its output | Must |
| FR-CR-15 | Proceeding to the full run charges the remaining images, not the previewed one again | Must |
| FR-CR-16 | Preview is optional, not enforced | Must |

**Why this rather than a refund policy.** A bad choice discovered after a 24-image run costs 24 credits and produces a support ticket. The same choice discovered at preview costs one credit and produces nothing.

### 4.1.2 Quality complaints

There is **no in-product mechanism to report a bad image.** A button invites use out of mild disappointment rather than genuine defect, and it would require a published defect standard, an adjudication process, and abuse controls to sit behind it.

| ID | Requirement | Priority |
|---|---|---|
| FR-CR-17 | Customers unhappy with output contact support by email, with run context attached from the app | Must |
| FR-CR-18 | Support reviews case by case and may grant credits through the admin console (FR-ADM-02), with a mandatory reason recorded in the ledger | Must |
| FR-CR-19 | No published defect standard, no automatic refund, no self-service credit return | Must |
| FR-CR-20 | Support tickets about output quality are tagged by model, garment category and plate type, so the failure data survives without an in-product flag | Should |

**Accepted trade-off.** Without a flag button there is no structured defect signal. Two partial substitutes: tagged support tickets, and regeneration rate — a run regenerated repeatedly is telling you something without anyone clicking anything.

### 4.2 Trial

| ID | Requirement | Priority |
|---|---|---|
| FR-CR-09 | Trial grant is 30 credits expiring 30 days from activation | Must |
| FR-CR-10 | Days and credits remaining are visible on the dashboard throughout the trial | Must |
| FR-CR-11 | Reminder emails at 7 days, 2 days and on expiry | Should |
| FR-CR-12 | On expiry, unused trial credits are forfeited and shoot creation is blocked. Existing products and generated images remain accessible and downloadable | Must |
| FR-CR-13 | Trial credits are consumed before purchased credits when both are held | Must |
| FR-CR-14 | One trial per account and per verified email; abuse detection on duplicate signups | Should |

### 4.3 Additional credits

| ID | Requirement | Priority |
|---|---|---|
| FR-CR-15 | Purchase credit packs independently of the subscription | Must |
| FR-CR-16 | Pack sizes and prices are configurable without a release | Must |
| FR-CR-17 | Purchased credits do not expire while a subscription is active; expiry after cancellation is stated at purchase | Must |
| FR-CR-18 | Purchase issues an invoice and applies the balance immediately | Must |
| FR-CR-19 | Auto top-up when balance falls below a user-set threshold | Could |

---

## 5. Module C — Products

The product catalogue is the entry point to a shoot. A product carries the garment image and the category that determines plate type, so a shoot launched from a product skips step one.

### 5.1 Product fields

| Field | Type | Required | Notes |
|---|---|---|---|
| Product name | Text | Yes | |
| SKU / product code | Text | Yes | Unique within account |
| External ID | Text | No | For PIM or e-commerce sync |
| **Segment** | Reference | **Yes** | Fast fashion, Occasion, Swimwear. The safety boundary (§5.3.1) |
| **Gender** | Enum | **Yes** | Womenswear / Menswear / Unisex. Narrows the casting at model browse. **Unisex shows both men's and women's models.** Only genders allowed by the sub-category are offered (FR-PRD-14a) |
| **Category** | Reference | Yes | Shirts, Jeans, Dresses. Descriptive |
| Sub-category | Reference | Yes | From the global taxonomy, scoped to the selected category |
| Brand | Reference | No | Selected from **Master data** (§5.4), not free text |
| Description | Long text | No | |
| **Primary image** | Image | Yes | Flat lay or ghost mannequin, plain background. Versioned — see §5.4 |
| Additional images | Image[] | No | Reference and detail shots. Never used for generation |
| Colourway | Reference | No | From Master data, carries a hex swatch. Multiple per product |
| Size set | Reference | No | From Master data. Used to suggest models of matching size |
| Fit | Enum | No | Slim, regular, relaxed, oversized. The only descriptive attribute kept as a field |
| Fabric | Reference | No | From Master data. Influences drape in the scene pass |
| Season / collection | Reference | No | From Master data |
| Price | Currency | No | |
| Status | Enum | Yes | Draft, Active, Archived |
| **Tags** | Reference[] | No | From the global vocabulary, filtered to those mapped to the sub-category (§5.4.2). Multi-valued |
| Shoot count | Derived | — | Number of completed shoots |
| Last shot | Derived | — | Date of most recent shoot |

The fields from Fit through Pattern are **shoot-relevant metadata**: they improve model and plate selection and feed the scene prompt. All optional, but the product page should indicate that completing them improves results.

### 5.2 Product management

| ID | Requirement | Priority |
|---|---|---|
| FR-PRD-01 | Create a product with the fields above; conditional fields appear based on category | Must |
| FR-PRD-02 | List view with search, filter by category, status, shoot state, staleness and tags, and sort | Must |
| FR-PRD-03 | Toggle between grid (image-led) and table (data-led) views | Should |
| FR-PRD-04 | Product detail page showing all fields, the active image, archived images (§5.5), and full shoot history | Must |
| FR-PRD-05 | Edit and archive. Archived products are hidden from shoot selection but retain history | Must |
| FR-PRD-06 | Delete, with warning if shoots exist. Deleting a product does not delete generated images | Must |
| FR-PRD-07 | **Start a shoot** from the product detail page, pre-seeding category and primary image | Must |
| FR-PRD-08 | Bulk import by CSV with column mapping, validation preview and per-row error reporting | Should |
| FR-PRD-09 | Bulk image upload matched to products by SKU in the filename | Should |
| FR-PRD-10 | Duplicate a product to create a colourway variant | Could |
| FR-PRD-11 | Image validation on upload is limited to **format, resolution and file size**. Minimum 1000px shortest edge | Must |
| FR-PRD-11a | **No automated assessment of image suitability.** Background, lighting, framing and garment presentation are the customer's responsibility | Must |
| FR-PRD-11b | Upload guidance is shown inline at the upload point — three good examples and three bad — not linked from a help article | Must |
| FR-PRD-11c | Terms of service state that image quality is the customer's responsibility and that credits are consumed regardless of input quality | Must |
| FR-PRD-12 | Uploaded images are screened for inappropriate content; failures are blocked with a clear message | Must |
| FR-PRD-13 | Product count against plan limit shown; blocked at limit with an upgrade route | Must |
| FR-PRD-14 | **Unisex** products show both men's and women's models at model browse. Womenswear and menswear show only their own | Must |
| FR-PRD-14a | The gender options offered are limited by the sub-category's gender applicability. A crop top (feminine only) offers Womenswear alone, never Unisex or Menswear | Must |
| FR-PRD-15 | **Segment, gender, category and sub-category lock once the product has been shot at least once.** They decide the base cut and plate, so changing them would leave past shoots disagreeing with the product they belong to | Must |
| FR-PRD-15a | Locked fields show as read-only with a short explanation and a "Contact support to change this" link. No self-service unlock at launch | Must |
| FR-PRD-15b | Support (Super admin) can edit a locked field. The change is written to the audit log with the old and new values and a reason, and existing shoots keep the values they were generated with | Must |
| FR-PRD-15c | Before the first shoot, all fields remain freely editable | Must |

### 5.3 Catalogue taxonomy and safety boundaries

Three levels, each answering a different question.

| Level | Examples | Owned by | Job |
|---|---|---|---|
| **Segment** | Menswear, Womenswear, Swimwear, Nightwear | Shootroom, granted per client | **Safety boundary.** Controls which products a client may shoot and which models may be paired with them |
| **Category** | Shirts, T-shirts, Jeans, Dresses, Sarees | Shootroom | Descriptive, for filtering. Carries **plate type** as a system field the user never chooses |
| **Sub-category** | Formal shirts, Bootcut jeans | Shootroom | Optional third level, only where it does real work |

**Segment and plate type are different axes.** Plate type says which half of the body the try-on replaces. Segment says what kind of shoot it is. A bridal lehenga and a fast-fashion maxi dress are both full-wear — same plate, entirely different casting.

#### 5.3.0 Base cut — why sub-categories matter

**Sub-categories are not descriptive. They shape the plate.**

Established by testing: a crop top mapped onto a plate wearing a full-length tank leaves the tank visible below the crop. A knee-length skirt onto full-length trousers leaves the trouser legs showing. The base garment must end where the real garment ends.

| ID | Requirement | Priority |
|---|---|---|
| FR-CUT-01 | Every sub-category carries a **base cut**, which determines where the base garment on the plate ends | Must |
| FR-CUT-02 | Base cuts: `top_standard`, `top_cropped`, `top_long`, `bottom_full`, `bottom_knee`, `bottom_short`, `full`. Many sub-categories share one cut — what matters is where the garment ends, not what it is called | Must |
| FR-CUT-03 | Plates are generated per base cut, not merely per plate type. `PLATE.T` is not one asset | Must |
| FR-CUT-04 | **A shoot loads only plates matching the sub-category's base cut.** A model without a plate of that cut does not appear | Must |
| FR-CUT-05 | Sub-categories record **gender applicability**. Crop tops are feminine only, so no masculine model needs a cropped plate | Must |
| FR-CUT-06 | A model is offered for a shoot only when it holds an approved plate of the required base cut, in addition to the segment pairing (§5.3.2) | Must |
| FR-CUT-07 | Selecting a sub-category with no plate coverage at all states so plainly, rather than returning an empty model list with no explanation | Must |
| FR-CUT-08 | Base cuts are seeded and maintained by Super admin. A client cannot create one | Must |

**Library impact.** Seven cuts instead of three plate types takes the library from 1,248 plates to up to 2,912 at 104 models. The bound is not reached in practice — gender applicability removes cropped cuts from masculine models. Build `top_standard`, `bottom_full` and `full` first; they cover most of a fast-fashion range.

#### 5.3.1 Why segments exist

Segments are **not a marketing taxonomy.** They exist to make an offensive garment-and-model combination impossible.

The unsafe outcome is never a segment alone or a model alone. Swimwear is a legitimate segment. Every model in the library is an adult. The risk lives entirely in the **pairing** — which is why permission is granted on the pair, not on either side.

| ID | Requirement | Priority |
|---|---|---|
| FR-SEG-01 | Segments are global, maintained by Super admin only, and granted per client | Must |
| FR-SEG-02 | A segment may be marked **sensitive**. A sensitive segment additionally requires an explicit model pairing before it can be used | Must |
| FR-SEG-03 | **Every product carries a segment. It is mandatory.** A product with no segment cannot be safety-checked and therefore cannot be shot | Must |
| FR-SEG-04 | A client may only assign segments they have been granted | Must |
| FR-SEG-05 | Segments a client does not hold are shown locked with a route to request access, never silently absent | Must |

#### 5.3.2 Segment–model pairing — the control

| ID | Requirement | Priority |
|---|---|---|
| FR-SEG-06 | A model may be used in a segment **only when an approved pairing exists.** Nothing else qualifies. A missing, pending, rejected or revoked record is equally not permitted | Must |
| FR-SEG-07 | Pairings are decided by a named staff member and recorded with actor, timestamp and reason. **No pairing is ever approved automatically**, by inference, by bulk default, or by a migration | Must |
| FR-SEG-07a | **Enabling a new segment creates a pending pairing for every model in the library.** The segment cannot be granted to any client until the review queue has been worked | Must |
| FR-SEG-07b | Each pairing carries a status of **pending, approved or rejected**. Only approved is visible to a client | Must |
| FR-SEG-07c | Rejections record a reason, so the same question does not have to be re-argued when the model or the segment is revisited | Must |
| FR-SEG-07d | The review queue shows, per segment, how many pairings are pending, approved and rejected, and who is reviewing | Must |
| FR-SEG-07e | A newly added model enters as **pending against every active segment**. It is invisible to clients until reviewed, so a new model can never arrive pre-approved | Must |
| FR-SEG-07f | For a **sensitive** segment, every pairing is reviewed individually. Batch approval after sampling is not permitted | Must |
| FR-SEG-07g | For a non-sensitive segment, a reviewer may approve a batch after examining a sample. The batch, the sample and the reviewer are recorded | Should |
| FR-SEG-08 | The model library is filtered by the product's segment **before** any other filter, including plate type. A model not paired with that segment does not appear | Must |
| FR-SEG-09 | The pairing is verified **again immediately before generation**, not only at selection. A model may be un-paired between the two, and a run in flight must not outlive the permission that authorised it | Must |
| FR-SEG-10 | A run whose pairing check fails is refused, consumes no credits, and is logged for review | Must |
| FR-SEG-11 | The run records the segment it was checked against and when the check passed, so the authorisation is auditable after the fact | Must |
| FR-SEG-12 | Revoking a pairing takes effect immediately for new runs. Existing assets are never deleted or hidden — the control governs generation, not history | Must |
| FR-SEG-12a | Revocation **preserves the record**. Who approved it, who withdrew it and why all survive. A revoked pairing is treated as absent by the filter but is never deleted | Must |
| FR-SEG-13 | Every pairing decision is written to the audit log and is not deletable | Must |

#### 5.3.3 Absolute boundaries

These are not permissions. They cannot be granted, configured, flagged on, or overridden by any role including Super admin.

| ID | Boundary | Priority |
|---|---|---|
| FR-SEG-14 | **No model in the library may depict a minor.** Age bands begin at 18–24 and the attribute vocabulary contains no younger value. No plate depicting a minor may be generated, stored or approved | Must |
| FR-SEG-15 | **Childrenswear is not a segment and never will be.** It is not a segment held back pending approval — it is absent from the model entirely, so there is nothing to switch on | Must |
| FR-SEG-16 | No combination of segment, category, sub-category, attribute or prompt may produce a model who reads as a minor | Must |
| FR-SEG-17 | Uploaded product images are screened for child imagery. A positive result blocks the upload and raises an internal review that the client cannot self-override | Must |
| FR-SEG-18 | These boundaries are enforced in code and covered by tests that fail the build if removed. They are not configuration | Must |

**Why childrenswear is absent rather than gated.** Making it a segment implies it could be switched on for the right client under the right conditions. It cannot. A boundary that must never move should not be modelled as a permission, because permissions are things people grant.

---

### 5.4 Master data

Lists the **client's** merchandising team maintains once and reuses across every product. They exist so that a brand, colour or fabric is spelled the same way on every record, filters group correctly, and a rename propagates rather than fragmenting the catalogue.

**Ownership.** Master data below is client-owned and edited by Owner and Admin. The catalogue taxonomy in §5.3 — segments, categories and sub-categories — is **Shootroom-owned and editable by Super admin only.** Clients select from it and may request access to gated levels, but cannot create, rename or reparent anything in it.

| Entity | Fields | Notes |
|---|---|---|
| Brands | Name, code, status | A single account may hold several labels |
| Colours | Name, hex swatch, status | Swatch renders on product cards and filters |
| Fabrics | Name, notes, status | Feeds drape and sheen in the scene pass |
| Seasons / collections | Name, year, status | Grouping and reporting |
| Size sets | Name, size list, status | Used to suggest models of matching garment size |

| ID | Requirement | Priority |
|---|---|---|
| FR-MD-01 | Each entity has a managed list: create, edit, archive. Applies to brands, colours, fabrics, seasons and size sets. **Tags are not client master data** (§5.4.1) | Must |
| FR-MD-02 | A value **in use by any product cannot be deleted**; it can only be archived | Must |
| FR-MD-03 | Archived values stay attached to existing products but do not appear when creating new ones | Must |
| FR-MD-04 | Each list shows how many products reference each value | Must |
| FR-MD-05 | Renaming a value propagates everywhere it is referenced; the previous name is retained in the audit log | Must |
| FR-MD-05a | Every master data record carries **who created it, who last edited it, and who archived it**, with timestamps. A rename can affect hundreds of products, so authorship is answerable without opening the audit log | Must |
| FR-MD-14 | A swatch is required when a colour is created. A colour with no swatch renders as nothing on a product card | Should |
| FR-MD-15 | Sheer fabrics warn at product creation and again before generation, since thin fabric can render skin where fabric should be | Must |
| FR-MD-06 | Product forms present these fields as selects sourced from master data, never as free text | Must |
| FR-MD-07 | A value can be added inline from the product form without losing form state | Should |
| FR-MD-08 | Sub-categories are **not** master data. They are global taxonomy (§5.3) and cannot be created by a client | Must |
| FR-MD-09 | Master data is per client. Nothing is shared between clients | Must |
| FR-MD-09a | The catalogue taxonomy (§5.3) is the opposite — global, shared, and not editable by any client role | Must |
| FR-MD-10 | Seed a new account with a sensible default set so the first product can be created without configuration | Must |
| FR-MD-11 | Bulk import and export of master data by CSV | Should |
| FR-MD-12 | Master data is editable by Owner and Admin only; Producers and Viewers select from it (§2.2) | Must |
| FR-MD-13 | CSV product import auto-creates missing master values, or reports them for review before import | Should |

#### 5.4.1 Tags — global vocabulary, mapped to sub-categories

Sleeve length, neckline, hem, garment length and pattern were product columns. They are now **tags**: multi-valued, mostly null on any given garment, and changing often enough that adding one should be data entry rather than a migration.

**Tags are Shootroom-owned, not client master data.** They feed the generation prompt, so a tag mapped to a sub-category fixes the prompt logic for that garment. If each client could edit the vocabulary, the same garment would generate differently for two customers and no prompt could be tuned centrally.

| ID | Requirement | Priority |
|---|---|---|
| FR-TAG-01 | Tags are a **global controlled vocabulary**, created and maintained by Super admin only | Must |
| FR-TAG-02 | Clients **select** tags. They cannot create, rename, archive or map them | Must |
| FR-TAG-03 | Each tag carries a **kind** — sleeve, neckline, hem, length, pattern, detail, occasion — so the product form groups them rather than presenting one long list | Must |
| FR-TAG-04 | A tag may carry a **prompt fragment**, the wording used in generation when it differs from the display name | Should |
| FR-TAG-05 | **Fit remains a field, not a tag.** It is single-valued, applies to every garment, and changes how the try-on drapes | Must |

#### 5.4.2 Sub-category to tag mapping

Every sub-category carries the set of tags it offers. Without it a polo offers "floor length" and a saree offers "cold shoulder" — noise at best, and at worst a nonsensical value reaching the generation prompt.

| ID | Requirement | Priority |
|---|---|---|
| FR-TAG-06 | Each sub-category is mapped to the tags that apply to it, authored by Super admin alongside the sub-category | Must |
| FR-TAG-07 | **A tag not mapped to the product's sub-category is not shown.** Hidden, not greyed — a list of things you cannot pick reads as broken | Must |
| FR-TAG-08 | Tag kinds with no mapped tags for a sub-category are omitted entirely. A pair of jeans shows no neckline group at all | Must |
| FR-TAG-09 | The tag section is unavailable until a sub-category is chosen, and says why | Must |
| FR-TAG-10 | Changing the sub-category **clears the selected tags**, since the applicable set has changed | Must |
| FR-TAG-11 | A mapping may mark a tag as **default**, pre-selected on a new product of that sub-category | Should |
| FR-TAG-12 | Creating a sub-category offers to **copy the mapping from an existing one** — "Polo, like T-shirt" — then adjust | Should |
| FR-TAG-13 | Editing a tag shows how many sub-categories reference it | Should |
| FR-TAG-14 | Removing a tag from a mapping does not strip it from existing products. It stops being offered on new ones | Must |

**The cost, accepted.** Roughly a dozen rows per sub-category, so around 400 across the catalogue, each authored by hand. A rule at the kind level would need seven rows instead, but introduces a third concept users would have to learn. Sub-category to tag is the familiar model from any PIM, and familiarity is worth the rows.

### 5.5 Product image versioning

The primary image is what the try-on maps onto, so a shoot is only correct with respect to the image it ran against. Replacing that image in place would silently invalidate every shoot already produced from it.

Images are therefore **never overwritten or deleted**. Uploading a replacement adds a new record and deactivates the previous one.

**Two garment images, not one.** A front image dresses the frontal, side and three-quarter poses. It cannot dress a back-view pose — there is nothing behind a flat lay — so a back image is a separate role, and the poses available in a shoot depend on which the product holds.

| ID | Requirement | Priority |
|---|---|---|
| FR-IMG-00 | A product carries a **required front image** and an **optional back image**. Both are garment images used for generation; additional images are reference only | Must |
| FR-IMG-00a | Each role is versioned independently. Replacing the back image does not disturb the front, and each keeps its own archive | Must |
| FR-IMG-00b | **Poses that require a back view are unavailable when the product has no back image**, with the reason stated and a route to add one | Must |
| FR-IMG-00c | The product page and product list show at a glance whether a back image exists, since it determines which poses can be shot | Should |
| FR-IMG-00d | A run records **which image of each role** it used, not merely which product | Must |
| FR-IMG-00e | Adding a back image to a product that has already been shot makes back poses available for new runs. Existing runs are unaffected | Must |
| FR-IMG-01 | The customer may replace either garment image at any time from the product page | Must |
| FR-IMG-02 | Replacement **adds a new image record with `is_active = true`** and sets the previous record to `is_active = false`. Nothing is overwritten or deleted | Must |
| FR-IMG-03 | Exactly one image per **role** per product is active at any time — one live front, one live back | Must |
| FR-IMG-04 | Every shoot records the **image ID it ran against**, not just the product ID | Must |
| FR-IMG-05 | Deactivating an image never alters, hides or invalidates assets already generated from it | Must |
| FR-IMG-06 | Front and back images are versioned. Additional reference images are freely editable, as they do not drive generation | Must |
| FR-IMG-07 | Each image record stores upload date, uploading member, and the shoot count produced from it | Should |

#### Archived images on the product page

| ID | Requirement | Priority |
|---|---|---|
| FR-IMG-08 | The product detail page shows an **Archived images** section listing every inactive image, **rendered greyed out** | Must |
| FR-IMG-09 | Each archived image shows when it was replaced, by whom, and how many shoots were produced from it | Must |
| FR-IMG-10 | Selecting an archived image shows the shoots and assets generated from it | Should |
| FR-IMG-11 | An archived image may be **restored to active**, which deactivates the current one by the same rule | Should |
| FR-IMG-12 | The section is hidden entirely when a product has never had its image replaced | Must |

#### Staleness

Versioning makes staleness detectable without any extra bookkeeping: a product whose active image is newer than its most recent shoot has imagery that no longer matches the product.

| ID | Requirement | Priority |
|---|---|---|
| FR-IMG-13 | A product is **stale** when its most recent shoot ran against an image that is no longer active | Must |
| FR-IMG-14 | Stale products are marked on the product page and in the product list | Must |
| FR-IMG-15 | Stale count appears on the dashboard alongside products without imagery. Both resolve the same way — run a shoot | Must |
| FR-IMG-16 | Assets from an inactive image remain downloadable, labelled as produced from a previous image. **Staleness is a label, not a block** — the customer paid for those images, and blocking them would punish improving product photography | Must |
| FR-IMG-17 | Filter the product list by stale | Should |

---

## 6. Module D — Shootroom

The four-step flow: **Product → Model → Poses → Review.**

**Every shoot is driven from a product.** The user selects what they are shooting and is never asked for a garment category, a plate type or a base cut — the product already carries all of it. This is what makes the safety check possible: a model cannot be verified as suitable for a garment the system knows nothing about.

#### Step 1 — Product

| ID | Requirement | Priority |
|---|---|---|
| FR-SHT-01 | Step 1 presents the client's **active products**. The user selects one | Must |
| FR-SHT-01a | **No garment category, plate type or base cut is asked for.** All are resolved from the product | Must |
| FR-SHT-01b | Four resolved values are shown, stated as derived rather than chosen: **segment** (which models may be paired), **gender** (narrows the casting), **base cut** (which plate loads), **plate type** (which half of the silhouette is replaced) | Must |
| FR-SHT-01c | A product missing segment, gender or sub-category cannot be shot. It is shown as incomplete with a route to fix it, never silently absent | Must |
| FR-SHT-01d | A product whose segment the client no longer holds cannot be shot, and the reason is stated | Must |
| FR-SHT-01e | Entering from a product page skips step 1 entirely | Must |
| FR-SHT-01f | Draft and archived products are not selectable | Must |
| FR-SHT-01g | Search and filter across the product list, since a catalogue may run to thousands | Must |
| FR-SHT-01h | **There is no ad-hoc path.** A shoot requires a product record | Must |
| FR-SHT-01i | A trial account is seeded with a **sample product**, so the demo shoot runs before the user has created anything | Must |

**Why products are mandatory.** An ad-hoc shoot would still require segment, gender and garment type to be supplied by hand, because the pipeline cannot resolve them otherwise. So an ad-hoc path is not "skip the product" — it is "give us the same facts and throw them away." Requiring a product keeps one path, makes every shoot traceable, and means shoot history and staleness work without exception.

**The cost, accepted deliberately.** A new user must create a product before their first shoot. FR-SHT-01i covers the trial case; beyond that, adding a product is the work the tool exists to make worthwhile.

#### Steps 2 to 4

| ID | Requirement | Priority |
|---|---|---|
| FR-SHT-02 | Step 2 — browse and filter the model library; select one model | Must |
| FR-SHT-02a | The library is filtered in three passes, all resolved from the product: **segment pairing** (§5.3.2), **gender**, then **base cut** (§5.3.0). A model must be paired with the product's segment *and* hold an approved plate of the sub-category's base cut | Must |
| FR-SHT-02b | The filter is silent, not a control. A model without the required plate is absent, not greyed — the same principle as booked models (FR-CAST-07) | Must |
| FR-SHT-02c | Result counts and coverage figures reflect the plate-type filter, so a stated count is always a count of models that can shoot this garment | Must |
| FR-SHT-02d | A model whose required plate is later retired stops appearing for new shoots. Existing runs and assets are unaffected | Must |
| FR-SHT-03 | Step 3 — select poses, base garment variant where applicable, and scene | Must |
| FR-SHT-03a | Back-view poses are shown only when the product holds a back image (FR-IMG-00b). Otherwise they are unavailable with the reason stated | Must |
| FR-SHT-04 | Step 4 — confirm the garment image from the product, select formats, review the credit cost, generate | Must |
| FR-SHT-04a | The run records the **product ID and the specific image ID** it was generated from (§5.5). Product ID alone is insufficient once images are versioned | Must |
| FR-SHT-05 | Shoot draft is saved automatically at every step and resumable after leaving | Must |
| FR-SHT-06 | Named, saved shoot configurations reusable against a different product | Should |
| FR-SHT-07 | Generation runs in the background; the user may leave the page and is notified on completion | Must |
| FR-SHT-08 | Live per-image progress with a stage label | Should |
| FR-SHT-09 | Cancel a running shoot; uncommitted credits are released | Must |
| FR-SHT-10 | Per-image actions on completion: select, regenerate, download | Must |
| FR-SHT-11 | Images rejected during approval are excluded from the set but retained for support review | Should |
| FR-SHT-12 | Favourite a model for quick access in later shoots | Should |
| FR-SHT-12a | A customer's booked cast is surfaced first in browse, ahead of the shared pool (§6.1) | Should — Phase 2 |
| FR-SHT-13 | Model detail view showing all attributes and available poses before selection | Should |
| FR-SHT-14 | Casting request from the empty filter state, capturing the filter combination | Must |
| FR-SHT-15 | Batch — one configuration across multiple products | Phase 2 |
| FR-SHT-16 | Build a custom model | **Phase 2 — explicitly out of scope for launch** |

---

## 6.1 Model availability and brand cast

Every customer draws from the same library. That is normal for stock imagery and the market accepts it, **provided it is stated plainly and never implied otherwise**. The risk is not sharing in general — it is collision: two competing labels in the same category and city shipping the same face.

Brand cast is the answer, and it is a revenue line rather than a risk control. A customer books models the way a brand books talent at an agency.

### 6.1.1 Availability model

| Value | Meaning |
|---|---|
| `shared` | In the general pool. Any customer may shoot with it |
| `reserved` | An existing library model booked by one account. Invisible to everyone else |
| `exclusive` | Built to one customer's brief, never entered the shared pool |
| `cooling` | Released, waiting out the cooling period before returning to `shared` |
| `retired` | Withdrawn. Historical runs still resolve |

Model record fields: `availability`, `reserved_to` (account ID or null), `reserved_from`, `reserved_until`, `cooling_until`.

`availability` alone is insufficient — the system must know **who** holds a model and **until when**, which is why the holder and the dates are separate fields rather than encoded in a single status.

### 6.1.2 How booking works

| ID | Requirement | Priority |
|---|---|---|
| FR-CAST-01 | A plan includes a number of **bookable models**. Zero on entry tiers | Must — Phase 2 |
| FR-CAST-02 | A customer books a `shared` model from browse or its detail view, moving it to `reserved` against their account | Must — Phase 2 |
| FR-CAST-03 | **Booking runs with the subscription, not for a fixed term.** The customer holds the model while subscribed and releases it by unbooking or cancelling | Must |
| FR-CAST-04 | Booking beyond the plan allowance is blocked, with the current count and an upgrade route | Must |
| FR-CAST-05 | Unbooking is immediate and returns the model to `cooling` | Must |
| FR-CAST-06 | Cancellation or non-payment moves every booked model to `cooling` at the end of the access period | Must |

**Why not a fixed term.** A six-month booking creates a renewal moment where the customer has already shot their entire catalogue on that face and is negotiating under duress. Continuous-while-subscribed avoids that and matches how the rest of billing already works.

### 6.1.3 Visibility

| ID | Requirement | Priority |
|---|---|---|
| FR-CAST-07 | A model reserved or exclusive to another account is **not shown at all** — not greyed, not labelled, not present | Must |
| FR-CAST-08 | **Availability is applied to the query, not to the results.** A booked model must be invisible to the search itself, so a customer never sees a gap where a result would have been | Must |
| FR-CAST-09 | Result counts, filter counts and coverage figures are computed against the visible library only | Must |
| FR-CAST-10 | When filters return nothing because matches are booked elsewhere, the customer sees the standard empty state and casting-request route, with no indication that a match exists but is held | Must |
| FR-CAST-11 | A customer's own booked models are marked in their browse view as part of their cast | Must |

**Why hidden rather than locked.** Showing a booked model greyed out tells a competitor exactly which faces a brand has taken — information about their campaign they never agreed to share. It also makes the library feel smaller than it is: a grid of things you cannot have reads as a paywall. The counter-argument, that visible locks drive urgency to book, is not worth leaking a customer's casting choices.

### 6.1.4 Cooling period

| ID | Requirement | Priority |
|---|---|---|
| FR-CAST-12 | A released model enters `cooling` for **90 days** before returning to `shared` | Must |
| FR-CAST-13 | During cooling the model is invisible to every account, including the one that released it | Must |
| FR-CAST-14 | The cooling period is disclosed at the point of booking, not buried in terms | Must |
| FR-CAST-15 | If the original holder resubscribes during cooling, the booking resumes rather than restarting | Should |

Releasing immediately would let an ex-customer find "their" model on a competitor within weeks. Retiring permanently wastes an asset that cost money to build. Ninety days is the compromise.

### 6.1.5 Protecting the shared pool

| ID | Requirement | Priority |
|---|---|---|
| FR-CAST-16 | **Every booking triggers generation of a replacement model for the shared pool**, matched to the same fit archetype | Must |
| FR-CAST-17 | The shared pool must never fall below a defined floor. Booking is suspended if it would breach that floor | Must |
| FR-CAST-18 | Booking revenue is reported against library growth so the two stay linked | Should |

Without FR-CAST-16 the feature quietly destroys the product: ten customers booking three models each strips thirty faces from a library of a hundred, and every non-booking customer sees a depleted catalogue. Done correctly, exclusivity revenue **funds** library expansion rather than cannibalising it.

### 6.1.6 Exclusive casting

| ID | Requirement | Priority |
|---|---|---|
| FR-CAST-19 | A customer may commission a model built to their brief, which never enters the shared pool | Could — Phase 3 |
| FR-CAST-20 | Priced as a one-off build plus a recurring exclusivity fee | Could — Phase 3 |
| FR-CAST-21 | Commissioned models pass the same QA gate as library models before use | Must, if built |

### 6.1.7 Commitments and language

| ID | Requirement | Priority |
|---|---|---|
| FR-CAST-22 | Terms of service state plainly that models are shared across customers and that no exclusivity is implied on standard plans | Must — Phase 1 |
| FR-CAST-23 | Exclusivity is described as **"not available to any other Shootroom customer."** Never as "unique" — no guarantee can be made about other tools producing a similar face | Must |
| FR-CAST-24 | Availability fields exist from launch and remain null. The feature ships once the library passes 150 models | Must |

**Launch position: shared only.** With a launch library of roughly 48 models, reserving even one leaves a visible hole. Build the fields, ship the honesty in the terms, switch the feature on in Phase 2.

---

## 6.2 Garment category policy

Base plates wear a minimal neutral outfit by design, so the try-on has a clean silhouette to work against. For almost every category the garment covers it entirely. For a small set of categories it does not, and the output becomes a synthetic person in underwear — a problem that exists before the customer's garment is involved at all.

Categories are therefore tiered, and **the tier is enforced at the category field, not at image upload.** Deciding at upload means a customer has already prepared a product and spent time before being refused.

### 6.2.1 Tiers

| Tier | Categories | Status |
|---|---|---|
| **Standard** | Topwear, bottomwear, dresses, co-ords, sarees, jumpsuits, outerwear, most activewear | Phase 1 |
| **Restricted** | Swimwear, lingerie, sports bras, bodysuits, sheer and semi-sheer fabrics | Phase 3 |
| **Prohibited** | Any garment for children; anything that is not a garment | Permanent |

### 6.2.2 Standard categories

| ID | Requirement | Priority |
|---|---|---|
| FR-CAT-01 | Only Standard categories are selectable at launch. The three garment types map to them exactly | Must |
| FR-CAT-02 | Sub-category taxonomy (§5.3) cannot be extended into a Restricted or Prohibited category by a customer | Must |
| FR-CAT-03 | Sheer and semi-sheer fabrics are flagged in the Fabric master list and warn at product creation that results may be unreliable | Should |

### 6.2.3 Restricted categories — Phase 3

These need a different pipeline, not a configuration flag.

| ID | Requirement | Priority |
|---|---|---|
| FR-CAT-04 | **Restricted categories do not use try-on.** The model is generated already wearing the garment, using the product image as reference. The minimal base plate is never created or stored | Must, if built |
| FR-CAT-05 | Restricted plates are never added to the shared library and are not reusable across runs | Must, if built |
| FR-CAT-06 | Restricted sub-categories carry `RequiresApproval` and are granted per client after a manual eligibility check (§5.3), never self-served | Must, if built |
| FR-CAT-07 | Every restricted output passes human review before it can be downloaded, regardless of the account's approval setting (§7.1) | Must, if built |
| FR-CAT-08 | Restricted outputs are excluded from bulk download and from any future channel push | Must, if built |
| FR-CAT-09 | Restricted runs carry their own retention policy, shorter than standard assets | Should, if built |

**Why a separate pipeline.** Removing try-on removes the minimal plate from existence. Nothing near-naked is generated, stored or reusable, which resolves the provider-filter problem and the asset-risk problem at the same time.

### 6.2.4 Prohibited categories

| ID | Requirement | Priority |
|---|---|---|
| FR-CAT-10 | **Childrenswear is not supported and will not be.** Every model in the library is an adult by design, and no plate depicting a minor may exist under any circumstance | Must — Phase 1 |
| FR-CAT-11 | The refusal is stated plainly in the terms, in the help centre, and at the category field — not discovered mid-flow | Must — Phase 1 |
| FR-CAT-12 | Product uploads are screened for child imagery. A positive result blocks the upload and raises an internal review, and cannot be self-overridden by the customer | Must — Phase 1 |
| FR-CAT-13 | No attribute, prompt or filter combination may produce a model who reads as a minor. Age bands start at 18–24 and the vocabulary contains no younger value | Must — Phase 1 |

**Commercial note.** Childrenswear is a real limitation. Most Indian apparel brands of any size carry a kids line and will ask. Sales needs a clear, prepared answer rather than discovering this in a call.

### 6.2.5 Handling a provider refusal

| ID | Requirement | Priority |
|---|---|---|
| FR-CAT-14 | A generation refused on content-policy grounds must be distinguishable from a system failure | Must |
| FR-CAT-15 | **A policy refusal consumes no credits** and is not retried automatically | Must |
| FR-CAT-16 | The customer is told the request was declined on content grounds, without exposing which classifier fired or how it was triggered | Must |
| FR-CAT-17 | Repeated refusals on one account raise an internal flag for review | Should |

### 6.2.6 To test before Phase 1 ships

These change the launch scope if they fail, so they are validation tasks rather than requirements.

| # | Test | If it fails |
|---|---|---|
| T1 | Will the provider generate the `PLATE.F` base — a fitted tank and mid-thigh shorts? | Full look is at risk, not only swimwear. Base outfit must change |
| T2 | Does try-on render a sheer or semi-sheer garment without showing skin through it? | Sheer fabrics move to Restricted, affecting standard categories |
| T3 | Does a policy refusal return a distinguishable response? | FR-CAT-14 and FR-CAT-15 cannot be implemented and customers get charged for blocks |

---

## 7. Module E — Assets and shoot history

| ID | Requirement | Priority |
|---|---|---|
| FR-AST-01 | Library of every generated image, filterable by product, model, pose, format, date, approval state and selection | Must |
| FR-AST-02 | Shoot detail view showing the configuration used, the source image version, and every image produced | Must |
| FR-AST-03 | Download a single image, a selection, or an entire shoot as a zip | Must |
| FR-AST-04 | Images are downloadable indefinitely while the account is active; retention after cancellation is stated in the plan | Must |
| FR-AST-05 | Re-run a past shoot with the same configuration. If the product image has since changed, the re-run uses the **active** image and says so | Should |
| FR-AST-06 | Delete images; deletion does not refund credits | Must |
| FR-AST-07 | **Select** an image — a merchandising pick, default off, independent of approval. Marks which images go to the product page | Must |
| FR-AST-10 | Regenerate a single image for 1 credit, from the asset library as well as from the run | Must |
| FR-AST-11 | Contact support about a run, with run and image references attached automatically (§4.1.2) | Must |
| FR-AST-08 | Storage used against plan limit shown | Should |
| FR-AST-09 | Push directly to connected channels or storage | Could — Phase 2 |

### 7.1 Approval workflow

Producers do the work; Owners and Admins sign it off. **Approval gates download**, so imagery cannot reach a live site until someone with commercial authority has looked at it.

**Approval is opt-in per account.** A solo user holds Owner and would otherwise approve their own work forever, which is pure ceremony. The states exist from launch but stay dormant until switched on.

#### States

```
Draft ─▶ Awaiting approval ─▶ Approved
              ▲                    │
              │                    ▼
        Changes requested ◀── (regenerate)
```

| ID | Requirement | Priority |
|---|---|---|
| FR-APP-01 | Account setting: **require approval before download**. Off by default | Must |
| FR-APP-02 | With approval off, completed runs go straight to Approved and no review UI is shown | Must |
| FR-APP-03 | With approval on, a run completed by a Producer enters **Awaiting approval** | Must |
| FR-APP-04 | A run completed by an Owner or Admin enters **Approved**, recorded as approved on creation by that actor — the audit trail must not imply a review took place | Must |
| FR-APP-05 | **Approval is granted at run level**, with the option to drill in and reject individual images. Per-image approval as the default would create an approval treadmill and invite rubber-stamping | Must |
| FR-APP-06 | Two outcomes: **Approved**, or **Changes requested** with a mandatory reason routed back to the Producer | Must |
| FR-APP-07 | Changes requested returns the run to the Producer, who may regenerate affected images and resubmit. Resubmission returns it to Awaiting approval | Must |
| FR-APP-08 | Regeneration of an approved image returns that image — not the whole run — to Awaiting approval | Must |
| FR-APP-09 | An approver may approve a run with individual images rejected; rejected images stay undownloadable and are excluded from the set | Must |

#### Download gating

| ID | Requirement | Priority |
|---|---|---|
| FR-APP-10 | Producers and Viewers can download **approved images only** | Must |
| FR-APP-11 | Producers may download a **watermarked preview** of images awaiting approval — enough to check the work, not enough to publish | Must |
| FR-APP-12 | Viewers cannot download or preview anything awaiting approval | Must |
| FR-APP-13 | Owners and Admins may download any image in any state | Must |
| FR-APP-14 | Bulk download of a run excludes images that are not approved, and says how many were excluded and why | Must |
| FR-APP-15 | The download control is visible but disabled for gated images, with the reason stated. Hiding it entirely reads as a bug | Must |

#### Review experience

| ID | Requirement | Priority |
|---|---|---|
| FR-APP-16 | Approval queue listing runs awaiting approval, with product, model, submitter, image count and age | Must |
| FR-APP-17 | Review view shows every image at a size large enough to judge, with per-image approve or reject | Must |
| FR-APP-18 | Approvers are notified in-app and by email when a run is submitted | Must |
| FR-APP-19 | Producers are notified on approval or on changes requested, with the reason | Must |
| FR-APP-20 | Runs awaiting approval appear on the dashboard for approvers, with age surfaced so nothing stalls silently | Must |
| FR-APP-21 | Every state change records actor, timestamp, reason and the images affected. The log is immutable | Must |
| FR-APP-22 | Delegate approval to a named Admin for a date range, so absence does not stall production | Could — Phase 2 |

**Scope of the control.** This is a governance control, not enforcement. A Producer sees every image on screen and can screenshot it. What the gate provides is a clear line — an unapproved image is one nobody signed off, that fact is logged, and downloading it required a deliberate act by someone with authority. That is enough to keep an honest team honest, and enough to establish accountability when something reaches a live site that should not have. It is not a technical barrier, and it should not be described to customers as one.

### 7.2 Disclosure and provenance

Shootroom generates the imagery; **the customer publishes it.** Disclosure obligations attach to the published image and vary by market, so the platform supplies the capability and the customer decides how to use it.

The strongest protection is structural: **no real person is involved at any point.** Models are wholly synthetic, no likeness is captured, and there is no consent, release or personality right in play. That removes the largest category of risk before disclosure is considered at all.

#### Watermark — customer controlled

| ID | Requirement | Priority |
|---|---|---|
| FR-DIS-01 | Account setting to enable a **visible disclosure watermark** on generated images. Off by default | Must |
| FR-DIS-02 | The watermark **text is configurable**. Markets and platforms require different wording, so no phrasing is hard-coded | Must |
| FR-DIS-03 | Position, size and opacity are configurable, with sensible defaults | Should |
| FR-DIS-04 | The watermark is **applied at download, not burned in at generation**. One clean master is retained, so a change of policy needs no regeneration | Must |
| FR-DIS-05 | A live preview shows the watermark on a real generated image before the setting is saved | Should |
| FR-DIS-06 | The setting applies account-wide, and to every format and every download route | Must |
| FR-DIS-07 | Owners and Admins may change the setting; Producers and Viewers may not | Must |

#### Provenance metadata — always on

| ID | Requirement | Priority |
|---|---|---|
| FR-DIS-08 | Every generated image carries **embedded provenance metadata** recording that it is AI generated. Not customer-configurable and not removable | Must |
| FR-DIS-09 | Provenance is invisible, costs nothing at the point of use, and is increasingly what platforms and regulators check for | Must |
| FR-DIS-10 | Provenance survives format conversion and resizing within the platform's own pipeline | Should |
| FR-DIS-11 | Internal records link every delivered image to its model, plate, prompt and generation run, so the synthetic origin of any image can be evidenced on challenge | Must |

**Why this is not optional.** The claim that models are synthetic is one the platform may need to prove, not merely assert. Provenance records are that evidence, and they cost nothing to keep.

#### Onboarding checklist

Rather than interpreting law on the customer's behalf, disclosure is raised as a **checklist item during onboarding**, so it is a decision the customer has consciously taken.

| ID | Requirement | Priority |
|---|---|---|
| FR-DIS-12 | Onboarding includes a disclosure step prompting the customer to confirm with their own legal or compliance team what their markets require | Must |
| FR-DIS-13 | The step explains what the platform provides — configurable watermark, embedded provenance — and what it does not: legal advice or a view on any jurisdiction | Must |
| FR-DIS-14 | The customer records a decision: watermark enabled with wording, or explicitly declined. The decision, actor and timestamp are stored | Must |
| FR-DIS-15 | The step is skippable but reappears until answered, and is revisitable from settings at any time | Must |
| FR-DIS-16 | Changing the decision later is logged with actor and timestamp | Must |

#### Terms and guidance

| ID | Requirement | Priority |
|---|---|---|
| FR-DIS-17 | Terms of service state that the **customer is the publisher** and is responsible for disclosure in the markets they sell into | Must |
| FR-DIS-18 | Terms state that all models are wholly synthetic and that no real person's likeness is used or implied | Must |
| FR-DIS-19 | A help page explains disclosure in plain terms and how to enable the watermark, so no customer can say the subject was never raised | Must |
| FR-DIS-20 | No marketing or in-product copy asserts compliance with any specific regulation | Must |

#### What does not transfer to the customer

| ID | Requirement | Priority |
|---|---|---|
| FR-DIS-21 | **Accuracy of depiction remains the platform's responsibility.** Try-on output must not make a garment drape, fit or colour better than the real product. A disclosure watermark does not remedy an inaccurate depiction | Must |
| FR-DIS-22 | Written confirmation is obtained from the generation provider regarding training data and the synthetic status of outputs | Must |

---

## 8. Module F — Dashboard

The landing page after sign-in. It answers three questions: what state is my catalogue in, what have I produced, and how much runway do I have left.

| ID | Requirement | Priority |
|---|---|---|
| FR-DSH-01 | Credit balance, plan name, and renewal or trial expiry date | Must |
| FR-DSH-01a | On an annual plan, the date of the next monthly credit release, and how much of the current balance is rolled over | Should |
| FR-DSH-02 | Total products, split **with shoots** and **without shoots** | Must |
| FR-DSH-03 | Products without shoots is an actionable list, not just a number — it is the primary call to action | Must |
| FR-DSH-03a | Products with **stale imagery** (§5.4) appear alongside it, resolved the same way | Must |
| FR-DSH-04 | Total shoots completed, and total images generated | Must |
| FR-DSH-05 | Credits consumed over time, with a period selector | Should |
| FR-DSH-06 | Recent shoots with thumbnails and status | Must |
| FR-DSH-07 | Most-used models, so a user can see their own cast forming | Should |
| FR-DSH-08 | Shoots by category and by model, for coverage gaps | Could |
| FR-DSH-09 | In-progress and failed runs surfaced prominently with a resolution route | Must |
| FR-DSH-12 | For approvers: runs awaiting approval, with age, as a distinct call to action | Must |
| FR-DSH-13 | For Producers: own runs awaiting approval or with changes requested | Must |
| FR-DSH-10 | Empty state for a new account guides to the first product or a demo shoot | Must |
| FR-DSH-11 | Trial countdown while on trial | Must |

---

## 9. Module G — Subscription, billing and invoices

| ID | Requirement | Priority |
|---|---|---|
| FR-BIL-01 | Plans page comparing tiers: monthly credits, product limit, storage, included seats, additional seat price, viewer allowance, **bookable models**, support | Must |
| FR-BIL-01a | The plans page states clearly that **Viewers are free** and do not consume a seat | Should |
| FR-BIL-02 | Subscribe, with monthly and annual terms and the annual saving shown | Must |
| FR-BIL-03 | Upgrade takes effect immediately with prorated charge; downgrade takes effect at renewal | Must |
| FR-BIL-04 | Cancel at period end, with retained access until then and a clear statement of what happens to credits, products and images | Must |
| FR-BIL-05 | Reactivate a cancelled subscription | Must |
| FR-BIL-06 | Manage payment methods; set a default | Must |
| FR-BIL-07 | Billing address and tax identifier, including GST for Indian customers | Must |
| FR-BIL-07a | Billing details are collected on the **provider's hosted checkout**, not on a form we build. Card data never reaches our servers and tax id validation is the provider's | Must |
| FR-BIL-07b | The billing profile is populated from the checkout-completion event and kept current by the customer-updated event | Must |
| FR-BIL-07c | **Only the Owner may view or edit billing details.** It carries tax identity and commits spend | Must |
| FR-BIL-07d | Platform admin may correct a billing profile for a support case, with an audit entry. It changes tax treatment, so it is never a casual edit | Should |
| FR-BIL-07e | The reconciliation job checks for subscriptions whose client has no billing profile, so a dropped webhook cannot leave a paying customer without one | Must |
| FR-BIL-07f | Confirm during provider setup whether hosted checkout collects a GSTIN in our configuration. If not, the GSTIN is collected before redirect and passed into the session | Must |
| FR-BIL-08 | Invoice list with number, date, amount, status; downloadable PDF | Must |
| FR-BIL-08a | Prices are mirrored locally in the smallest currency unit for display and estimates. **Charging always uses the provider's price object** — the mirror is never the basis of a charge | Must |
| FR-BIL-08b | The mirror is kept current by the provider's price-update webhook, so a price edited in the provider dashboard cannot silently diverge from what customers are shown | Must |
| FR-BIL-08c | A price is never edited. A change creates a new price and retires the old one, so existing subscribers stay on the price they signed up at | Must |
| FR-BIL-09 | Invoices are tax compliant for the billing country | Must |
| FR-BIL-09a | The payment provider raises, taxes, renders and collects every invoice. Nothing is calculated locally; the platform mirrors the outcome | Must |
| FR-BIL-09b | Credits are released **only** on a confirmed payment event. No earlier invoice event may trigger a release | Must |
| FR-BIL-09c | Every webhook handler is idempotent on the provider's event id, because retries are normal rather than exceptional | Must |
| FR-BIL-09d | A reconciliation job periodically polls the provider for invoices not recorded locally, so a missed or undelivered webhook cannot leave a paying customer without credits | Must |
| FR-BIL-09e | Webhook endpoints verify the provider's signature before processing | Must |
| FR-BIL-09g | Every event is **stored before it is acted on**, and acknowledged immediately. Processing happens asynchronously so a slow handler cannot cause a duplicate delivery | Must |
| FR-BIL-09h | The provider's event id is the primary key, so duplicate delivery is rejected by the database rather than by application logic | Must |
| FR-BIL-09i | The raw payload is retained, so a handler fixed after a defect can replay historical events without asking the provider to resend | Must |
| FR-BIL-09j | Events record the resolved client and provider customer, so support can retrieve every billing event for a client directly | Should |
| FR-BIL-09k | Our own client identifier is passed in the checkout session metadata, so an event can be attributed even before a billing profile exists | Must |
| FR-BIL-09l | Repeated processing failures on an event raise an alert. An unprocessed payment event means a paying customer is waiting on credits | Must |
| FR-BIL-09m | Event payloads are cleared after 90 days; the event ids are retained longer, as they remain the idempotency guard | Should |
| FR-BIL-09f | Revenue reporting reads invoices. Subscription periods describe entitlement, not income | Must |
| FR-BIL-10 | Plan credits are granted at the start of each billing month, on monthly and annual plans alike | Must |
| FR-BIL-10a | **Annual plans are charged in full up front but release credits monthly.** The customer receives the annual discount; credits arrive at the same rate as a monthly plan | Must |
| FR-BIL-10b | Unused plan credits **roll over to the following month**, subject to the plan's rollover cap (§9.3) | Must |
| FR-BIL-10c | The plans page states the monthly credit allowance, not an annual total. "600 credits a month, billed annually" — never "7,200 credits a year", which implies they arrive together | Must |
| FR-BIL-10d | Cancelling an annual plan mid-term stops future monthly releases. This is stated at purchase, not discovered later | Must |
| FR-BIL-10e | The credit ledger shows each monthly release as its own entry, with the rolled-over balance carried in | Must |
| FR-BIL-10f | Purchased credit packs are separate from plan credits and follow FR-CR-17 (§4.3) | Must |
| FR-BIL-11 | Failed payment triggers a dunning sequence before suspension; access degrades to read-only rather than locking out | Must |
| FR-BIL-12 | Billing email address separate from the login email | Should |
| FR-BIL-13 | Usage-based overage instead of hard blocking | Could — Phase 3. Requires a stored payment method, a spend cap and a dunning path; blocking is the launch behaviour |

### 9.1 Seats and additional users

Seats are sold with the plan and charged for beyond it. The model grows revenue with the customer's own team rather than forcing a tier jump to add one colleague.

| ID | Requirement | Priority |
|---|---|---|
| FR-SEAT-01 | Each plan includes a number of **billable seats**. Additional seats are charged monthly per seat | Must — Phase 2 |
| FR-SEAT-02 | **Viewers are not billable.** Read-only access is free, so agencies and stakeholders can be given the output without a charge that discourages it | Must |
| FR-SEAT-03 | Billable seat count is the number of **active** Owner, Admin and Producer members. Viewers and revoked members are excluded | Must |
| FR-SEAT-04 | Viewers are capped per plan. Free access must be generous but finite, or an account can carry hundreds of logins at no cost | Must |
| FR-SEAT-05 | Inviting beyond the included seats states the additional monthly cost and requires explicit confirmation before the invitation is sent | Must |
| FR-SEAT-06 | **Promoting a Viewer to Producer, Admin or Owner is a purchase.** It warns, states the cost, and requires confirmation before taking effect | Must |
| FR-SEAT-07 | Demoting a member to Viewer, or revoking them, **frees the seat immediately** and reduces the billed quantity at once, not at renewal | Must |
| FR-SEAT-08 | Seat changes are prorated by the payment provider. Shootroom does not calculate proration | Must |
| FR-SEAT-09 | Only the Owner may add paid seats, since it commits spend (§2.2) | Must |
| FR-SEAT-10 | Included seats are **copied onto the subscription** at the point of subscribing, so a later change to the plan never silently alters what an existing subscriber is billed | Must |
| FR-SEAT-11 | The member list shows which members occupy a billable seat and the current monthly seat cost | Should |
| FR-SEAT-12 | A plan may cap the number of paid seats. Beyond it, an upgrade is required | Should |

### 9.2 Usage and storage

| ID | Requirement | Priority |
|---|---|---|
| FR-USE-01 | Every delivered image records its **byte size** | Must |
| FR-USE-02 | A running total per client holds storage bytes, image count, product count, billable seats and viewers. Reads never aggregate across the image table | Must |
| FR-USE-03 | Totals are maintained on delivery and deletion, with a nightly reconciliation job that recomputes them and alerts on drift | Must |
| FR-USE-04 | Storage used against the plan allowance is shown on the dashboard and in billing | Must |
| FR-USE-05 | Approaching the allowance warns at 80% and at 100%. Exceeding it blocks **new runs**, never access to existing assets | Must |
| FR-USE-06 | Deleting assets frees storage immediately | Must |
| FR-USE-07 | Storage is not sold as an overage at launch. Exceeding it means upgrading or deleting | Should |

**On the commercial weight of storage.** At roughly 400KB per delivered image, a client shooting 500 products a year accumulates around 5GB — a trivial hosting cost for years. Storage is therefore a **retention** question rather than a cost one: its commercial value lies in what happens to a customer's archive when they stop paying, not in charging by the gigabyte. That decision is F6.

### 9.3 Credit rollover

| ID | Requirement | Priority |
|---|---|---|
| FR-ROLL-01 | Unused credits carry into the following month on monthly and annual plans alike | Must |
| FR-ROLL-02 | A plan may cap the carry-forward. Anything above the cap **expires at the release** | Must |
| FR-ROLL-03 | The cap is a plan attribute, usually expressed as a multiple of the monthly allowance. Null means uncapped | Must |
| FR-ROLL-04 | Expiry is written to the ledger as its own entry, so a customer sees what carried and what lapsed rather than watching a balance drop | Must |
| FR-ROLL-05 | Order at each release: compute carry-forward, expire the excess, then grant the new allowance. The customer is never briefly over the cap | Must |
| FR-ROLL-06 | Purchased pack credits are **not** subject to the rollover cap. They were paid for separately | Must |
| FR-ROLL-07 | The cap and the amount at risk are shown before it applies, with at least seven days' warning | Should |

### 9.4 Pausing a subscription

A client with no shoots planned may pause rather than cancel, keeping every product, asset and setting intact.

| ID | Requirement | Priority |
|---|---|---|
| FR-PAUSE-01 | An Owner may pause an active subscription | Must — Phase 2 |
| FR-PAUSE-02 | While paused: **no invoice is raised and no credits are released** | Must |
| FR-PAUSE-03 | While paused the client is read-only, on the same terms as FR-ROL-02a. Nothing they own is deleted or hidden | Must |
| FR-PAUSE-04 | The maximum pause duration is a **system-level configuration value**, overridable per plan | Must |
| FR-PAUSE-05 | Pause days consumed are tracked per subscription year, so the allowance cannot be reset by pausing repeatedly | Must |
| FR-PAUSE-06 | The client may resume at any time. Resuming restarts billing and the credit release schedule from that date | Must |
| FR-PAUSE-07 | Pausing an annual plan **extends the term by the paused days** rather than consuming them | Must |
| FR-PAUSE-08 | Reminders are sent before the pause allowance expires | Must |
| FR-PAUSE-09 | If the allowance expires without a resume, the subscription enters the standard grace period | Must |
| FR-PAUSE-10 | Pause and resume are recorded as subscription periods, so the history reads correctly | Must |

### 9.5 Credit expiry and restoration

| ID | Requirement | Priority |
|---|---|---|
| FR-EXP-01 | If grace ends without payment, the credit balance is taken to zero. Every carried credit lapses | Must |
| FR-EXP-02 | Expiry is a **ledger entry with a negative delta**, never a deleted or mutated balance. The history stays readable | Must |
| FR-EXP-03 | The customer is warned before it happens, stating the balance at risk and the date | Must |
| FR-EXP-04 | Products, images and settings are **never** deleted by credit expiry. Only the balance is affected | Must |
| FR-EXP-05 | **Super admin may restore expired credits** as an `AdminGrant` entry with a mandatory reason, for goodwill on reactivation | Must |
| FR-EXP-06 | Restoration is capped at the amount that expired and is fully audit logged | Must |
| FR-EXP-07 | No self-service restoration. It is a staff action only | Must |

### 9.6 Subscription history and usage snapshots

| ID | Requirement | Priority |
|---|---|---|
| FR-HIST-01 | A subscription is **one record for its whole life**. Renewals move the period forward; they do not create subscriptions | Must |
| FR-HIST-02 | Every billing period is recorded as a child row holding the plan, price, seats and amount **as they were then** | Must |
| FR-HIST-03 | A mid-period change closes the current period and opens a new one. Periods are never edited | Must |
| FR-HIST-04 | Monthly usage is captured as a snapshot per client per month: credits opened, granted, purchased, consumed, expired, closed, plus runs, images, products, storage and seats | Must |
| FR-HIST-05 | Snapshots are idempotent per client and month, so a retried job cannot double-write | Must |
| FR-HIST-06 | The snapshot job verifies that opening plus grants minus consumption equals closing, and alerts on any discrepancy between the ledger and the cached balance | Must |
| FR-HIST-07 | Charts and historical figures read snapshots, never aggregating the ledger or the image table | Must |

---

## 10. Module H — Notifications

| ID | Requirement | Priority |
|---|---|---|
| FR-NTF-01 | Transactional email: welcome and activation, password reset OTP, email change, payment receipt, failed payment, subscription changes | Must |
| FR-NTF-02 | Shoot complete notification, in-app and by email | Must |
| FR-NTF-03 | Shoot failed notification with the reason and a retry route | Must |
| FR-NTF-03a | Run submitted for approval — to approvers | Must |
| FR-NTF-03b | Run approved, or changes requested with the reason — to the submitting Producer | Must |
| FR-NTF-04 | Credit warnings at 20% and zero; trial reminders at 7 days, 2 days and expiry | Should |
| FR-NTF-05 | In-app notification centre with read state. Behind `Features:InAppNotifications`, off at launch (§13.1) | Should |
| FR-NTF-06 | Per-category email preferences. **Transactional email — receipts, password resets, activation — is not opt-out and has no preference record** | Must |
| FR-NTF-07 | Preferences are held per user **per client**, so the same person may choose differently at each client they belong to | Must |
| FR-NTF-08 | Absence of a preference row means **use the category default**, defined in code. A missing row is never read as off | Must |
| FR-NTF-09 | Only categories relevant to a user's role are shown. Approval requests to approvers, approval outcomes to producers | Should |
| FR-NTF-10 | The in-app channel is stored per category from launch so enabling the feature later needs no migration | Must |

---

## 11. Module I — Platform administration

Internal only. Separate from the Plate Console described in `shootroom-prd.md` §12.

| ID | Requirement | Priority |
|---|---|---|
| FR-ADM-01 | Search accounts; view plan, credits, usage and shoot history | Must |
| FR-ADM-02 | Grant, adjust or expire credits with a mandatory reason, recorded in the ledger | Must |
| FR-ADM-03 | Suspend or reinstate an account | Must |
| FR-ADM-04 | Issue refunds and credit notes | Must |
| FR-ADM-05 | Review the casting request queue from FR-SHT-14 | Must |
| FR-ADM-06 | Review output-quality tickets raised through support, with run provenance attached | Should |
| FR-ADM-07 | Review content-moderation blocks from FR-PRD-12 and override false positives | Must |
| FR-ADM-08 | Publish, unpublish and retire models in the library | Must |
| FR-ADM-08a | View and override model bookings, and monitor the shared-pool floor (§6.1.5) | Must |
| FR-ADM-11 | **Super admin only:** create, edit, retire and reparent segments, categories and sub-categories, and set `RequiresApproval` on any level | Must |
| FR-ADM-11a | **Super admin only:** maintain the global tag vocabulary and the sub-category to tag mapping (§5.4.1, §5.4.2) | Must |
| FR-ADM-12 | Entitlement queue: review client requests for gated levels, grant or decline with a recorded eligibility note | Must |
| FR-ADM-13 | Bulk grant a gated level to selected clients, for staged release of a newly tested category | Should |
| FR-ADM-09 | Platform metrics: signups, activations, conversion, runs, credit consumption, failure rate | Should |
| FR-ADM-10 | Every staff action is audit logged with actor, target, timestamp and reason, under the same scheme as customer actions (§11.1) | Must |

### 11.1 Audit logging

**Every state change, by every actor, is logged.** Not only staff actions. The most common question after something goes wrong is "who changed this, and what was it before" — and that question is asked about customer actions far more often than staff ones.

#### What is logged

| ID | Requirement | Priority |
|---|---|---|
| FR-AUD-01 | Every create, update, delete, archive and state transition is written to a single audit log, whoever performed it | Must |
| FR-AUD-02 | Three actor types are recorded: **member** (a client's user), **staff** (internal), **system** (a scheduled job or webhook handler) | Must |
| FR-AUD-03 | Each entry records: actor type, actor, client, action, entity type, entity id, timestamp, source address, and where relevant the reason | Must |
| FR-AUD-04 | The **before and after state** of the changed fields is recorded, so a value can be traced back and restored | Must |
| FR-AUD-05 | When a staff member acts through impersonation, both the impersonated user and the impersonating staff member are recorded (§15 D1) | Must |
| FR-AUD-06 | System actions record which job or handler ran, so an automated change is never anonymous | Must |

#### What must be covered

| Area | Examples |
|---|---|
| Account and access | Sign-in, sign-in failure, password change, role change, invitation, revocation, seat change |
| Master data | Create, rename, archive, restore — a rename propagates across every referencing product |
| Products | Create, edit, delete, archive, image replacement, bulk import |
| Shoots | Run started, cancelled, approved, changes requested, image regenerated, asset deleted |
| Credits | Every ledger movement is already immutable; the audit log additionally records who initiated it |
| Billing | Plan change, seat change, pause, resume, cancellation, payment method change |
| Entitlements and safety | Segment grant and revoke, segment–model pairing decision, moderation override |
| Taxonomy | Any change to segments, categories, sub-categories, base cuts |
| Settings | Approval toggle, watermark and disclosure decisions, notification preferences |

#### Integrity

| ID | Requirement | Priority |
|---|---|---|
| FR-AUD-07 | The log is **append only**. No application path issues an update or delete against it, and the database grants reflect that | Must |
| FR-AUD-08 | A failure to write an audit entry **fails the operation it describes**. An unlogged change is worse than a rejected one | Must |
| FR-AUD-09 | Entries are never edited to redact. If personal data must be removed, the entry is tombstoned with a record of who removed it and why | Must |
| FR-AUD-10 | The log is retained beyond the data it describes, so a deleted product's history survives | Must |

#### Access

| ID | Requirement | Priority |
|---|---|---|
| FR-AUD-11 | **Owners and Admins can read their own client's log**, filtered by actor, entity and date. It is not staff-only | Must |
| FR-AUD-12 | Producers and Viewers cannot read the log | Must |
| FR-AUD-13 | A client never sees entries belonging to another client, and never sees internal-only actions | Must |
| FR-AUD-14 | Entity detail pages surface recent history inline — a product page shows who last edited it and when | Should |
| FR-AUD-15 | Reading the audit log is itself logged, for staff readers | Should |

#### Retention buckets

Retention is **configuration, not code**. Named buckets each carry an age threshold, a backup retention period, and the list of entities they apply to.

**Anything not listed in a bucket is retained forever.** The default is to keep. A table only ages out when someone deliberately adds it to a bucket, so forgetting to configure something is safe rather than destructive.

| Bucket | Ages out after | Backup kept for | Applies to |
|---|---|---|---|
| `transient` | 90 days | 180 days | High-volume operational noise — see below |
| `financial` | 7 years | 7 years | Credits, refunds, plan and seat changes. Indian record-keeping expects this and it is not our choice |
| `safety` | Never | — | Segment grants, model pairings, moderation overrides. If asked eighteen months later how an image came to be generated, the authorising decision must still exist |
| *(unlisted)* | Never | — | **Everything else, by default** |

**What belongs in `transient`.** Only entries with no lasting value — high in volume, low in meaning, and unlikely to be asked about after three months.

| Included | Why |
|---|---|
| Sign-in attempts, successful and failed | Volume is high and the security question is answered within days, not months |
| Password reset requests and OTP verifications | Same |
| Token issue and consumption | Plumbing |
| Expired and consumed auth tokens | The row has no purpose once spent |
| Revoked and expired sessions | |
| Processed webhook payloads | The event id is retained; only the payload ages out |
| Read notifications | |
| Account lock and unlock events | |

**What must not be in `transient`, even though it is tempting.** Anything describing a change a customer might ask about later: product edits, image replacements, run activity, member and role changes, master data renames. A merchandiser asking in March why a February shoot used the wrong colour needs that trail. **When in doubt, leave it unlisted** — the default is to keep.

| ID | Requirement | Priority |
|---|---|---|
| FR-AUD-16 | Retention buckets are defined in configuration: name, age threshold, backup retention, and the entities included | Must |
| FR-AUD-17 | **An entity absent from every bucket is retained indefinitely.** Omission must never cause deletion | Must |
| FR-AUD-18 | Each audit entry carries a **category**, so entries in one table can fall into different buckets | Must |
| FR-AUD-19 | Financial and safety entries are exempt from transient ageing regardless of their table | Must |
| FR-AUD-19a | The `transient` bucket carries **operational noise only** — authentication attempts, token lifecycle, session lifecycle, processed payloads, read notifications. Nothing describing a change to a customer's data | Must |
| FR-AUD-19b | Adding an entity to a bucket is a **deliberate, reviewed change**. The reviewer confirms nobody will need the record after the threshold | Must |

#### The archive job

| ID | Requirement | Priority |
|---|---|---|
| FR-AUD-20 | An overnight job moves rows past their threshold into dated archive files, then deletes them from the live table | Must |
| FR-AUD-21 | **Archive, verify, then delete — in that order.** Rows are removed only after the archive is written and its integrity confirmed | Must |
| FR-AUD-22 | The job runs in batches with a bounded transaction size, so a large backlog cannot lock the table or exhaust the log | Must |
| FR-AUD-23 | The job is **idempotent and resumable**. An interrupted run resumes without duplicating or skipping rows | Must |
| FR-AUD-24 | **No row is archived while a live row references it.** Referential integrity is checked before deletion, not assumed | Must |
| FR-AUD-25 | Each run records rows examined, archived, deleted and skipped, and the archive location. A run that archives nothing is reported, since silence usually means the job stopped rather than that there was nothing to do | Must |
| FR-AUD-26 | Archives are written to durable storage separate from the primary database | Must |
| FR-AUD-27 | A **restore path exists and is tested**. An archive nobody can read back is not a backup | Must |
| FR-AUD-28 | Archives past their backup retention are deleted, and that deletion is itself logged | Must |
| FR-AUD-29 | The job is disabled by default in non-production environments | Should |

**Never eligible for any bucket**, regardless of configuration: `CreditLedger`, `Invoices`, `SubscriptionPeriods`, `Plates`, `Models`, `RunImages`, and any row still referenced by live data. These are the record, not the trail.

#### Volume

| ID | Requirement | Priority |
|---|---|---|
| FR-AUD-16 | Entries are retained for a defined period, longer for security and billing actions than for routine edits | Must |
| FR-AUD-30 | The log grows without bound and becomes one of the largest tables. Partitioning by month is planned from the outset rather than retrofitted, and aligns with the archive boundary | Must |
| FR-AUD-31 | Before and after state is stored for changed fields only, not whole records, so a wide table does not produce enormous entries | Should |

---

## 12. Module J — Support and help

| ID | Requirement | Priority |
|---|---|---|
| FR-SUP-01 | Help centre covering the shoot flow, garment image guidance and credit model | Must |
| FR-SUP-02 | Contact support with the current account and run context attached | Must |
| FR-SUP-03 | Guidance on preparing garment images shown inline at every upload point, with worked good and bad examples | Must |
| FR-SUP-03a | The standard is stated plainly: plain light background, single garment, flat lay fully spread or ghost mannequin, even lighting, no person in frame, no heavy shadow | Must |
| FR-SUP-04 | Contact support from a run or image, with full provenance attached — model, plate, pose, product and source image ID — as the sole route for quality complaints (§4.1.2) | Must |

---

## 13. Cross-cutting behaviour

| ID | Requirement | Priority |
|---|---|---|
| FR-X-01 | Every list has a defined empty state that explains and offers the next action | Must |
| FR-X-02 | Every destructive action is confirmed and states what is lost | Must |
| FR-X-09 | Every state change is audit logged regardless of actor (§11.1). A change that cannot be logged is not performed | Must |
| FR-X-03 | Errors state what happened, whether the user was charged, and what to do next | Must |
| FR-X-04 | Long operations show progress, never an indefinite spinner | Must |
| FR-X-05 | Full keyboard navigation and visible focus throughout; WCAG 2.1 AA | Must |
| FR-X-06 | All monetary and credit values are unambiguous about currency and unit | Must |
| FR-X-07 | Disclosure is handled per §7.2: provenance metadata always embedded, visible watermark customer-controlled, obligation resting with the customer as publisher | Must |
| FR-X-08 | Session timeout with warning and the opportunity to extend | Should |

---

## 13.1 Feature flags

Unfinished or unproven features are gated by **configuration**, not by a database table. Flags live in `appsettings.json` and environment variables, resolved per environment through the standard .NET configuration and feature-management pipeline.

| ID | Requirement | Priority |
|---|---|---|
| FR-FF-01 | Every feature not fully rolled out sits behind a named configuration flag, disabled by default in production until it is trusted | Must |
| FR-FF-02 | Flags are **global per environment**. There is no per-client or per-user flag resolution | Must |
| FR-FF-03 | Per-client variation is handled by `ClientEntitlements` (§5.3) or by plan entitlements — never by a flag | Must |
| FR-FF-04 | A flag never gates a paid capability or a permission. Roles decide who may act, plans decide what was bought, entitlements decide what was approved, flags decide only whether the code path exists yet | Must |
| FR-FF-05 | Disabled features are hidden entirely rather than shown disabled, so no customer is teased with something that does not exist | Must |
| FR-FF-06 | When a flag is unreadable or absent, the feature is treated as **off** | Must |
| FR-FF-07 | Each flag carries an owner and a retirement date in the configuration comments. A flag outliving its rollout is removed with the code path it guarded | Should |
| FR-FF-08 | Changing a flag requires a deploy. This is accepted: no runtime kill switch exists at launch | Must |

**Known flags at launch**

| Flag | Gates | Default |
|---|---|---|
| `Features:InAppNotifications` | In-app notification centre. Email notifications are unaffected | Off |
| `Features:Teams` | Invitations and member management (§3.6) | Off |
| `Features:SavedShootConfigurations` | Naming and reusing a configuration (FR-SHT-06) | Off |
| `Features:BrandCast` | Model booking (§6.1) | Off |
| `Features:CsvImport` | Bulk product import (FR-PRD-08) | Off |

**Why no table.** A flag table brings scope resolution, percentage rollout, caching and a stale-flag problem. None of that is needed while every flag is a global on-or-off per environment. Should a runtime kill switch become necessary — pausing generation because a provider is failing — that is a small settings table holding a handful of specific switches, not a flag framework. Recorded as F36.

---

## 14. Out of scope for Phase 1

Recorded so the design does not preclude them.

- Custom model building (FR-SHT-16)
- Batch shoots across multiple products (FR-SHT-15)
- Team invitations and the member management UI (the role model itself ships, per §2.4)
- Channel and PIM integrations, publishing
- Restricted garment categories — swimwear, lingerie, sheer (§6.2.3)
- Video output
- Public API
- Mobile applications
- White-label or reseller accounts

---

## 15. Decisions pending

Substantial decisions that need their own discussion before they can be specified. Each blocks a defined piece of scope. Distinct from §16, which holds smaller calls that can be made in the moment.

### D1 — Staff impersonation

**Status** Deferred. Requirements FR-ROL-20 and FR-ROL-21 are recorded but not in Phase 1 scope. The `ImpersonatedBy` and `ImpersonationReason` columns exist in the schema so enabling it later needs no migration.

**Settled so far**
- Capability sits with Support, Platform admin and Super admin in the role matrix
- An impersonating session cannot change billing, purchase credits or delete an account
- Reason recorded, visible in the customer's own session list, fully audit logged

**Open**

| # | Question | Why it matters |
|---|---|---|
| D1.1 | Should **Support** hold it at all, or only Platform admin and Super admin? | Support is deliberately kept away from anything financial. Three roles able to enter any customer account is a wide surface for a launch product |
| D1.2 | Is **customer consent required** before a session starts, or is notification after the fact sufficient? | Consent is safer and slower. Notification is faster and relies on the audit trail as the control |
| D1.3 | If consent is required, how is it obtained — in-app approval, a support ticket reply, or a signed clause in the terms? | Determines whether it works out of hours, which is when it is most needed |
| D1.4 | What is the **time-box**? A support session should be far shorter than a customer session | 30 minutes is a starting proposal, not a decision |
| D1.5 | Is impersonation **read-only**, or may staff act on the customer's behalf? | Read-only is far safer. Acting is what actually resolves some tickets |
| D1.6 | How does the customer know it is happening — banner, email, session list only? | Affects trust more than any other detail here |
| D1.7 | Does the **admin console cover most diagnosis without it**? It already shows runs, credits and provenance | If yes, impersonation may not be needed at launch at all |

**Recommendation to review.** Ship without it. Give Support read-only account views in the admin console, which covers most diagnosis. Add impersonation when support volume proves it necessary, by which point its requirements will be obvious rather than speculative.

### D2 — Staff access and separation of duties

**Status** Open. Three gaps in the internal role model, each blocking a piece of internal tooling.

| # | Question | Why it matters |
|---|---|---|
| D2.1 | Is the Studio operator / Library reviewer conflict enforced **when a role is granted**, or **when a plate is approved**? A related question: Super admin inherits every capability, so it can approve plates and reintroduce self-approval by the back door | Blocking at grant is simpler but halts plate production when one person is on leave. Blocking at approval — a person may generate or approve, never both on the same plate — is more code but workable with a team of three |
| D2.2 | How do staff **sign in**? No authentication method, session record or last-login field exists for `StaffUsers` | Most teams use Google or Microsoft SSO so that removing someone from the company removes their access everywhere at once. Nothing is currently specified, and staff cannot log in without it |
| D2.3 | `StaffRoles` records who **granted** a role but not who **revoked** one | For roles that control refunds and credit grants, only half the audit story is recorded. You can see who gave access, not who took it away |

**Recommendation to review.** Enforce separation at approval time rather than at grant, so a small team is not blocked by absence. Use SSO for staff. Add revocation columns to `StaffRoles`.

---

## 16. Open questions

| # | Question | Owner |
|---|---|---|
| F1 | Is 30 credits over 30 days the right trial? It is one full shoot of six poses across four formats, plus six regenerations |
| F2 | ~~Is rollover capped?~~ **Decided:** capped per plan (FR-ROLL-02). Open: what the cap should be — two months' allowance is the working proposal |
| F3 | Should a customer's **first run be free**? New customers make their worst choices in the first hour, and absorbing that may cost less than the support and churn it causes |
| F4 | Do team invitations ship at launch, or after? The role model ships either way per §2.4 |
| F5 | ~~Are products required?~~ **Decided:** yes. Every shoot is driven from a product. Trials are seeded with a sample product so the first run needs no setup |
| F6 | What is the image retention policy after cancellation, and after account deletion? |
| F7 | Which payment provider, and does it cover Indian GST invoicing natively? |
| F8 | ~~Does sub-category drive anything beyond display?~~ **Decided:** yes. Sub-category carries the base cut (§5.3.0), gender applicability and the tag mapping (§5.4.2) |
| F11 | ~~Free-form or master-data tags?~~ **Decided:** controlled global vocabulary, see F53 |
| F34 | Are five internal roles right, or would two or three serve better at launch? Roles nobody occupies are roles nobody maintains |
| F35 | If Studio operator and Library reviewer merge, FR-ROL-18 loses its mechanism entirely. Any reduction in roles must carry the separation-of-duties rule with it |
| F43 | ~~Should Segment narrow the model list?~~ **Decided:** segment is a safety boundary and filters models through an explicit pairing (§5.3.2). Open: should scenes also be segment-scoped, and is the pairing a hard filter or a default the client may widen? It must remain hard for sensitive segments |
| F44 | Which segments ship at launch, and which of them are marked sensitive? |
| F45 | Who decides segment–model pairings — Library reviewer as part of the plate QA gate, or Super admin? Proposal: reviewer for ordinary segments, Super admin for sensitive ones |
| F53 | ~~Controlled tags?~~ **Decided:** controlled, **Shootroom-owned** global vocabulary maintained by Super admin, with a kind and an optional prompt fragment (§5.4.1). Clients select only |
| F54 | ~~Columns or tags?~~ **Decided:** collapsed into global tags, mapped per sub-category. Fit alone stays a field. Open: the seed vocabulary must cover Indian garment terms — dupatta, ghera, nehru collar — not only Western descriptors |
| F55 | Does a front flat lay genuinely dress a three-quarter or side pose well, or do those also degrade? If they do, the pose set narrows further or a side image becomes a third role |
| F49 | Size set values are free text and do not join to the model attribute vocabulary, so "suggest models of matching size" cannot currently work. Should size sets draw from the controlled vocabulary, or is the suggestion dropped? |
| F51 | ~~Retention periods?~~ **Decided:** configurable buckets, default forever. The 90-day bucket takes operational noise only — sign-ins, password attempts, token and session lifecycle. Anything describing a change to customer data stays unlisted and is kept |
| F52 | Where do archives live, and who can read them back? A restore that needs an engineer is not a restore support can use |
| F50 | What seed lists ship for colours, fabrics and size sets? They must suit Indian apparel — silk, khadi, chanderi, georgette — not only cotton and linen |
| F47 | Which base cuts ship at launch? `top_standard`, `bottom_full` and `full` cover most of a fast-fashion range; cropped, long and knee cuts can follow demand |
| F48 | Does a base cut need its own QA gate, or does the existing plate checklist cover it? A cropped base exposes the midriff, which changes what "passes" |
| F46 | Reviewing every model against every new segment scales linearly with library size. At 104 models it is a session; at 1,000 it is a project each time a segment is added. Is sampled batch approval acceptable for non-sensitive segments, and what sample size? |
| F42 | Does the provider's invoice PDF satisfy Indian GST requirements — GSTIN, HSN or SAC codes, CGST/SGST/IGST split? If not, we must issue our own compliant tax invoice on top, with our own numbering sequence, and this table stops being a pure mirror |
| F40 | How many free credits at registration, and for how many days, before a plan is required? |
| F41 | What is the default maximum pause duration, and does it differ by plan? |
| F38 | What is the additional seat price, and how does it compare with the per-credit gap between plan and pack rates? |
| F39 | What is the viewer cap per plan? A multiple of paid seats, or a flat number per tier? |
| F36 | Do we need a runtime kill switch before launch — pausing generation without a deploy — or is a deploy fast enough? |
| F37 | Should credit warnings and trial expiry be opt-out at all? Muting them means a user discovers an empty balance mid-catalogue |
| F33 | Are the OTP rate limits (5/hour, 10/day) right for a business tool, or too tight for a shared team inbox? |
| F32 | Does sales-led client creation (FR-ACC-38) ship at all, or is self-registration the only route? It matters for enterprise deals where the buyer is not the user |
| F31 | Should replacing an image warn that existing shoots will become stale, or is the label after the fact enough? |
| F12 | Can a product carry multiple colourways as one record, or is each colourway a separate product? Affects SKU uniqueness and shoot counts |
| F9 | Is the demo shoot a real generation, or pre-rendered? Real costs money on every signup |
| F25 | Should preview be free rather than 1 credit? Free removes all friction from getting the combination right, at the cost of one image per attempt |
| F26 | Without a flag button, how do we detect a systematically failing model or garment type before support volume reveals it? |
| F27 | Which provenance standard — C2PA, IPTC, or both? C2PA is where platforms are heading; IPTC is simpler and more widely read today |
| F30 | Do rolled-over credits expire at the end of an annual term, or carry into a renewal? |
| F28 | Should the watermark decision be enforced per market, based on where the customer sells, or left entirely to them? Enforcing means interpreting law on their behalf |
| F29 | How is FR-DIS-21 measured? "Must not flatter the garment" needs a testable definition before it can be held to |
| F10 | Do we need a hard cap on concurrent runs per account to protect throughput? |
| F13 | Do we ship all four customer roles at launch, or Owner and Producer only, adding Admin and Viewer with team management? |
| F14 | Is the credit cap per member per month, or per run? Per month is simpler; per run catches a single runaway batch |
| F15 | ~~Should Viewers be billable seats?~~ **Decided:** Viewers are free and capped per plan (FR-SEAT-02, FR-SEAT-04). Open: what the cap should be |
| F16 | Does the watermarked preview carry a visible mark, an invisible one, or both? Visible is honest; invisible traces a leak |
| F17 | Should approval be enforced per plan tier, or available to every account that wants it? |
| F18 | Is there an auto-approve timeout — approve after N days if nobody reviews — or do runs wait indefinitely? |
| F19 | How many bookable models per tier, and is booking a plan feature or a paid add-on? Add-on scales with perceived value; plan feature is simpler to sell |
| F20 | Is 90 days the right cooling period? Longer protects the ex-customer, shorter recovers the asset faster |
| F21 | Can a booked model be swapped mid-subscription, or is a booking a commitment to that face? |
| F23 | Does activewear stay Standard, or do sports bras and bodysuits split out into Restricted? The line is not obvious |
| F24 | Is there a market for Restricted at all, or is the safer product one that simply never supports it? |
| F22 | Should face reseeding — same fit archetype and anchor profile, new generated identity — be prototyped as a cheaper alternative to booking? If it works it delivers brand distinctiveness at near-zero library cost |
