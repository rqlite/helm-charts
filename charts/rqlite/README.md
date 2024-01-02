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

The default chart values will deploy an unsecured single-node rqlite instace geared toward
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

The chart supports deploying a separate resources for [readonly
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
  voting nodes use, but most configuration can be overriden specifically for readonly
  nodes by specifying keys normally at the top-level within the `readonly` map
    * all configuration that can be overriden within `readonly` is so indicated in
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

## Versioning

Helm charts use semantic versioning, and rqlite offers the following guarantees:
 * Breaking changes will only be introduced in new major versions
    * where "breaking" is defined as you needing to modify the Helm chart values to avoid
      breaking your deployment, or when the chart points to a version of rqlite which
      itself contains breaking changes (such as non-backward-compatible API changes)
 * New features or non-breaking changes will be introduced in minor versions
    * note that changes that result in a rolling restart to the rqlite cluster are fair
      game, they are not considered breaking
 * Releases containing only bug fixes or trivial features will be introduced in patch
   releases

**Exception**: while the chart is under active development as version 0.x, breaking changes
will be introduced in minor revisions, not major ones (e.g. v0.10.0 -> v0.11.0).


## License

[MIT License](./LICENSE).
