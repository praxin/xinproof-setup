# Xinproof runner setup

These are the setup files behind the **Set up runner** buttons in Xinproof
Cloud. They are public so you can read exactly what gets created in your
account before you click.

Each one creates, inside **your** cloud account:

- a **read-only** identity that can only read the one backup bucket you chose;
- **one small VM** (free-tier size where the cloud has one) using that identity;
- Docker, and the Xinproof runner on it.

Nothing listens for inbound connections. The runner connects out to Xinproof
Cloud to ask for work, restores your backups on that VM in throwaway databases
with no network, and deletes them. Only results (file sizes, fingerprints,
table names, row counts, pass or fail) leave your account, signed by a key that
never leaves the VM.

| Cloud | File | How it is used |
|---|---|---|
| AWS | [aws/runner.yaml](aws/runner.yaml) | CloudFormation; the **Launch in AWS** button fills in everything |
| Azure | [azure/runner.json](azure/runner.json) | ARM template; the **Deploy to Azure** button fills in everything |
| Google Cloud | [gcp/setup.sh](gcp/setup.sh) | Runs in Cloud Shell; you approve a short code in Xinproof Cloud |

The runner itself is downloaded from Xinproof Cloud during setup with a
one-time setup code that works once, for one hour.

To remove a runner: delete the CloudFormation stack (AWS), the resource group
or the `xinproof-runner` resources (Azure), or the `xinproof-runner` VM and
service account (Google Cloud), and remove it on the Runners page.
