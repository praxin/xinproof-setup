# Set up a Xinproof runner

This creates, in your project: a service account that can only **read** your
backup bucket, one small **e2-micro** VM (free tier in us-central1), and the
Xinproof runner on it. Your backups are restored on that VM and deleted; only
results (sizes, fingerprints, table names, row counts) leave your project.

## Start

Click the ▶ button to run it:

```sh
bash gcp/setup.sh
```

It shows an 8-letter code. Type it on the Runners page in Xinproof Cloud and
click **Approve**. The script then finishes by itself in about a minute.
