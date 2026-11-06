# vaultphotos

**Vault Photos** is a
[Lightroom Classic](https://www.adobe.com/products/photoshop-lightroom-classic.html)
publish service plugin. It reads the catalog, renders photos, and runs a
**publish command** to store them. The [JSON protocol](PROTOCOL.md) lets
the command choose where and how to store the photos.

[vaultsite](https://github.com/garyburd/vaultsite) implements the command as
`vaultsite lr-publish`. Its user guide's "Lightroom publishing" section
describes what it stores and where.

## Installing

1. Install vaultsite with `make install` in its repository and configure
   a service under `lr_publish` in the site's `site.yaml`, as its user
   guide's "Lightroom publishing" section describes.
2. In Lightroom Classic, choose **File → Plug-in Manager → Add** and select
   `vaultphotos.lrplugin`.
3. Set up a **Vault Photos** service in the **Publish Services** panel with
   the command line from the [user guide](USER-GUIDE.md), such as:

   ```sh
   /Users/me/go/bin/vaultsite lr-publish /Users/me/Vault mycatalog
   ```

## Documentation

- [User guide](USER-GUIDE.md): setting up the service and how Lightroom
  actions reach the command.
- [Protocol](PROTOCOL.md): the contract between the plugin and a publish
  command.
- [Developer guide](DEVELOPING.md): tests, loading the plugin in Lightroom,
  and the end-to-end test loop.
