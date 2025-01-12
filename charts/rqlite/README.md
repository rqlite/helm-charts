[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/rqlite/helm-charts/blob/master/LICENSE)
[![Release Status](https://github.com/rqlite/helm-charts/workflows/Release%20Charts/badge.svg)](https://github.com/rqlite/helm-charts/actions)
[![Artifact Hub](https://img.shields.io/endpoint?url=https://artifacthub.io/badge/repository/rqlite)](https://artifacthub.io/packages/helm/rqlite/rqlite)

# rqlite Helm Chart

[rqlite](https://rqlite.io) is a lightweight, easy-to-use, distributed relational database
built on SQLite.

Experienced Helm user?  Let's cut to the chase: the chart's default
[`values.yaml`](values.yaml) is what you want.


## Quick Start

First add the `rqlite` helm repository:

```bash
helm repo add rqlite https://rqlite.github.io/helm-charts
```

To install or upgrade a release named `rqlite` in a namespace called `db` run:

```bash
helm upgrade -i -n db --create-namespace rqlite rqlite/rqlite
```

This uses the default chart values, which deploys a single-node rqlite cluster on 10GiB
persistent volumes, without any authentication or TLS, accessible from within the
Kubernetes cluster at `http://rqlite.db.svc.cluster.local`.

If you want a 3 node cluster, add `--set replicaCount=3` at the end of the command.  Or,
if you'd like to change the storage size to 50GiB, say, add `--set
persistence.size=50Gi`.

Naturally, once you have more than handful of customizations you will want to use a
separate values file.  For example, `values.yaml` may contain:

```yaml
replicaCount: 3
persistence:
  size: 50Gi
resources:
  requests:
    cpu: 500m
```

Then you deploy with:

```bash
helm upgrade -i -n db --create-namespace rqlite rqlite/rqlite -f values.yaml
```

Refer to [Helm's documentation](https://helm.sh/docs/) for more usage details for Helm itself.

Finally, read through the chart's default [`values.yaml`](values.yaml), which is well
commented and currently acts as the authoritative source of the chart's configuration
values.


## Production Deployments

The default chart values will deploy an unsecured single-node rqlite instance geared toward
low-friction testing, but it means that anyone with network access to the K8s Service or
pods has free rein over the rqlite database.

This may not be suitable for production deployments in your environment.  It's recommended
you consider the following reliability and security related configuration:
 * The number of replicas (`replicaCount`), which requires at least 3 for high availability
 * Password-based authentication and user permissions (`config.users`)
 * Client-facing TLS either by means of a TLS-terminating Ingress (`ingress.enabled`) or
   by configuring rqlite's native TLS support (`config.tls.client`)
 * Depending on your personal/organizational requirements or environmental constraints,
   inter-node TLS (`config.tls.node`)
 * Properly tuned requests and limits for your workload (`requests`)

It's also recommended you either pin to a specific Helm chart version (by passing
`--version` to `helm`) or at least to a specific rqlite version (`image.tag`), particularly
if using deployment pipelines, so that you have explicit control over when the software is
upgraded in your environment.


## Read-only Nodes

The chart supports deploying zero or more [readonly
nodes](https://rqlite.io/docs/clustering/read-only-nodes/), where:

* `readonly.replicaCount` specifies the number of read-only nodes for the rqlite cluster
* read-only nodes are given their own dedicated Kubernetes Service (and Ingress, if
  enabled under `readonly.ingress`)
    * remember to [use a read-consistency level of
      `none`](https://rqlite.io/docs/clustering/read-only-nodes/#querying-a-read-only-node)
      when querying the read-only endpoint, otherwise your queries will simply be
      forwarded to the cluster's current leader node, defeating the purpose of a dedicated
      read-only pool
* by default, readonly nodes inherit most of the same chart configuration values that
  voting nodes use, but most configuration can be overridden specifically for readonly
  nodes by specifying keys normally at the top-level within the `readonly` map
    * all configuration that can be overridden within `readonly` is so indicated in
      [`values.yaml`](values.yaml)
* unlike voting nodes, read-only nodes will automatically leave cluster when the pod
  gracefully terminates, making it possible to use Horizontal Pod Autoscaling for
  demand-based scaling for readonly workloads


## Secrets

The chart receives a number of configurable values that are sensitive, such as user
passwords and TLS private keys.  As a best practice, it's recommended to define sensitive
values in an appropriately secured file, separate from non-secret values.

One solution is to use the popular
[helm-secrets](https://github.com/jkroepke/helm-secrets) plugin, which allows configuring
charts using [Sops](https://github.com/getsops/sops)-encrypted values files.

Non-secret configuration is then kept in `values.yaml` as usual, while you can keep, for
example, `config.users`, `config.tls.node.key`, etc. in `secrets.yaml` which is
Sops-encrypted.  Then the chart can be deployed as:

```bash
helm upgrade -i -n db --create-namespace rqlite rqlite/rqlite -f values.yaml -f secrets://secrets.yaml
```

## Cluster Scaling and Recovery

Nodes come in two flavors: voting and read-only (non-voting).

### Scaling Voting Nodes

The chart value `replicaCount` dictates the number of voting nodes in the cluster. It's
strongly recommended that voting nodes only be scaled up or down by updating this value
and redeploying the chart (via `helm upgrade`), because the replica count is used in
multiple places in the chart (such as the PodDisruptionBudget).

Scaling voting nodes up can be done simply by increasing `replicaCount` and running `helm
upgrade`.  The new nodes will mount a fresh PV, join the cluster, and synchronize the data
before receiving requests via the K8s Service.

On the other hand, scaling voting nodes *down* should follow rqlite's [documented
procedure for removing or replacing a
node](https://rqlite.io/docs/clustering/general-guidelines/#removing-or-replacing-a-node).
You can't simply decrease `replicaCount` and be done with it, because once voting nodes
have joined the rqlite cluster, the rest of the nodes in the cluster will be expecting
them to re-join until they are explicitly removed.

The basic procedure for scaling down the voting nodes is:
 1. Redeploy the chart with the updated `replicaCount` to shrink the StatefulSet
 2. Use the `rqlite` CLI or the HTTP API to remove each node that was dropped

It's important to shrink the voters in this order. Although the rest of the cluster will
complain loudly in the logs about the missing nodes until step 2 is completed, running the
procedure in reverse will cause transactions to be routed to the removed (now leaderless)
nodes until they eventually fail their readiness probes, where clients issuing those
requests will experience HTTP 503 errors.

One caveat to this order: you must ensure you never remove more than ceiling(N/2)-1 nodes
at a time, otherwise quorum will be lost.

For example, suppose you've deployed the chart with the release name `rqlite` in a
namespace called `db`, and you have a 5-node cluster and want to shrink to 3 nodes. First,
reinstall the chart with the lower replica count:

```bash
# In practice you'll more likely update your custom values.yaml
$ helm upgrade -n db rqlite rqlite/rqlite --set replicaCount=3
```

Then you can administratively drop the last 2 nodes from the rqlite cluster:

```bash
# Connect to the first voting note of the cluster.
$ kubectl exec -n db rqlite-0 -ti -- /bin/sh
# You will need to include additional arguments if you've enabled
# user authentication (-u user:password) or client TLS (-s https).
~ $ rqlite
Welcome to the rqlite CLI.
Enter ".help" for usage hints.
Connected to https://127.0.0.1:4001 running version v8.14.1
127.0.0.1:4001> .remove rqlite-4
127.0.0.1:4001> .remove rqlite-3
```

Note that the node ids are the pod names. If you deployed the chart with a release name
`rqlite-myapp` instead, then the node ids would be `rqlite-myapp-3` and `rqlite-myapp-4`.


#### Recovering From Permanent Loss of Quorum

If you lost enough nodes to the point where quorum can't be satisfied *and* the PVs for
those pods were also lost (because otherwise you could simply scale back up to restore
quorum), you will need to perform [rqlite's quorum recovery
procedure](https://rqlite.io/docs/clustering/general-guidelines/#recovering-a-cluster-that-has-permanently-lost-quorum).

rqlite's Helm chart provides a mechanism to handle this with the `useStaticPeers` chart
value. During normal operation, `useStaticPeers` should be `false`, in which case rqlite
will use DNS provided by Kubernetes for peer discovery.

However, in the event that quorum can't be recovered, you can set `useStaticPeers` to
`true` temporarily, perform a rolling restart on all nodes in the cluster, and set it back
to `false`. Changing this value only updates a ConfigMap, so it won't trigger an unwanted
rollout of the StatefulSet when changing back to `false`.

For example, assume your deployment's usual values are in `values.yaml`, and again
assuming your release is called `rqlite` in the `db` namespace:

```bash
# Upgrade the chart with the useStaticPeers recovery setting
$ helm upgrade -n db rqlite rqlite/rqlite -f values.yaml --set useStaticPeers=true
# Restart all pods in the rqlite cluster. You can remove the last argument if
# you don't have readonly pods.
$ kubectl rollout -n db restart statefulset/rqlite statefulset/rqlite-readonly
```

At this point, once the pods restart and quiesce, quorum should be restored. As a final
step, don't forget to revert the `useStaticPeers` setting simply by redeploying the chart
using your original values without the override:

```bash
$ helm upgrade -n db rqlite rqlite/rqlite -f values.yaml
```

This last command won't restart the rqlite pods, only prevent the use of `peers.json` on
the next restart, which includes if an existing rqlite pod crashes and is restarted by the
Kubelet.


### Scaling Read-only Nodes

Read-only nodes don't participate in quorum, and the Helm chart deploys them such that
they will automatically leave the cluster on shutdown. This means the read-only
StatefulSet can be scaled up and down arbitrarily, and can even be driven by the
Horizontal Pod Autoscaler if you choose.

The chart value `readonly.replicaCount` defines the initial number of read-only replicas,
and can thereafter be dynamically scaled, either by running `kubectl scale`, using HPA, or
some other orchestrator.


## Auto Backup and Restore

rqlite provides support for [automatically backing up its data to S3-compatible
storage](https://rqlite.io/docs/guides/backup/#automatic-backups), and even automatically
restoring from that backup when the cluster is being bootstrapped from a clean (data-less)
state.

The Helm chart exposes this capability under the `config.backup` dict.  Here, the S3
storage details are provided in `config.backup.storage`, which applies to both backup and
restore, and then automatic backup and restore can be independently enabled using
`config.backup.autoBackup.enabled` and `config.backup.autoRestore.enabled` respectively.

The example below configures both automatic backup and restore to a MinIO deployment at
`s3.example.com` with credentials for a MinIO Service Account with a policy that grants
read/write access to a bucket called `rqlite`:

```yaml
config:
  backup:
    storage:
      # MinIO Service Account credentials
      accessKeyId: cdRtR5mRJMvtMJz51Cts
      secretAccessKey: YY6RieQEwbbek3rhjOPwbwEUIkg8kYhhbxrL0h3R
      bucket: rqlite
      # region is a required field, but the value doesn't generally matter with MinIO
      region: us-east-1
      path: backups/mydatabase.sqlite.gz
      # Endpoint must be defined for any non-Amazon-native S3 storage
      endpoint: https://s3.example.com
      # Most MinIO deployments use path-style requests, so unlike Amazon S3 (where this
      # is not recommended to be set), for MinIO we set it to true
      forcePathStyle: true
    autoBackup:
      # Enable automatic backups every 30 minutes
      enabled: true
      interval: 30m
    autoRestore:
      # Enable automatic restoration when the cluster is being bootstrapped
      # with no existing data.
      enabled: true
```

## Versioning

Helm charts use semantic versioning, and rqlite's chart offers the following guarantees:
 * Breaking changes will only be introduced in new major versions
    * where "breaking" is defined as you needing to modify the Helm chart values to avoid
      breaking your deployment, or when the chart points to a version of rqlite which
      itself contains breaking changes (such as non-backward-compatible API changes)
 * New features or non-breaking changes will be introduced in minor versions
    * note that changes that result in a rolling restart to the rqlite cluster are fair
      game, they are not considered breaking
 * Releases containing only bug fixes or trivial features will be introduced in patch
   releases

This approach extends to updates to rqlite itself: if rqlite releases a new minor version
(8.14.x to 8.15.0, say) and the chart's *only* update is to point to this new version, the
chart will be given a minor version increase rather than a patch-level increase, despite
the trivial nature of the change to the chart itself.


## License

[MIT License](./LICENSE).
