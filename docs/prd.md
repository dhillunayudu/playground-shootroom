# Shootroom — Product Requirements

**Version** 1.0 · Draft for review
**Scope** Browse-first model library and AI try-on content pipeline
**Status** Design locked, engineering not started

---

## 1. Summary

Shootroom replaces the traditional fashion photoshoot for our catalogue and marketing channels. A user picks a garment category, selects a pre-built AI model from a curated library, chooses poses and styling, attaches the garment image, and receives a set of channel-ready images.

The flow is a **shoot configuration** first and a garment run second. Steps 01 to 03 describe the plate — category, model, poses, styling, scene — and none of them need the garment image. The garment attaches at step 04, immediately before generation. This is what makes Phase 2 batch work: one saved configuration, many garments.

The product is built around one core constraint: **the model is never generated at request time.** Models are pre-built, hand-reviewed and stored as reusable plates. Only the garment and the scene change per run. This is what makes output consistent across a product line, cheap to produce, and predictable in quality.

---

## 2. Problem

Producing product imagery today requires booking models, studios, photographers and stylists. Each shoot costs money and weeks of lead time, covers one product line, and produces a narrow demographic range. Reshoots for new colourways or sizes are disproportionately expensive.

The result is that most SKUs ship with flat-lay or ghost-mannequin imagery, which converts worse than on-body imagery, and that our catalogue shows a far narrower range of body types and ethnicities than our actual customer base.

---

## 3. Goals

| # | Goal | Measure |
|---|---|---|
| G1 | Produce on-body imagery for any SKU without a photoshoot | Cost per SKU image set vs. photoshoot baseline |
| G2 | Keep the model consistent across a product line | Same model ID reused across ≥80% of SKUs in a line |
| G3 | Cover a demographic range wider than physical casting allows | Library spans defined coverage matrix (§7.2) |
| G4 | Make a full image set producible by a non-technical merchandiser | Time from garment upload to download, unassisted |
| G5 | Batch across a catalogue, not one product at a time | SKUs processed per run (Phase 2) |

### Non-goals for V1

- Custom model building by end users (deferred to Phase 3, §14)
- Video output
- Automatic publishing to channels
- Garment design or pattern generation
- Face swapping onto real people, or any use of a real person's likeness

---

## 4. Users

**Merchandiser (primary).** Owns a product line. Wants on-body images for every SKU, fast, on-brand, without briefing anyone. Not technical. Will not read documentation.

**Marketing / social (secondary).** Wants the same garment across several poses, scenes and aspect ratios for campaigns. Cares about variety and format coverage more than catalogue consistency.

**Shootroom admin (internal).** Owns the model library. Builds, reviews, approves and retires plates. Needs tooling not exposed to the other two.

---

## 5. Domain model

These terms are used precisely throughout this document.

**Plate.** A stored, approved, full-length image of an AI model in a neutral base outfit, shot for try-on input. The canonical asset. Never regenerated at request time.

**Plate type.** Determined by garment category, never chosen directly:

| Type | Garment categories | Base outfit worn | Survives into final image |
|---|---|---|---|
| `PLATE.T` | Topwear — t-shirts, shirts, kurtas, blouses, blazers, outerwear | Varies by **base cut** (§7.3.1) — a t-shirt and a crop top need bases ending in different places | Bottoms, footwear |
| `PLATE.B` | Bottomwear — trousers, jeans, skirts, shorts | Fitted tucked top + a bottom matching the **base cut** (§7.3.1) | Top, footwear |
| `PLATE.F` | Full look — dresses, co-ords, sarees, complete outfits | Fitted tank + short, **or** a skin-fitted plain grey bodysuit — see §7.5.1 | Footwear only |

**Model.** A casting identity. One model has one canonical plate per plate type, plus a set of pose plates. Identified by a stable ID (`mp_014`).

**Variant.** A region-limited inpaint applied to a canonical plate — a different bottom, a different top, eyewear. Cached, never regenerated for a repeat combination. Cache key: `model_id + plate_type + variant_id + pose_id`.

**Pose.** A stored camera and body position. Frontal poses are try-on safe; all others are produced in the scene pass after the garment has been mapped.

**Shoot configuration.** Garment category, model, poses, base variant and scene. Fully specified without any garment image. Saveable and reusable.

**Run.** One garment executed against one shoot configuration, across N poses and M output formats, producing N×M images.

---

## 6. Functional requirements

### 6.1 Step 01 — Garment category

The user selects a category from a fixed, pre-defined set. **No garment image is uploaded at this step.** Everything from here to step 03 configures the plate, and none of it depends on the garment.

| ID | Requirement | Priority |
|---|---|---|
| F1.1 | User selects one of three garment types: Topwear, Bottomwear, Full look | Must |
| F1.2 | Selection derives the plate type; user never selects plate type directly | Must |
| F1.3 | Each option states what the try-on replaces and what is retained, before selection | Must |
| F1.4 | Optional garment metadata: fit, sleeve, hem, colourway. Refines the plate choice, not the try-on | Should |
| F1.5 | Step 01 is skipped entirely when the flow is entered from a product with a known category (§6.5) | Must — Phase 2 |
| F1.6 | Category is editable later without losing model, pose or scene selections, provided the plate type does not change | Should |
| F1.7 | Changing category to one with a different plate type resets the model selection and warns before doing so | Must |
| F1.8 | No step beyond 01 is reachable until a category is selected | Must |

### 6.2 Step 02 — Model

| ID | Requirement | Priority |
|---|---|---|
| F2.1 | Display all library models compatible with the chosen plate type | Must |
| F2.2 | **Filter set scales with library size.** At launch scale the rail exposes gender, garment size, body shape, heritage and skin tone only. Additional attributes unlock as the library grows past thresholds set per attribute | Must |
| F2.2a | The full §7.2 schema is stored and queryable from day one, whether or not it is exposed in the rail | Must |
| F2.2b | A filter that would return fewer than three results across the whole library is not exposed | Should |
| F2.3 | Filters are multi-select within a group, AND across groups | Must |
| F2.4 | Colour attributes (skin, hair, eye) render as swatches, not text lists | Must |
| F2.5 | Live result count; active filter count per group and overall | Must |
| F2.6 | Clear-all filters in one action | Must |
| F2.7 | Model card shows: name, ID, height, garment size, body shape, build, age band | Must |
| F2.8 | Empty result state offers a casting request, capturing the exact filter combination that returned nothing. Requests queue for generation (§7.1 tier 3) | Must |
| F2.8a | When strict matching returns nothing, offer nearest matches with the relaxed filters named — "3 models match if you drop *eye colour*" | Must |
| F2.8b | Filters are ranked by fit relevance. Relaxation always drops cosmetic attributes before fit attributes | Must |
| F2.9 | Sort: recommended, recently added, most used, name | Should |
| F2.10 | Favourite models and a saved cast per brand or line | Should — see §15 |
| F2.11 | Model detail view showing all stored attributes and available poses | Should |
| F2.12 | Exactly one model per run | Must |
| F2.13 | **A model appears only if it holds an approved plate of the type this shoot requires.** A model with no approved top plate is not shown for a Topwear shoot, so a shoot can never fail at generation for a reason that was knowable at selection | Must |
| F2.14 | The result count reflects the plate-type filter, so "12 models" means twelve that can actually shoot this garment | Must |

