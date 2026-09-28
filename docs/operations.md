# Appliance operations

The current AMD64 image is built from Ruby 4.0.6 on Debian Trixie, with PostgreSQL
17, Redis 8.0.2, GoAWS 0.5.4, and s6-overlay 3.2.3.2. GoAWS and s6 release downloads
are checksum checked. ARM64 build paths exist but are not verified yet.

s6 starts `prepare`, then PostgreSQL, Redis and GoAWS. Readiness oneshots check
the running dependencies, create the application database/role once, and allow
schema migration. Web starts only after migration succeeds. Startup failure
stops the container. Unexpected web/PostgreSQL/Redis exit stops the container;
GoAWS may restart under supervision (durable runner reconciliation is upcoming).
The dependency graph stops web before databases on shutdown. PostgreSQL gets a
fast shutdown signal and 15 seconds to stop. Use `docker stop --time 30 rubellum`.

`/data` holds `postgres`, `redis`, `config`, `apps`, `bundles`, `runtime`, and
`backups`. PostgreSQL uses its own user and peer-authenticated Unix socket;
Redis binds loopback. Only the HTTP port is published. The Rails secret is
generated once, fsynced, persisted with mode 0600, and reused on replacement.
An unexpected PostgreSQL major fails startup rather than overwriting the cluster.

Verified: fresh-volume boot; HTTP readiness; PostgreSQL/Redis data and Rails
secret survive restart and same-image container replacement; critical Redis
failure exits the container with a nonzero status; clean database shutdown.

Whole-instance backup/restore and cross-version upgrade commands are not yet
implemented. Do not treat copying a live database directory as a backup. Until
the coordinated backup/restore path is verified, this is a development appliance.
