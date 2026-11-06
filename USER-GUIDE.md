# vaultphotos user guide

Install the plugin with the [instructions in the README](README.md#installing).

The plugin renders photos and runs the service's publish command, which
decides what to store and where. This guide covers the plugin's settings
and how Lightroom actions reach the command. For vaultsite's storage
behavior, see "Lightroom publishing" in its user guide.

- [Setting up](#setting-up)
- [Lightroom actions](#lightroom-actions)
- [Good to know](#good-to-know)

## Setting up

In the **Publish Services** panel, set up **Vault Photos**:

- **Command line:** the program's absolute path and its arguments, quoted
  for `/bin/sh` if they contain spaces or shell characters. For
  vaultsite:

  ```sh
  /Users/me/go/bin/vaultsite lr-publish /Users/me/Vault mycatalog
  ```

  The last two arguments are a directory in the vault
  and the name of the service's entry under `lr_publish` in `site.yaml`.
  Lightroom runs the command with a minimal `PATH`, so use an absolute
  program path. The dialog checks the configuration when it opens and
  about 0.3 seconds after typing stops. Errors appear in red and block
  saving. While an error remains, checks repeat every 2 seconds for about
  15 minutes, so fixes made outside Lightroom appear without retyping.

  To try it first, run the command line in a terminal. Without the
  request and response files that the plugin adds, `vaultsite lr-publish`
  checks the configuration, lists the folders, and prints the command line
  to paste here, with absolute paths.
- **Format, size, and metadata:** the usual export settings. The command may
  accept only some formats: vaultsite makes thumbnails only from JPEG,
  PNG, and TIFF. Published images carry the metadata chosen here, so choose
  **Copyright Only** to leave out location, capture time, and camera
  details.

Complete the command's setup, then add photos to the default collection
or create your own and publish. You can delete the default collection.
Each service needs its own command configuration, such as its own
`lr_publish` entry.

## Lightroom actions

- **Publish** renders the pending photos, then sends the successful
  renditions to the command in one call. An operation error fails all
  photos in that call; a per-photo error fails only that photo. Failed
  photos remain pending for the next publish.
- **Cancel** during rendering skips the command call. Photos remain
  pending for the next publish. Once the command starts, it runs to
  completion.
- **Removing photos** from a collection and publishing asks the command to
  delete them. Unconfirmed deletions are retried at the next publish.
- **Mark to Republish** sends the photo and its caption again at the next
  publish.
- **Renaming or moving** a collection or set tells the command at once,
  with the updated collection paths, without rendering photos.
- **Deleting a collection** tells the command at once when you choose to
  delete its photos from the service, otherwise at the next publish of any
  collection, when the command sees that the collection is gone.

Repeated warnings appear at most once per minute; every occurrence is
logged. Errors from renaming, moving, or deleting collections are logged
without undoing the Lightroom change. The next publish retries the sync.

## Good to know

- The caption goes to the command with each publish of the photo.
  Lightroom marks a photo to republish when its develop settings change,
  and when its metadata changes if the service's metadata setting
  includes it.
- If a change to the command's configuration makes Lightroom offer to
  republish all photos, follow the command's guidance on whether existing
  photos need updating.
- Changing the image format affects photos as they are republished. To
  keep one format throughout a collection, mark all its photos to republish.
- The plugin's log is
  `~/Library/Logs/Adobe/Lightroom/LrClassicLogs/vaultphotos.log`. The
  command's stderr is copied into it.
- Video isn't supported.
