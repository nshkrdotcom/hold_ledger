# Changelog

## Unreleased

- Removed archived review-card/model-proposal APIs, prompts, schemas and experiments.
- Kept the current question service, trace writer and comparison/evidence workflow.
  Existing trace files and historical comparison fields remain readable; retired
  review-card documents are left untouched on disk.
- Removed unused DNS clustering and telemetry scaffold dependencies.
