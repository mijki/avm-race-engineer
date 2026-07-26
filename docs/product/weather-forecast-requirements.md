# Weather Forecast Requirements

Status: `Planned`

## Purpose

Weather forecasting is a first-class subsystem of AVM Race Engineer. It must
support both AVM PitWall and Engineer Console without overstating what the
active source actually knows about future conditions.

The system must distinguish:

1. measured current weather;
2. measured current track condition;
3. controller-provided current-to-next transition;
4. authoritative server or controller schedule;
5. AVM-derived trend;
6. AVM-estimated future conditions;
7. unknown future conditions.

The product must never present a derived trend as an authoritative schedule.

## Canonical Weather Labels

All user-facing weather status language must use these explicit labels:

- `CURRENT`: direct current measurement
- `SCHEDULED`: authoritative future schedule from a server or controller source
- `ESTIMATED`: AVM model output with uncertainty
- `TRENDING`: recent measured direction, not a promise
- `UNKNOWN`: no trustworthy future claim is available
- `STALE`: previously known data is no longer fresh enough to trust normally

These labels must remain visible in both contracts and UI. They are not
interchangeable.

## Terminology Rules

- `Probability` is allowed only when a source genuinely supplies probability.
- `Confidence` explains how trustworthy AVM believes a value is.
- `Intensity` describes how strong the measured or forecast weather state is.
- `Transition progress` describes movement between weather states.

Rain probability must not be fabricated from intensity, confidence, or trend
alone.

## Weather Timeline Requirements

The first forecast timeline must support these display buckets:

- `now`
- `+5 minutes`
- `+10 minutes`
- `+15 minutes`
- `+20 minutes`
- `+25 minutes`
- `+30 minutes`

The timeline should be extensible to longer endurance horizons later.

Each point should preserve:

- bucket time window;
- weather type;
- precipitation type where known;
- rain intensity;
- ambient and road temperature where available;
- track wetness and standing water where available;
- wind information where available;
- source type and source identity;
- generated time and source age;
- confidence and uncertainty;
- authoritative versus interpolated status;
- reason codes.

A five-minute display bucket does not mean the original source had exact
five-minute resolution. Aggregation, interpolation, resampling, missing
buckets, and stale-source handling must remain explicit.

## Driver Weather UX Requirements

The driver must see only compact weather context:

- current weather;
- current track condition;
- the next meaningful weather change;
- scheduled or estimated time until that change when justified;
- provenance and confidence in concise form;
- expected tyre crossover implication;
- strategy implication;
- any active engineer instruction.

Examples of acceptable compact framing:

- `CURRENT Dry`
- `RAIN EXPECTED 8-12 minutes Estimated`
- `HEAVY RAIN Scheduled in 10 minutes`
- `WEATHER UNKNOWN`
- `WEATHER STALE`

The in-car race view must not show a dense weather chart while driving.
Critical weather messaging must never rely on color alone, and weather alerts
must follow the same bounded sound and repetition rules as other driver alerts.

## Engineer Weather UX Requirements

Engineer Console must show the richer weather model:

- current measured conditions;
- source health and provenance;
- five-minute forecast timeline;
- scheduled versus estimated versus trending distinction;
- historical measured timeline and forecast-versus-actual comparison;
- confidence and uncertainty detail;
- rain intensity;
- air temperature, track temperature, wetness, standing water, wind, and grip
  trend where proven;
- drying or wetting rate;
- tyre crossover implications;
- pace, fuel, and pit-window effects;
- alternative weather scenarios;
- empty, stale, degraded, and unknown states;
- forecast-versus-actual comparison.

The engineer view must make empty, stale, degraded, conflicting, and unknown
states explicit rather than filling gaps with optimistic defaults.

## Empty, Stale, Degraded, And Unknown Behavior

The weather subsystem must define conservative behavior when:

- no future source exists;
- only current weather exists;
- only current and upcoming type exist;
- transition timing is unknown;
- the weather controller changes;
- the server reconnects;
- weather data becomes stale;
- the forecast conflicts with measured conditions;
- the forecast is incompatible with the current session;
- insufficient history exists;
- a provider fails.

In these cases the UI should prefer `UNKNOWN`, `STALE`, or clearly reduced
confidence rather than false precision.

## Weather Strategy Integration

Weather and track state must influence:

- representative sample selection;
- pace and fuel models;
- tyre degradation and tyre choice;
- tyre crossover timing;
- pit-window recommendations;
- expected traffic pace where supported;
- expected pit-release traffic where supported;
- next-stint fuel requirement;
- forecast confidence;
- strategy feasibility.

The system must preserve provenance when weather influences strategy. Users
must be able to tell whether a recommendation came from a scheduled source, an
estimated source, a measured trend, or a degraded fallback.

## Product Boundary Rules

- AVM PitWall consumes compact weather outcomes and labels.
- Driver Bridge is the expected owner of low-latency current weather capture
  and compact snapshot production where local evidence exists.
- Relay Server may ingest weather context, compare scenarios, and preserve
  source provenance.
- Engineer Console visualizes weather evidence and strategy consequences; it
  does not become an authoritative forecast source by presentation alone.

## Non-Negotiable Rules

- Do not imply that future weather is always available.
- Do not present five-minute display buckets as automatically authoritative.
- Do not collapse scheduled, estimated, trending, unknown, and stale into one
  generic "forecast" status.
- Do not fabricate rain probability from intensity or confidence.
