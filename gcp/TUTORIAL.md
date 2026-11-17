# Set up a Xinproof runner

This creates, in your project: a service account that can only **read** your
backup bucket, one small **e2-micro** VM (free tier in us-central1), and the
Xinproof runner on it. Your backups are restored on that VM and deleted; only
results (sizes, fingerprints, table names, row counts) leave your project.

## Start

Click the ▶ button to run it:

```sh
curl -fsSL https://xinproof-cloud.xinproof.workers.dev/agent/gcp.sh | bash
```

It shows an 8-letter code and a link. Open the link and click **Approve**
(or type the code on the Runners page). The script then finishes by itself in
about a minute. If a step fails, it says which one, and the Runners page shows
the error too.
