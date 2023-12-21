# rqlite Helm Repository

## Add the rqlite Helm repository

```sh
helm repo add rqlite https://rqlite.github.io/helm-charts
```

## Install rqlite

```sh
helm upgrade -i -n db rqlite rqlite/rqlite
```

For more documentation on installing rqlite, please see the [chart's README](https://github.com/rqlite/helm-charts/tree/master/charts/rqlite).

## License

[MIT License](https://github.com/rqlite/helm-charts/blob/master/LICENSE)