### 6.3 Step 03 — Poses and styling

| ID | Requirement | Priority |
|---|---|---|
| F3.1 | Multi-select from the pose library; each selected pose produces one image per format | Must |
| F3.2 | Selection order is preserved and displayed; it is the render order | Should |
| F3.3 | Each pose is labelled try-on safe or scene pass | Must |
| F3.4 | Warn when no try-on-safe pose is selected | Must |
| F3.5 | Base garment selection appears conditionally: bottoms for `PLATE.T`, tops for `PLATE.B`, none for `PLATE.F` | Must |
| F3.6 | Footwear is bundled with each base option, not selected separately | Must |
| F3.7 | Scene selection, single-select, applied as a separate pass after try-on | Must |
| F3.8 | At least one pose required to advance | Must |

### 6.4 Step 04 — Review and generate

| ID | Requirement | Priority |
|---|---|---|
| F4.1 | User attaches the garment image here, immediately before generation | Must |
| F4.2 | Upload validation: min 1000px shortest edge, plain background, single garment in frame, category consistent with step 01 | Must |
| F4.3 | Multiple garment images may be attached to one configuration; each produces its own run | Should — Phase 2 |
| F4.4 | Full run summary: garment, model, poses, base, scene | Must |
| F4.5 | Output format multi-select: 9:16, 4:5, 3:4, 1:1 | Must |
| F4.6 | Live image count = poses × formats, shown before generation | Must |
| F4.7 | Pipeline stages shown in order with what each does | Should |
| F4.8 | Generation runs asynchronously with per-image progress | Must |
| F4.9 | Per-image QA actions: approve, reject, regenerate single image | Must |
| F4.10 | Download individually, as a set, or push to storage | Must |
| F4.11 | Configuration is saved independently of the garment and re-runnable against a different garment | Must |

### 6.5 Entry points

| ID | Requirement | Priority |
|---|---|---|
| F5.1 | **Direct entry.** User starts at step 01 and picks a category manually | Must — Phase 1 |
| F5.2 | **Product entry.** User starts a shoot from a product detail page. Category is pre-seeded from the product record and step 01 is skipped | Must — Phase 2 |
| F5.3 | Product entry also pre-attaches the product image, so step 04 requires no upload | Must — Phase 2 |
| F5.4 | Pre-seeded category is visible and overridable, with the F1.7 warning if the plate type would change | Must — Phase 2 |
| F5.5 | Runs initiated from a product are linked back to it and visible in that product's history | Should — Phase 2 |

---

## 7. Model library

### 7.1 Library composition

Every model is a **pre-built master record**: a fixed set of attribute tags plus stored image references. Nothing about a model is computed at request time.

**The attribute space cannot be pre-generated.** Fifty-two attributes cross to 4.4 × 10³⁹ combinations. Even the nineteen fit-relevant attributes alone reach 7.3 × 10¹². No budget or timeline reaches any part of that.

The library is therefore a **small, deliberately chosen base set**, grown by demand, with user-built models arriving in a later phase.

#### Tier 1 — the base set (Phase 1)

Built by **gender × ethnicity cell**, four variants per cell. Thirteen ethnicities × two gender presentations × four variants = **104 base models.**

Within a cell, attributes split two ways:

**Anchor attributes** are shared by all four variants — eye colour, hair colour, hair texture, face shape, nose. These are where a heritage group genuinely clusters.

**Range attributes** vary across the four — skin tone steps through four values of that group's range, height varies ±5cm around a group median, age rotates through the bands. Skin tone and facial structure vary more within an ethnicity than between ethnicities, so fixing a single "major" value per group would produce a stereotype generator rather than a casting.

**The four variants vary on fit, not colouring.** If all four sat at the modal body type the library would be entirely S–M, and size is the one thing imagery cannot fake.

| Slot | Build | Size (F) | Size (M) | Height |
|---|---|---|---|---|
| V1 | Slender | S | S | Group median −5cm |
| V2 | Average | M | M | Group median |
| V3 | Curvy (F) / Athletic (M) | L | L | Group median +6cm |
| V4 | Plus size | XL–2XL | XL | Group median +1cm |

**Atypical features.** One variant per cell carries a feature that breaks the pattern — freckles, early silver hair, heterochromia, vitiligo, a gap tooth, alopecia. Twenty-six of the 104. Without them a library of this size reads uniform in a way that looks synthetic.

Full roster in **Appendix A**.

| | Count |
|---|---:|
| Base models | 104 |
| Canonical plates (× 3 plate types) | 312 |
| Pose plates (× 4 poses) | 1,248 |
| Storage @600KB | ~750 MB |

**Build order.** The top six ethnicities by actual customer base ship first — 48 models, 576 plates, a few weeks of production. The remaining seven are pulled by tier-2 demand rather than built speculatively.

#### Tier 2 — demand-driven growth (Phase 2.5)

Filter combinations that return nothing are captured as casting requests (F2.8) and queued for production. Generated models enter the shared library permanently, so the library converges on the combinations customers actually ask for.

#### Tier 3 — user-built models (Phase 3)

Users specify attributes directly. The system snaps to the nearest base model and applies only the differences as region-limited inpaints, so identity and QA are inherited rather than re-earned. Full generation runs only when nothing close exists, and every result passes the §7.6 gate before entering the shared library.

### 7.2 Attribute schema

Attributes are stored as **tags against a controlled vocabulary**, not free text. One namespaced key per attribute, one value per model, drawn from a fixed enum. The same vocabulary powers the filter rail, the generation prompt template and the coverage dashboard, so it has exactly one definition.

| Namespace | Keys |
|---|---|
| `identity` | gender, heritage, age_band, archetype |
| `body` | height_cm, height_band, body_shape, build, garment_size, frame, torso_ratio |
| `upper` | shoulders, collarbones, arms, chest, back, neck |
| `mid` | waist, stomach, hips, glutes |
| `lower` | thighs, calves, ankles, feet_size |
| `skin` | tone, undertone, finish, character, aging |
| `hair` | length, texture, density, colour, style, hairline, facial_hair |
| `face` | shape, jaw, cheekbones, forehead, nose, chin, ears |
| `features` | eye_shape, eye_colour, lashes, brows, lips, expression |
| `marks` | tattoos, piercings, assistive_device |

**Rules**

