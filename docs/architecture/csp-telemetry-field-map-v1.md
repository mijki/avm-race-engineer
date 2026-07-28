# CSP Telemetry Field Map V1

`apps/driver-lua/src/adapters/csp.lua` is the only live CSP boundary. The
adapter reads documented members behind protected access, preserves unavailable
values as `nil`, and emits normalized fields consumed by the live model.

| CSP source | Normalized field | Type / unit | Optional | Fallback |
| --- | --- | --- | --- | --- |
| `ac.getCar(0).isInPitlane` | `car.pit_lane` | boolean | yes | unavailable |
| `ac.getCar(0).isInPit` | `car.pit_box` | boolean | yes | unavailable |
| `ac.getCar(0).splinePosition` | `car.spline` | number, 0..1 | core | unavailable |
| `ac.getCar(0).position` | `car.world_position` | vector, metres | yes | unavailable |
| `ac.getCar(0).resetCounter` | `car.reset_counter` | integer | yes | unavailable |
| `ac.getCar(0).speedKmh` | `car.speed_kmh` | number, km/h | core | unavailable |
| `ac.getCar(0).fuel` | `car.fuel_l` | number, litres | core | unavailable |
| `ac.getCar(0).lapCount` | `session.completed_laps`, `session.race_lap` | integer, completed laps | core | unavailable |
| `ac.getCar(0).lapTimeMs` | `car.lap_time_s` | number, seconds | core | unavailable |
| `ac.getCar(0).isLapValid` | `car.lap_valid` | boolean | yes | unavailable |
| `ac.getSim().currentSessionTime` | `session.elapsed_s` | number, seconds | core | `gameTime` if verified |
| `ac.getSim().sessionTimeLeft` | `session.remaining_s` | number, seconds | yes | unavailable |
| `ac.getSim().trackLengthM` | `session.track_length_m` | number, metres | yes | unavailable |
| `ac.getSim().isReplayActive` | `session.replay` | boolean | yes | unavailable |
| `ac.getSim().ambientTemperature` | `environment.ambient_c` | number, °C | yes | unavailable |
| `ac.getSim().roadTemperature` | `environment.road_c` | number, °C | yes | unavailable |
| `ac.getSim().rainIntensity` | `environment.rain_intensity` | number, 0..1 | yes | unavailable |
| `ac.getSim().rainWetness` | `environment.track_wetness` | number, 0..1 | yes | unavailable |
| `ac.getSim().roadGrip` | `environment.grip` | number, CSP scale | yes | unavailable |
| wheel tyre members | `tyres.wheels[FL..RR]` | independent values | yes | unavailable per wheel |

`session.current_lap` is the one-based AC lap currently in progress and is
derived as `completed_laps + 1` at the adapter boundary. `session.race_lap`
remains the completed race/session count; downstream stint progress and the
driver HUD must not substitute the active-lap value for it.

The adapter records member type, protected-call result, first failure,
normalization rejection, and missing optional fields in bounded diagnostics.
The source-health layer maps current core/optional availability and sample age
to `LIVE`, `PARTIAL`, `STALE`, or `OFFLINE`; it does not expose raw CSP objects
to the view model.
