# Telemetry Capability Matrix

**DRAFT — NOT IMPLEMENTED — SUBJECT TO CHANGE**

## Scope

This matrix is the F0 planning baseline for exactly 35 telemetry categories. It is intentionally conservative:

- local selected-car telemetry is preferred over relay-wide or opponent-wide promises
- teammate coverage is materially better with an active bridge than without one
- private opponent fuel, tyres, damage, setup, and controls remain unavailable in this draft
- weather, wetness, grip, wind, and aero remain low-confidence or conditional until a source inventory proves them

Authoritative field detail lives in [telemetry-capability-matrix.json](./telemetry-capability-matrix.json).

## Exact Categories

1. Session identity
2. Session timing
3. Driver identity
4. Car identity
5. Track and layout identity
6. Motion
7. Position
8. Controls
9. Engine and powertrain
10. Gearbox
11. Fuel
12. Tyres
13. Brakes
14. Suspension
15. Ride height
16. Aero where available
17. Electronics
18. Damage
19. Lap and sector timing
20. Position and classification
21. Pit state
22. Flags
23. Penalties
24. Weather
25. Track wetness
26. Track grip
27. Wind
28. Traffic
29. Nearby cars
30. Team-car state
31. Strategy state
32. Stint state
33. Connection health
34. Source health
35. Data freshness

## Notes

- The JSON matrix uses field-level properties named `canonical_name`, `source`,
  `unit`, `type`, `expected_frequency`, `local_availability`,
  `teammate_with_bridge`, `teammate_without_bridge`,
  `opponent_availability`, `classification`, `freshness`, `MVP`, `confidence`,
  and `evidence`. These correspond respectively to the requested canonical
  field name, data source, unit, data type, cadence, availability, provenance
  class, freshness requirement, MVP inclusion, confidence, and evidence
  reference.
- `classification` is constrained in meaning to `direct`, `derived`, `inferred`, or `unavailable`.
- `opponent_availability` is intentionally `unavailable` for private opponent domains such as fuel, tyres, damage, setup, and controls.