| ID | Requirement | Priority |
|---|---|---|
| T1 | Every key has a fixed enum; new values require a vocabulary change, not a free-text entry | Must |
| T2 | Every model carries a value for every fit-relevant key. Cosmetic keys may be null where the attribute does not apply | Must |
| T3 | Vocabulary is versioned. Adding a value never invalidates existing models | Must |
| T4 | Tags are indexed for filtering; a twelve-filter query resolves client-side over a loaded library | Must |
| T5 | The same tag set generates the model's prompt, so a stored model can be re-generated identically | Must |
| T6 | Attribute vocabulary is reviewed for respectful language, particularly heritage and body descriptors (§13 C6) | Must |

### 7.3 Coverage matrix

| Dimension | Minimum coverage at launch |
|---|---|
| Garment size | XS through 3XL, no gaps |
| Body shape | Three or four values at Phase 1; all five once the library passes 100 models |
| Heritage | 12 groups across the 26 base models, weighted toward our actual customer base |
| Age band | 18–24 through 65+, each with at least 2 models |
| Gender presentation | Feminine, masculine, androgynous |
| Skin tone | Full range of the stored tone scale, no clustering |
| Hair texture | Straight through coily 4C, including protective styles, headwrap and hijab |
| Inclusive casting | At least 2 models at Phase 1; broadened through tier-2 growth |

### 7.3.1 Base cut — the base garment must expose what the real garment exposes

**Established by testing, not theory.** A crop top mapped onto a plate wearing a full-length tank leaves the tank visible below the crop. A knee-length skirt onto full-length trousers leaves trouser legs showing through. **The base garment must end where the real garment ends, or the plate shows through.**

Plate type alone is therefore insufficient. `PLATE.T` is not one thing — a t-shirt and a crop top both replace the upper body, but they need bases that finish in different places.

#### The base cuts

What matters is where the base garment ends, not what the garment is called. Many sub-categories share a cut.

| Base cut | Base garment ends | Serves |
|---|---|---|
| `top_standard` | Tank to the waist | T-shirts, shirts, blouses, blazers, polos, jackets |
| `top_cropped` | Tank to the underbust, midriff bare | Crop tops, bralettes, cropped knits |
| `top_long` | Tunic to mid-thigh | Kurtas, longline shirts, tunics, long jackets |
| `bottom_full` | Trousers to the ankle | Jeans, trousers, palazzos, joggers |
| `bottom_knee` | Ends at the knee | Knee-length skirts, culottes, capris |
| `bottom_short` | Shorts to mid-thigh | Shorts, mini skirts |
| `full` | Bodysuit, or tank and short | Dresses, co-ords, sarees, jumpsuits |

Every sub-category maps to exactly one base cut. Every plate is generated for one base cut. A shoot loads plates matching the sub-category's cut, not merely its plate type.

#### Gender applicability

Some cuts apply to one gender presentation only. Crop tops are feminine; a masculine model needs no `top_cropped` plate. Recording applicability on the sub-category trims the library and prevents a nonsensical plate being generated.

#### Effect on library size

| | Before | After |
|---|---|---|
| Base cuts per model | 3 plate types | 7 base cuts |
| Plates per model | 12 (3 × 4 poses) | up to 28 (7 × 4 poses) |
| Library at 104 models | 1,248 plates | up to 2,912 plates |
| Storage @600KB | ~750 MB | ~1.7 GB |

The upper bound is not reached in practice: gender applicability removes cropped cuts from masculine models, and not every model needs every cut at launch. **Build the cuts your catalogue actually sells first** — `top_standard`, `bottom_full` and `full` cover most of a fast-fashion range — and add the rest as demand appears.

### 7.4 Pose set per model

Every model ships with, at minimum:

- Frontal, symmetrical, arms clear of torso — **required, the try-on input**
- Three-quarter left and right
- Back view

Additional poses are produced in the scene pass and do not require separate try-on runs.

### 7.5 Base outfit specification

Non-negotiable for every plate, because it determines segmentation quality:

- Fitted sleeveless scoop-neck tank, neckline at the collarbone
- Slim straight-leg trousers, same colour
- Mid-tone neutral (stone or greige). **Not white** — bleeds into pale garments. **Not black** — leaves halos on dark garments. **Never saturated** — colour tint is the most common try-on artefact
- Matte woven or fine jersey. No pattern, logo, ribbing, pockets, buttons, zips or visible topstitching
- Bare feet or plain neutral flats; real footwear is added in the variant pass
- Standing straight to camera, weight even, arms relaxed with a visible gap from the torso, hands open and separated from the thighs
- Hair fully clear of the chest
- Plain seamless light grey backdrop, soft even frontal lighting, no cast shadow
- Full length, both feet and floor in frame, generous headroom, 9:16

#### 7.5.1 Full-look base outfit — two candidates, undecided

Both remain open until tested. The choice affects segmentation quality and the likelihood of a provider content refusal.

| | **A · Tank and short** | **B · Grey bodysuit** |
|---|---|---|
| Description | Fitted sleeveless tank, fitted mid-thigh shorts, stone neutral | Skin-fitted plain grey bodysuit, full torso to mid-thigh, matte, seamless |
| Silhouette edge | Two garments, so a waistband edge the mask must resolve | One unbroken silhouette, no waistband |
| Content-filter risk | **Higher.** Reads as underwear to a classifier — this is PRD Q4 | **Lower.** Reads as a garment |
| Skin visible | Midriff and upper thigh | Minimal |
| Risk | Provider refusal blocks the whole Full look category | A deep neckline or open back must replace bodysuit fabric rather than skin; try-on can leave the original showing at the edges |
| Colour | Mid-tone stone or greige | Mid grey, same reasoning — never white, never black, never saturated |

**Current leaning: B.** It resolves the content-filter risk at source and gives the mask a cleaner edge. Both are unproven; the tests in §7.6 item 7 decide it.

**Test to settle it.** Generate one model on each base, then run the same five reference garments through both — a fitted dress, a loose kaftan, a saree, a deep-neckline dress, and an open-back dress. Score for edge bleed, ghosting of the base garment, and skin appearing where fabric should be. Record which base survived the provider's filters at all.

### 7.6 Plate QA gate

No plate enters the library without passing:

1. Visible gap between each arm and the torso
2. Hands not overlapping the hips or thighs; fingers countable and correct
3. Hair entirely clear of the chest
4. Both feet fully in frame with visible floor beneath
5. No cropping at the bust or head
6. Skin texture natural, not plastic or over-smoothed
7. Test try-on run against five reference garments — white top, black top, bright print, sheer fabric, unusual hemline — scored for edge bleed, ghosting and colour tint

### 7.7 Storage and references

A model record holds no image data, only references. Images live in object storage behind a CDN.

```
/models/{model_id}/
    canonical/{plate_type}/{pose_id}.webp
    variants/{plate_type}/{pose_id}/{variant_id}.webp
    thumb/card.webp
    thumb/detail.webp
```

