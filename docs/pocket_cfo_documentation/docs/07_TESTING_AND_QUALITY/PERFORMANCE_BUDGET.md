# Performance Budget and Measurement Plan

Initial targets are hypotheses to validate, not guaranteed performance. Select reference low/mid/high devices and publish supported OS versions before baselining.

| Area | Initial budget | Measurement
|---|---|
| Cold startup | <3 seconds to usable shell on reference mid-range device | Release/profile build, repeated cold starts |
| Cached dashboard | <1 second after local DB opens | Instrumented start/end timings |
| Transaction list | Stable smooth scroll on agreed dataset | Frame timing and memory profile |
| Local save | <300 ms target for common transaction on reference device | DB transaction timing |
| Search/filter | Responsive while typing; stale results never flash | BLoC timing and UI profiling |
| Memory | No unbounded growth during long history/analytics session | Long-running profiling |
| Animation | No sustained jank on target device matrix | Frame raster/build timing |
| Sync | Bounded batching and backoff; no UI-thread blocking | Network/worker instrumentation |

Benchmark with synthetic dataset sizes (small, typical, stress), release builds, airplane-mode/offline states and both themes. Record device, OS, app build, dataset, median/p95 and regressions.
