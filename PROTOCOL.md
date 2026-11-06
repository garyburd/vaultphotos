# The publish command protocol

The Vault Photos plugin reads the catalog, renders photos, and handles
the Lightroom interface. A **publish command**, configured in the service's
settings, stores the photos. Requests and responses use JSON.

This document defines protocol version 5, implemented by
`vaultsite lr-publish`.

## Running the command

The service's **command line** setting holds the program and its own
arguments, such as:

```sh
/Users/me/go/bin/vaultsite lr-publish /Users/me/Vault mycatalog
```

For each call, the plugin makes a temporary folder and writes
`request.json` in it. It appends the request and response paths to the
command line, each quoted, and runs the result with `/bin/sh`, from `/`:

```sh
<command line> '<dir>/request.json' '<dir>/response.json' 2>'<dir>/stderr'
```

- **The command line is shell text.** Quote arguments that contain spaces or
  shell characters.
- **PATH is `/usr/bin:/bin:/usr/sbin:/sbin`**, so name the program by its
  absolute path.
- **The command must finish before Lightroom moves on.** Lightroom waits
  for it, but stays responsive.
- **stderr** is copied to the plugin's log, a line at a time. Use it for
  trace lines.
- **The exit status** is 0 when the command wrote a response, whatever the
  outcome of the operation. Anything else is a failure of the command
  itself, such as an unreadable request. The plugin retains the temporary
  folder and reports the failure, including the last five nonblank stderr
  lines for ordinary nonzero exit codes. Exit 127 gets a program-not-found
  message; signals are reported separately.

An unreadable response or unsupported protocol version also retains the
folder. A valid response, including one with an operation error, removes
it. To replay a retained publish request, replace its `rendition` paths
with existing files: Lightroom deletes the originals after the callback.

## Requests

Every request is a JSON object with these fields and its operation's fields:

| Field | Type | Meaning |
|---|---|---|
| `protocol` | number | `5`. A command must reject a version it doesn't implement, with a nonzero exit status. |
| `op` | string | The operation: see below. |

Optional fields may be omitted. A `publish` request must include `service`,
even when it is empty (`[]`). A command should reject unknown fields to
detect mismatches early.

### Operations

| `op` | Lightroom hook | Fields |
|---|---|---|
| `check` | The settings dialog | none |
| `publish` | `processRenderedPhotos`, after rendering | `service`, `collection`, `photos` |
| `publish` | `renamePublishedCollection`, `reparentPublishedCollection`, `deletePublishedCollection` | `service` |
| `delete` | `deletePhotosFromPublishedCollection` | `collection`, `remoteIds` |

- **`check`** validates the command's own configuration. The dialog runs it
  when it opens and about 0.3 seconds after typing stops. While an error
  remains, it blocks saving and retries every 2 seconds, up to 450 retries
  after each edit, so fixes outside Lightroom are detected.
- **`publish`** stores the rendered photos of a collection. It runs after
  rendering finishes, unless the user canceled. Lightroom deletes the
  renditions after the callback returns, so the command must finish reading
  them before it exits and make any thumbnails it needs. Each publish includes
  every collection in `service`, allowing the command to detect deleted
  collections and update paths.
- **`publish` without `collection` and `photos`** only brings the records
  up to date. The plugin sends it when a collection or set is renamed,
  moved, or deleted, with `service` as it will be after the change, since
  Lightroom makes the change only after the hook returns. Lightroom reports
  a deleted collection only when the user chooses to delete its photos from
  the service. The command must also detect deletions from the collection
  list in subsequent publishes.
- **`delete`** removes photos from a collection. Only the remote IDs the
  command confirms are cleared from Lightroom's pending deletions. The
  others are retried at the next publish.

### Fields

| Field | Type | Meaning |
|---|---|---|
| `service` | array of collections | Every collection of the publish service. |
| `collection` | number | The collection's local identifier. |
| `photos` | array of photos | The renditions to store. |
| `remoteIds` | array of strings | The remote IDs to delete from the collection. |

A **collection** is an object:

| Field | Type | Meaning |
|---|---|---|
| `id` | number | Its local identifier, which never changes. |
| `path` | array of strings | The names of its enclosing collection sets, outermost first, then its own name. |

A **photo** is an object:

| Field | Type | Meaning |
|---|---|---|
| `uuid` | string | The photo's Lightroom UUID, such as `3CF3E45A-…`. A virtual copy has its own. |
| `rendition` | string | The path to the rendered file, including its extension. |
| `caption` | string | The caption, if any. |

A photo whose rendering failed isn't sent and remains pending in Lightroom.

## Responses

The command writes a JSON object:

| Field | Type | Meaning |
|---|---|---|
| `protocol` | number | `5`. The plugin rejects a response with any other value. |
| `error` | string | A user-facing explanation of an operation failure; omitted on success. |
| `warnings` | array of warnings | Problems to show the user, which didn't stop the operation. |
| `photos` | array of photo results | `publish`: one for each photo of the request. |
| `confirmed` | array of strings | `delete`: the remote IDs removed. |

- **An `error`** fails the whole operation:
  - **`check`:** the dialog shows it and blocks saving.
  - **`publish`:** every photo fails with the message. Without photos,
    it's logged, since an error there would make Lightroom offer to undo
    the change.
  - **`delete`:** it's shown as an error.
- **A warning** is an object with a `title` and a `message`. For `publish`
  and `delete`, each occurrence is logged and identical warnings appear
  in a dialog at most once per minute. The settings dialog ignores warnings
  in `check` responses; validation failures must use `error`.
- **A photo result** is an object with the photo's `uuid` and either its
  `remoteId`, which Lightroom records, or an `error`, which fails the
  photo. A photo without a result fails.

Messages are plain text for the user, and may span lines.

## Remote IDs

The command chooses each photo's remote ID, and Lightroom stores it.
Choose IDs that survive file moves: `delete` requests identify photos by
their remote IDs. Publish requests use Lightroom UUIDs. vaultsite's remote
IDs are `{id}.{ext}`: the UUID lowercased without dashes, followed by the
lowercased rendition extension. Changing the format changes the remote ID.

## Changes

- **Version 5:**
  - Photos have no `thumbnail`: the command makes thumbnails from the
    renditions.
  - Photos have no `new`: vaultsite adds a figure for any photo without
    one, and deletes the figures of removed photos.
  - No `move` or `delete-collection`: those hooks send `publish` without
    photos, with the changed `service`.
  - No `locate-collection` or `locate-photo`, and responses have no
    `path`: Lightroom's Go to Published items are disabled.
- **Version 4:** no `prepare`: a publish runs the command once, after
  rendering, and its checks fail the publish instead.
- **Version 3:**
  - Requests have no `servicePublished`: vaultsite requires the notes
    folder to exist, even before the first publish.
  - `publish` requests have no `published`: vaultsite creates a missing
    note with the photos being published only.
  - Responses have no `trash`: vaultsite marks a deleted collection's note
    rather than having the plugin move it to the Trash.
- **Version 2:**
  - Requests have no `settings`: the command reads its own configuration.
  - Photos have no `gps`.
- **Version 1:** the first, used only by the vaultphotos command.