| ID | Requirement | Priority |
|---|---|---|
| S1 | Every plate and variant is addressed by a deterministic path derived from its IDs | Must |
| S2 | Model records store the path prefix, not per-image URLs | Must |
| S3 | Browse grids load `thumb/card.webp` only — never full plates | Must |
| S4 | WebP primary, JPEG fallback. Card thumbs ≤ 60KB, plates ~1400×2000 | Must |
| S5 | Retiring a model hides it from browse but never deletes images referenced by historical runs | Must |
| S6 | Storage paths are stable for the life of the model; regeneration writes a new version rather than overwriting | Must |

### 7.8 Library production process

**This process is operated by people, not by an autonomous agent.** No system generates, selects or approves a plate without a human in the loop. The Plate Console (§12 A1) writes prompts; an operator runs them, judges the output, and decides what enters the library. That judgement is the product's quality floor and it is not delegated.

| Step | Owner | Action |
|---|---|---|
| 1 | Studio admin | Open the Plate Console, select a roster entry |
| 2 | Studio admin | Review the pre-filled attributes; override any that read wrong for the casting |
| 2a | Studio admin | **Generate and approve the hero portrait** — the model's reference image (§7.9.2). Record its seed, provider and model version |
| 3 | Studio admin | Copy the positive and negative prompts for the required plate type and pose |
| 4 | Studio admin | Run in the image generator **with the reference image attached**. Regenerate until the output passes visual judgement and reads as the same person |
| 5 | Studio admin | Score against the §7.6 QA checklist. Any failure sends it back to step 4 |
| 6 | Studio admin | Run the five-garment try-on test (§7.6 item 7) on the frontal plate |
| 7 | Studio admin | Upload to the §7.7 storage path; the model record moves to `approved` |
| 8 | Second reviewer | Sample audit — minimum 20% of plates, and 100% of any cell where one plate failed |

**Automation boundary.** The console may be extended to call the generation API directly, submitting the prompt it already writes and returning candidates. Steps 5 to 8 stay manual regardless. Automating the call is a convenience; automating the judgement is not on the roadmap.

### 7.9 Model identity and reproducibility

A library model is only useful if it stays **the same person** across every plate built for it — every pose, plate type and base cut — and if that person can be **regenerated later** when a new pose or base cut is added. This section records how identity is held, what is stored to make it reproducible, and what was verified about the generation providers.

#### 7.9.1 What a "model" is in the data

| Term | Meaning | Where it lives |
|---|---|---|
| **Model** | One specific synthetic person — bm_014. The four variants in a gender × ethnicity cell are **four models**, each its own record | `Models`, one row each (104 at launch) |
| **Attributes** | Eye colour, build, hair and so on — one value per attribute, each pointing at a value in `AttributeVocabulary` | `ModelAttributes`, one row per attribute |
| **Plate** | One generated image of a model: plate type × pose × base cut | `Plates` |
| **Plate variant render** | A plate with a base garment inpainted (the jeans under a top shoot) | `PlateVariantRenders` |

A prompt is **assembled** from the model's attributes plus the pose, plate type and base cut, and **stored on the image it produced**. It is never stored on `ModelAttributes` (one attribute per row cannot hold a whole prompt) and never on `Models` (the prompt differs per pose).

#### 7.9.2 How identity is held: reference image first, seed second

**The identity anchor is a reference image, not a seed.**

1. For each model, the operator first generates and approves one **hero portrait**. This is the model's reference image.
2. Every plate for that model is then generated **from the reference image** — using the provider's image-reference, character-consistency or image-edit capability — so the face carries across poses.
3. The seed of the hero portrait is recorded where the provider supports one, as a secondary aid to regeneration.

**What a seed is, simply.** An image generator starts every picture from random noise; the seed is the number that picks which noise. Same prompt + same seed + same provider + same model version ⇒ the same image again. Different seed ⇒ a different face, even with an identical prompt. Think of it as the model's DNA number — but only within one provider and one model version.

**Why the seed alone is not enough.**

| Limit | Consequence |
|---|---|
| A seed is meaningful only for **one provider and one model version** | Seed 48213907 on Flux and on another generator are unrelated faces. A provider upgrading its model can change the output for the same seed. The seed is useless without the provider and version recorded beside it |
| A seed fixes the starting noise, **not the identity** | Same seed with "front pose" and with "three-quarter pose" gives a similar person, not the same one |
| Different seeds do **not guarantee different faces** | Two seeds can produce lookalikes. Distinctness across the roster is a QA check (§7.6), not a property of the seed |
| Not every provider accepts a seed | See §7.9.3. The design must work without one |

#### 7.9.3 Provider support — verified 11 October 2026

Checked against each provider's own documentation. **Re-verify before choosing a provider**; these APIs change.

| Provider / model | Accepts a seed? | Reference images for consistency? | Notes |
|---|---|---|---|
| **Flux (via fal.ai)** | **Yes** — `seed` integer | Via image-to-image and adapter models | fal's schema: *"The same seed and the same prompt given to the same version of the model will output the same image every time."* Determinism is tied to the model version |
| **Google Imagen (Vertex AI)** | **Yes**, `seed` 1 – 2,147,483,647 | — | Deterministic **only with `addWatermark: false`** (required on model version 006+ when a seed is used). Google states many Imagen endpoints are being discontinued and recommends migrating to Gemini image models before 30 June 2026 |
| **Google Gemini image models ("Nano Banana")** | **Not documented** | **Yes** — up to 14 reference images; 4–5 of them specifically for character consistency, depending on model | The direction of travel: consistency through references, not seeds |
| **OpenAI image models** | **Unconfirmed** — believed not supported | Image edit with input images | The parameter list could not be verified at the time of writing. Treat as no seed until confirmed |

