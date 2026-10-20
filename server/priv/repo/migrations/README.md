# Faro migrations

There are no application tables yet. Release deployment runs Ecto's migrator so
schema bookkeeping and future migrations follow the same rollout path. Add
versioned `.exs` migrations here as persistence features are implemented. Primary
and foreign keys must use UUIDs (`:binary_id`), never integer IDs.