Sources: [fal.ai — FLUX.1 [dev] API](https://fal.ai/models/fal-ai/flux/dev/api) · [Google Cloud — Generate deterministic images](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/image/generate-deterministic-images) · [Google AI — Gemini image generation](https://ai.google.dev/gemini-api/docs/image-generation) · [Vercel AI SDK — Image generation](https://ai-sdk.dev/docs/ai-sdk-core/image-generation)

**Implication.** The newer generators are converging on reference images for consistency and some drop the seed entirely. The library therefore treats the reference image as mandatory and the seed as optional.

#### 7.9.4 What is recorded

| Where | Field | Purpose |
|---|---|---|
| `Models` | `ReferenceImageUri` | The approved hero portrait — the identity anchor every plate is built from |
| `Models` | `GenerationSeed` *(nullable)* | Seed of the hero portrait, when the provider supports one |
| `Models` | `GeneratorProvider`, `GeneratorModelVersion` | Without these the seed cannot be reused |
| `Models` | `StoragePrefix` | The one folder holding every image of the model (`/models/bm_014/`). Plates store only their path inside it, so a model can be moved, copied or removed as a unit (S2) |
| `Models` | `VocabularyVersion` | Which version of the attribute vocabulary the model was tagged against. When the vocabulary grows (eyewear and hairstyle were added after the first roster), this identifies models needing re-tagging |
| `Models` | `UsageCount`, `LastUsedAt` | How often the model is shot — library planning and over-exposure. **Counts runs, not images.** Recomputed from `Runs` by a scheduled job, never incremented inside a shoot (see ID6) |
| `Plates` | `Prompt`, `NegativePrompt` | The exact text that produced this image |
| `Plates` | `Seed`, `GeneratorProvider`, `GeneratorModelVersion` | What actually ran — normally the model's, but a single pose may be retried with an override |
| `Plates` | `ReferenceImageUri` | The reference the plate was generated from |
| `PlateVariants` | `InpaintPrompt` | Shared garment prompt — "dark denim baggy jeans" — for every model that wears it |
| `PlateVariantRenders` | Final prompt sent | The assembled inpaint prompt for that plate + garment combination |

**Vocabulary history.** The vocabulary itself is versioned value by value (`AttributeVocabulary.AddedInVersion`, `DeprecatedAt`), so its state at any version can be reconstructed. A model's own re-tagging is not kept in a separate table: re-tagging is a change to a model and is written to the audit log with before and after values (FRD FR-AUD-04).

| ID | Requirement | Priority |
|---|---|---|
| ID1 | Every model has an approved **reference image** before any plate is generated for it | Must |
| ID2 | Every plate is generated from the model's reference image, using the provider's reference or image-edit capability | Must |
| ID3 | Every generated image records its prompt, negative prompt, provider, provider model version and seed (if any) | Must |
| ID4 | A seed is never stored without the provider and model version it belongs to | Must |
| ID5 | Changing provider or provider model version for an existing model is a deliberate act: new plates are QA'd against the reference image for identity drift before release | Must |
| ID6 | `UsageCount` and `LastUsedAt` are recomputed from `Runs` by a scheduled job. Models are shared across all clients, so incrementing a model row inside every shoot would make popular models a write hotspot | Must |
| ID7 | Re-tagging a model to a new vocabulary version writes an audit entry with before and after attributes | Must |
| ID8 | QA includes a **near-duplicate check** across the roster: no two models may read as the same person | Should |

**Open — which generation provider?** The choice decides whether seeds are available at all and how reference images are passed. It should be made against §7.9.3, re-verified on the day, with a five-model pilot measuring identity hold across all poses (FRD F58).

---

## 8. Generation pipeline

Four stages, in order. Stages 1 and 2 are usually cache hits.

| Stage | Input | Output | Cached |
|---|---|---|---|
| 01 Plate | `model_id`, `plate_type`, `pose_id` | Canonical plate image | Always — never generated at request time |
| 02 Variant | Plate + `variant_id` | Plate with base garment and footwear replaced | Yes, on `model_id + plate_type + variant_id + pose_id` |
| 03 Try-on | Variant plate + garment image | Garment mapped onto the plate | No |
| 04 Scene | Try-on output + `scene_id` + format | Relit, placed, cropped to format | No |

**Requirements**

| ID | Requirement | Priority |
|---|---|---|
| P1 | Try-on runs only on a try-on-safe pose; other poses derive from stage 04 | Must |
| P2 | Variant inpaint region starts at mid-hip when the garment hem will cover the waistband | Should |
| P3 | Mask edges feathered; no hard transition line | Must |
| P4 | Stage 02 cache is warmed for popular combinations rather than generated on demand | Should |
| P5 | Failed stages retry twice, then surface a clear error naming the stage | Must |
| P6 | Every output image stores full provenance: model, plate, variant, pose, product, **source image ID**, scene, stage versions | Must |

---

## 9. Data model

```
Model                          (master record — one row per synthetic person)
  id, code, gender, status (draft|approved|retired)
  storage_prefix               -- /models/{code}/
  vocabulary_version
  reference_image_uri          -- identity anchor (§7.9)
  generation_seed?, generator_provider, generator_model_version
  usage_count, last_used_at    -- recomputed from runs by a job
  availability + booking mirror

ModelAttribute                 (one row per attribute — the filter index)
  model_id, namespace, attr_key, attribute_vocabulary_id
  PRIMARY KEY (model_id, namespace, attr_key)
  FK (attribute_vocabulary_id, namespace, attr_key) → AttributeVocabulary
  INDEX (attribute_vocabulary_id, model_id)   -- drives every filter query

AttributeVocabulary            (controlled vocabulary, one row per value)
  namespace, attr_key, attr_value, label, sort_order
  fit_relevant (bool)          -- drives filter relaxation order (F2.8b)
  is_filterable
  added_in_version, deprecated_at

CastingRequest                 (tier-3 demand signal)
  id, user_id, filter_json, created_at
  status (open|queued|generated|declined), fulfilled_model_id

Plate
  id, model_id, plate_type, pose_id, image_uri
  qa_status, qa_notes, approved_by, approved_at

Variant
  id, label, kind (bottom|top|eyewear), swatch_hex
  bundled_footwear, inpaint_prompt, negative_prompt

VariantRender          (the stage-02 cache)
  cache_key, plate_id, variant_id, image_uri, created_at

Pose
  id, label, try_on_safe, description, camera_notes

Scene
  id, label, relight_prompt, negative_prompt

ProductImage                   (primary images are versioned, never overwritten)
  id, product_id, uri, is_active
  uploaded_by, uploaded_at, replaced_at
  shoot_count

Run
  id, user_id, product_id, product_image_id,   -- both, not product alone
  garment_category, garment_meta,
  model_id, variant_id, scene_id, pose_ids[], formats[],
  status, created_at

RunImage
  id, run_id, pose_id, format, image_uri,
  qa_state (pending|approved|rejected), provenance_json
```

---

## 10. Non-functional requirements

| Area | Requirement |
|---|---|
| Latency | Model browse and filter interaction under 200ms, client-side over a loaded library |
| Throughput | A 24-image run (6 poses × 4 formats) completes within 10 minutes |
| Concurrency | 20 simultaneous runs without queue starvation |
| Cost | Tracked per image and per run; stage-02 cache hit rate reported |
| Storage | Plates served as WebP with JPEG fallback, ~1400×2000, CDN-backed |
| Availability | 99.5% for browse; generation degrades to a queue rather than failing |
| Accessibility | WCAG 2.1 AA. Full keyboard navigation, visible focus, no colour-only state |
| Browser support | Current and previous major versions of Chrome, Safari, Firefox, Edge |
| Responsive | Full function at 1280px and above; browse and review usable on tablet |

---

## 11. Design system

Locked. Reference implementations: `shootroom-browse.html` (customer flow), `shootroom-plate-console.html` (internal plate console), `shootroom-flow.html` (Phase 3 builder).

| Token | Value |
|---|---|
| Ground | Bone `#F6F4F0` |
| Ink | `#0E0E0E` |
| Selvedge (accent) | `#B4241F` — hairline use only: selection, required markers, live indicators. Never a fill, never on type above 11px |
| Typeface | Manrope 400/500/600/700 |
| Data typeface | IBM Plex Mono — codes, specs, system labels only |
| Layout | 70% centred column, max 1340px, 32px gutter |
| Radius | 14px cards, 8px controls, 22px chips |
| Motion | `cubic-bezier(.16,1,.3,1)`, 620ms panel expansion, 240ms everything else |
| Imagery | Grayscale at rest, full colour on hover and selection. All colour in the interface comes from photography |

---

## 12. Admin tooling (internal, out of user scope)

| ID | Requirement | Priority |
|---|---|---|
| A1 | **Plate Console** — roster browser, attribute editor, prompt writer, QA checklist, build tracking. Reference implementation: `shootroom-plate-console.html` | Must |
| A1a | Console pre-fills every attribute from the roster entry; every field is operator-overridable without editing the roster | Must |
| A1b | Console emits positive prompt, negative prompt and a JSON tag record, per plate type and per pose | Must |
| A1c | Console outputs the §7.7 storage path for each plate so uploads cannot be misfiled | Must |
| A1d | QA checklist is completed in the console before a plate can be marked built | Must |
| A1e | Optional: submit the prompt to the generation API and return candidates in the console. Human selection and QA remain mandatory | Could |
| A2 | QA queue with the §7.6 checklist, approve or reject with notes | Must |
| A3 | Bulk plate generation across a defined attribute grid | Should |
| A4 | Variant library management: add, test, retire, view cache hit rate | Must |
| A5 | Coverage dashboard against the §7.3 matrix, flagging gaps | Should |
| A6 | Casting request queue fed by F2.8 empty-state submissions | Should |
| A7 | Retire a model without breaking historical runs | Must |

---

## 13. Compliance and policy

| ID | Requirement |
|---|---|
| C1 | Every model is wholly synthetic. No plate may be derived from, trained on, or resemble an identifiable real person |
| C2 | AI-generated imagery is disclosed wherever required by the markets we sell in. Disclosure copy is reviewed by legal before launch |
| C3 | Garments shown must be the actual product; try-on output must not misrepresent fit, fabric or colour |
| C4 | Uploaded garment images are customer data — retention, deletion and access follow existing policy |
| C5 | Body-type representation is reviewed for dignity and accuracy; no attribute combination is offered that we would not put in a campaign |
| C6 | Model attribute vocabulary is reviewed for respectful language, particularly heritage and body descriptors |

---

## 14. Phasing

**Phase 1 — Launch (this document)**
Browse-first flow, four steps. Curated library. Single garment, single model per run.

**Phase 2 — Products and batch**
A Products section where users upload and manage their catalogue: images, category, SKU, colourway, size range. Shoots launch from a product detail page with the category and image pre-seeded, so the flow starts at step 02.

Batch follows from the same foundation, because a shoot configuration is already garment-independent: one configuration across every SKU in a line, one garment across an assigned cast, scheduled runs, direct push to PIM and channels.

**Phase 2.5 — Demand-driven library**
Casting requests from F2.8 become a generation queue. Gaps the market actually asks for are filled and enter the shared library, so coverage improves without speculative generation.

**Phase 3 — Custom models**
The model builder, already designed and prototyped (`shootroom-flow.html`). Users specify attributes across the full §7.2 schema. The system snaps to the nearest base model and applies only the differences as region-limited inpaints — identity and QA are inherited rather than re-earned. Full generation runs only when nothing close exists. Every result passes the §7.6 gate and enters the shared library, so one customer's custom casting becomes the next customer's browse result.

**Phase 4 — Video**
Motion output from the same plate library.

---

## 15. Open questions

| # | Question | Owner | Blocking |
|---|---|---|---|
| Q1 | Is three garment types permanent? A fourth breaks the step-01 composition | Design | Phase 1 |
| Q2 | Do favourites and saved casts ship in Phase 1, or wait? Becomes necessary past ~50 models | Product | Phase 1 scope |
| Q3 | Does the try-on model degrade on three-quarter poses? Determines whether angled poses need their own try-on plates | Engineering | §7.4 |
| Q4 | Will the `PLATE.F` base outfit trigger content filters? Two candidates now recorded in §7.5.1 — tank and short, or grey bodysuit. Must be tested before bulk generation | Engineering | §7.5 |
| Q5 | Exact base-outfit colour — stone vs. greige. Settle with the §7.6 test, six variants across five reference garments | Shootroom admin | Library build |
| Q6 | Do we hold a per-brand cast, or one shared library? Affects the data model | Product | Phase 2 |
| Q7 | Where does run state persist, and for how long? No save exists in the prototype | Engineering | Phase 1 |
| Q8 | Should saved shoot configurations be first-class and nameable in Phase 1, or wait for Products? They are the unit Phase 2 batches over | Product | Phase 1 scope |
| Q9 | Does category alone give enough signal to pick a plate well, without the garment image? A longline coat and a cropped tee are both Topwear but frame differently | Design | Phase 1 |
| Q10 | Where does product category live — our taxonomy, or mapped from the customer's existing PIM categories? | Engineering | Phase 2 |
| Q11 | Are the anchor profiles in Appendix A accurate and respectful? Needs review by people from each group, not just internal sign-off | Product | Library build |
| Q12 | Which six ethnicities ship first? Needs actual customer-base data | Product | Library build |
| Q13 | Is filter relaxation (F2.8a) automatic or user-initiated? Automatic risks showing a model that misses the one attribute they cared about | Design | Phase 1 |
| Q14 | At what library size does filtering move server-side? Not a Phase 1 concern at ~100 models | Engineering | Phase 2 |
| Q15 | At ~48 launch models, is a filter rail right, or a browsable grid with sort until the library grows? | Design | Phase 1 |
| Q16 | Do heights track population medians or fashion-industry norms? Southeast Asian feminine V1 lands at 4'11" on population medians — accurate, but below commercial casting norms | Product | Library build |
| Q17 | Do we need a 3XL slot per cell? Adds 26 models and takes the roster to 130 | Product | Library build |
| Q18 | Does androgynous ship as a third gender cell (156 models) or as selected additions to existing cells? | Product | Library build |
| Q19 | Who is the second reviewer in §7.8 step 8, and what is their throughput? At 1,248 plates a 20% audit is 250 reviews | Studio admin | Library build |

---

## 16. Success criteria

Phase 1 ships when:

1. The library meets the §7.3 coverage matrix with every plate through the §7.6 QA gate
2. A merchandiser with no training completes a run end to end, unassisted, in under five minutes
3. Output quality is indistinguishable from a photoshoot to a panel of internal reviewers at catalogue size
4. Cost per image is an order of magnitude below the photoshoot baseline
5. Stage-02 cache hit rate exceeds 70% after the first two weeks of real use

---

## Appendix A — Base model roster

104 models. Generated by the rules in §7.1. The live, editable version is the roster in `shootroom-plate-console.html`.

### Anchor profiles — shared by all four variants in a cell

| Ethnicity | Eye colour | Hair colour | Hair texture | Face | Nose | Skin range (4 steps) | Height median F / M |
|---|---|---|---|---|---|---|---|
| South Asian | Deep brown | Jet black – dark brown | Straight – loose wave | Oval / heart | Straight / rounded | Light medium → Deep brown | 158 / 170 cm |
| East Asian | Deep brown | Jet black – soft black | Pin straight | Oval / round | Low bridge / button | Porcelain → Light medium | 159 / 171 cm |
| Southeast Asian | Deep brown | Jet black – dark brown | Straight – loose wave | Round / heart | Button / wide base | Light → Tan | 154 / 165 cm |
| Middle Eastern | Warm brown | Dark brown – jet black | Loose – defined wave | Oval / oblong | Aquiline / straight | Fair → Tan | 160 / 173 cm |
| North African | Warm brown | Dark brown – jet black | Defined wave – curl | Oval / diamond | Straight / aquiline | Light medium → Deep tan | 160 / 172 cm |
| West African | Deep brown | Jet black | Coily 4B – 4C | Round / square | Wide bridge / broad | Deep tan → Ebony | 160 / 172 cm |
| East African | Deep brown | Jet black – soft black | Coily 4A – 4B | Oval / diamond | Narrow bridge / straight | Tan → Ebony | 162 / 174 cm |
| Afro-Caribbean | Deep brown | Jet black – dark brown | Curly 3C – coily 4B | Oval / heart | Rounded tip / wide | Light medium → Deep brown | 163 / 175 cm |
| Northern European | Blue / grey | Ash – blonde – dark brown | Pin straight – wave | Oblong / square | Straight / narrow | Porcelain → Light medium | 168 / 181 cm |
| Southern European | Warm brown | Dark brown – chestnut | Wave – loose curl | Oval / heart | Straight / aquiline | Fair → Olive | 164 / 176 cm |
| Latin American | Warm brown | Dark brown – jet black | Wave – loose curl | Round / heart | Rounded tip / straight | Light → Tan | 158 / 170 cm |
| Pacific Islander | Deep brown | Jet black – dark brown | Wave – curl | Round / square | Wide bridge / broad | Medium → Brown | 164 / 175 cm |
| Mixed heritage | Hazel | Dark brown – auburn | Loose curl – 3C | Oval / diamond | Rounded tip / straight | Light → Deep tan | 164 / 176 cm |

### Roster

IDs run `bm_001` to `bm_104`, ordered by ethnicity, then gender, then variant slot V1–V4.

| ID | Ethnicity | Gender | Build | Size | Height | Skin tone | Age | Atypical |
|---|---|---|---|---|---|---|---|---|
| `bm_001` | South Asian | F | Slender | S | 5'0" | Light medium | 18–24 | Freckles across nose |
| `bm_002` | South Asian | F | Average | M | 5'2" | Medium | 25–32 | — |
| `bm_003` | South Asian | F | Curvy | L | 5'5" | Tan | 33–40 | — |
| `bm_004` | South Asian | F | Plus size | XL–2XL | 5'3" | Deep brown | 41–50 | — |
| `bm_005` | South Asian | M | Slender | S | 5'5" | Light medium | 18–24 | — |
| `bm_006` | South Asian | M | Average | M | 5'7" | Medium | 25–32 | — |
| `bm_007` | South Asian | M | Athletic | L | 5'9" | Tan | 33–40 | Freckles across nose |
| `bm_008` | South Asian | M | Plus size | XL | 5'7" | Deep brown | 41–50 | — |
| `bm_009` | East Asian | F | Slender | S | 5'1" | Porcelain | 25–32 | — |
| `bm_010` | East Asian | F | Average | M | 5'3" | Fair | 33–40 | Green eyes |
| `bm_011` | East Asian | F | Curvy | L | 5'5" | Light | 41–50 | — |
| `bm_012` | East Asian | F | Plus size | XL–2XL | 5'3" | Light medium | 51–65 | — |
| `bm_013` | East Asian | M | Slender | S | 5'5" | Porcelain | 25–32 | — |
| `bm_014` | East Asian | M | Average | M | 5'7" | Fair | 33–40 | — |
| `bm_015` | East Asian | M | Athletic | L | 5'10" | Light | 41–50 | — |
| `bm_016` | East Asian | M | Plus size | XL | 5'8" | Light medium | 51–65 | Green eyes |
| `bm_017` | Southeast Asian | F | Slender | S | 4'11" | Light | 33–40 | — |
| `bm_018` | Southeast Asian | F | Average | M | 5'1" | Light medium | 41–50 | — |
| `bm_019` | Southeast Asian | F | Curvy | L | 5'3" | Medium | 51–65 | Early silver hair |
| `bm_020` | Southeast Asian | F | Plus size | XL–2XL | 5'1" | Tan | 18–24 | — |
| `bm_021` | Southeast Asian | M | Slender | S | 5'3" | Light | 33–40 | Early silver hair |
| `bm_022` | Southeast Asian | M | Average | M | 5'5" | Light medium | 41–50 | — |
| `bm_023` | Southeast Asian | M | Athletic | L | 5'7" | Medium | 51–65 | — |
| `bm_024` | Southeast Asian | M | Plus size | XL | 5'5" | Tan | 18–24 | — |
| `bm_025` | Middle Eastern | F | Slender | S | 5'1" | Fair | 41–50 | — |
| `bm_026` | Middle Eastern | F | Average | M | 5'3" | Light medium | 51–65 | — |
| `bm_027` | Middle Eastern | F | Curvy | L | 5'5" | Olive | 18–24 | — |
| `bm_028` | Middle Eastern | F | Plus size | XL–2XL | 5'3" | Tan | 25–32 | Vitiligo on hands |
| `bm_029` | Middle Eastern | M | Slender | S | 5'6" | Fair | 41–50 | — |
| `bm_030` | Middle Eastern | M | Average | M | 5'8" | Light medium | 51–65 | Vitiligo on hands |
| `bm_031` | Middle Eastern | M | Athletic | L | 5'10" | Olive | 18–24 | — |
| `bm_032` | Middle Eastern | M | Plus size | XL | 5'9" | Tan | 25–32 | — |
| `bm_033` | North African | F | Slender | S | 5'1" | Light medium | 51–65 | Gap tooth |
| `bm_034` | North African | F | Average | M | 5'3" | Olive | 18–24 | — |
| `bm_035` | North African | F | Curvy | L | 5'5" | Tan | 25–32 | — |
| `bm_036` | North African | F | Plus size | XL–2XL | 5'3" | Deep tan | 33–40 | — |
| `bm_037` | North African | M | Slender | S | 5'6" | Light medium | 51–65 | — |
| `bm_038` | North African | M | Average | M | 5'8" | Olive | 18–24 | — |
| `bm_039` | North African | M | Athletic | L | 5'10" | Tan | 25–32 | Gap tooth |
| `bm_040` | North African | M | Plus size | XL | 5'8" | Deep tan | 33–40 | — |
| `bm_041` | West African | F | Slender | S | 5'1" | Deep tan | 18–24 | — |
| `bm_042` | West African | F | Average | M | 5'3" | Brown | 25–32 | Heterochromia |
| `bm_043` | West African | F | Curvy | L | 5'5" | Deep brown | 33–40 | — |
| `bm_044` | West African | F | Plus size | XL–2XL | 5'3" | Ebony | 41–50 | — |
| `bm_045` | West African | M | Slender | S | 5'6" | Deep tan | 18–24 | — |
| `bm_046` | West African | M | Average | M | 5'8" | Brown | 25–32 | — |
| `bm_047` | West African | M | Athletic | L | 5'10" | Deep brown | 33–40 | — |
| `bm_048` | West African | M | Plus size | XL | 5'8" | Ebony | 41–50 | Heterochromia |
| `bm_049` | East African | F | Slender | S | 5'2" | Tan | 25–32 | — |
| `bm_050` | East African | F | Average | M | 5'4" | Brown | 33–40 | — |
| `bm_051` | East African | F | Curvy | L | 5'6" | Deep brown | 41–50 | Alopecia, shaved |
| `bm_052` | East African | F | Plus size | XL–2XL | 5'4" | Ebony | 51–65 | — |
| `bm_053` | East African | M | Slender | S | 5'7" | Tan | 25–32 | Alopecia, shaved |
| `bm_054` | East African | M | Average | M | 5'9" | Brown | 33–40 | — |
| `bm_055` | East African | M | Athletic | L | 5'11" | Deep brown | 41–50 | — |
| `bm_056` | East African | M | Plus size | XL | 5'9" | Ebony | 51–65 | — |
| `bm_057` | Afro-Caribbean | F | Slender | S | 5'2" | Light medium | 33–40 | — |
| `bm_058` | Afro-Caribbean | F | Average | M | 5'4" | Tan | 41–50 | — |
| `bm_059` | Afro-Caribbean | F | Curvy | L | 5'7" | Brown | 51–65 | — |
| `bm_060` | Afro-Caribbean | F | Plus size | XL–2XL | 5'5" | Deep brown | 18–24 | Prominent beauty mark |
| `bm_061` | Afro-Caribbean | M | Slender | S | 5'7" | Light medium | 33–40 | — |
| `bm_062` | Afro-Caribbean | M | Average | M | 5'9" | Tan | 41–50 | Prominent beauty mark |
| `bm_063` | Afro-Caribbean | M | Athletic | L | 5'11" | Brown | 51–65 | — |
| `bm_064` | Afro-Caribbean | M | Plus size | XL | 5'9" | Deep brown | 18–24 | — |
| `bm_065` | Northern European | F | Slender | S | 5'4" | Porcelain | 41–50 | Amber eyes |
| `bm_066` | Northern European | F | Average | M | 5'6" | Fair | 51–65 | — |
| `bm_067` | Northern European | F | Curvy | L | 5'9" | Light | 18–24 | — |
| `bm_068` | Northern European | F | Plus size | XL–2XL | 5'7" | Light medium | 25–32 | — |
| `bm_069` | Northern European | M | Slender | S | 5'9" | Porcelain | 41–50 | — |
| `bm_070` | Northern European | M | Average | M | 5'11" | Fair | 51–65 | — |
| `bm_071` | Northern European | M | Athletic | L | 6'2" | Light | 18–24 | Amber eyes |
| `bm_072` | Northern European | M | Plus size | XL | 6'0" | Light medium | 25–32 | — |
| `bm_073` | Southern European | F | Slender | S | 5'3" | Fair | 51–65 | — |
| `bm_074` | Southern European | F | Average | M | 5'5" | Light | 18–24 | Auburn hair |
| `bm_075` | Southern European | F | Curvy | L | 5'7" | Light medium | 25–32 | — |
| `bm_076` | Southern European | F | Plus size | XL–2XL | 5'5" | Olive | 33–40 | — |
| `bm_077` | Southern European | M | Slender | S | 5'7" | Fair | 51–65 | — |
| `bm_078` | Southern European | M | Average | M | 5'9" | Light | 18–24 | — |
| `bm_079` | Southern European | M | Athletic | L | 6'0" | Light medium | 25–32 | — |
| `bm_080` | Southern European | M | Plus size | XL | 5'10" | Olive | 33–40 | Auburn hair |
| `bm_081` | Latin American | F | Slender | S | 5'0" | Light | 18–24 | — |
| `bm_082` | Latin American | F | Average | M | 5'2" | Light medium | 25–32 | — |
| `bm_083` | Latin American | F | Curvy | L | 5'5" | Medium | 33–40 | Natural acne scarring |
| `bm_084` | Latin American | F | Plus size | XL–2XL | 5'3" | Tan | 41–50 | — |
| `bm_085` | Latin American | M | Slender | S | 5'5" | Light | 18–24 | Natural acne scarring |
| `bm_086` | Latin American | M | Average | M | 5'7" | Light medium | 25–32 | — |
| `bm_087` | Latin American | M | Athletic | L | 5'9" | Medium | 33–40 | — |
| `bm_088` | Latin American | M | Plus size | XL | 5'7" | Tan | 41–50 | — |
| `bm_089` | Pacific Islander | F | Slender | S | 5'3" | Medium | 25–32 | — |
| `bm_090` | Pacific Islander | F | Average | M | 5'5" | Tan | 33–40 | — |
| `bm_091` | Pacific Islander | F | Curvy | L | 5'7" | Deep tan | 41–50 | — |
| `bm_092` | Pacific Islander | F | Plus size | XL–2XL | 5'5" | Brown | 51–65 | Grey streak |
| `bm_093` | Pacific Islander | M | Slender | S | 5'7" | Medium | 25–32 | — |
| `bm_094` | Pacific Islander | M | Average | M | 5'9" | Tan | 33–40 | Grey streak |
| `bm_095` | Pacific Islander | M | Athletic | L | 5'11" | Deep tan | 41–50 | — |
| `bm_096` | Pacific Islander | M | Plus size | XL | 5'9" | Brown | 51–65 | — |
| `bm_097` | Mixed heritage | F | Slender | S | 5'3" | Light | 33–40 | Deep dimples |
| `bm_098` | Mixed heritage | F | Average | M | 5'5" | Light medium | 41–50 | — |
| `bm_099` | Mixed heritage | F | Curvy | L | 5'7" | Medium | 51–65 | — |
| `bm_100` | Mixed heritage | F | Plus size | XL–2XL | 5'5" | Deep tan | 18–24 | — |
| `bm_101` | Mixed heritage | M | Slender | S | 5'7" | Light | 33–40 | — |
| `bm_102` | Mixed heritage | M | Average | M | 5'9" | Light medium | 41–50 | — |
| `bm_103` | Mixed heritage | M | Athletic | L | 6'0" | Medium | 51–65 | Deep dimples |
| `bm_104` | Mixed heritage | M | Plus size | XL | 5'10" | Deep tan | 18–24 | — |
