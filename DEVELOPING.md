# Developing vaultphotos

The Lua plugin (`vaultphotos.lrplugin`) reads the catalog, renders photos,
and handles the Lightroom interface. `Command.lua` runs the publish
command with a JSON request and reads its response. Update
[PROTOCOL.md](PROTOCOL.md) and both implementations' protocol constants
when changing the request or response format.

vaultsite implements `lr-publish` in its `lrpublish` package. Its package
documentation, golden tests (`lrpublish/testdata/*.txtar`), and user guide
describe storage behavior. This repository's [user guide](USER-GUIDE.md)
covers the plugin.

## Check

```sh
make check
```

`make check` runs the Lua tests and checks the plugin's syntax. Tests use
Lightroom SDK fakes from `tests/testing.lua`; `tests/command_test.lua`
uses a shell script to test requests, responses, exit statuses, and stderr.

Keep the code compatible with Lightroom's Lua 5.1. Tests use LuaJIT when
installed, otherwise `lua`. Syntax checks use the SDK's Lua 5.1.5 compiler
at `~/Downloads/LrC_15/Lua Compiler/mac/luac`, falling back to `luac` on
`PATH`. You can override these with `LUA` and `LUAC`. Before macOS will run
the SDK compiler, make it executable, remove its quarantine attribute
(`xattr -d com.apple.quarantine`), and sign it ad hoc (`codesign -s - --force`).

## Load it in Lightroom

1. Install vaultsite (`make install` in its repository) and add an
   `lr_publish` entry to a test site's `site.yaml`.
2. **File → Plug-in Manager → Add → `vaultphotos.lrplugin`.**
3. Set a service's command line to
   `/Users/me/go/bin/vaultsite lr-publish /path/to/site service`.
4. After changing vaultsite, run `make install` there; the next call uses
   the new command, with no reload. After editing a Lua file,
   **Plug-in Manager → Reload Plug-in**. After changing `Info.lua` or adding
   a Lua file, restart Lightroom (a reload reports "Could not load toolkit
   script" for a new file).

Both sides reject unsupported protocol versions; failures appear in the log.

## Watch the log

```sh
tail -F ~/Library/Logs/Adobe/Lightroom/LrClassicLogs/vaultphotos.log
```

The command's stderr is copied to the same log. If the command fails or
returns an invalid response, the log names the retained temporary folder.
From that folder, replay the request with:

```sh
vaultsite lr-publish /path/to/site service request.json out.json
```

Lightroom deletes renditions after publishing. To replay a publish request,
first replace its `rendition` paths with existing image files. An operation
error in a valid response does not retain the temporary folder.

## End-to-end test loop

Follow each action in the plugin log and check the command's stored
records. vaultsite's tests cover its storage behavior.

1. **Settings:** an empty command line, `vaultsite` without its path (exit
   127, with the `PATH` hint), and a configuration error the command
   reports: each shows a red message, about 0.3 seconds after typing stops, and
   blocks saving. Type quickly: the log has one `check` line per pause,
   not per keystroke. Open the dialog of a service with a bad setting: the
   message shows at once. With the dialog open, fix the configuration
   outside Lightroom: the message clears after the next check, about
   2 seconds plus the command's runtime. Close the dialog with
   a problem showing: the log's `check` lines stop.
2. **First publish** of three photos in the default collection, one
   without a caption: the log has the command's trace lines and one
   `publish` line with its time; the photos show as published, and the
   command's records have all three, with the two captions. Make the
   command fail the operation (for vaultsite, a missing notes folder) and
   publish: the photos are rendered, then all fail with the message, and
   nothing is stored.
3. **Adding:** add two photos and publish: the request has those two only
   (inspect a retained `request.json`, or read the command's trace),
   and the command's records gain them.
4. **Editing a photo:** change its develop settings and publish: it's sent
   again with the same UUID. With vaultsite and an unchanged format, it
   keeps its remote ID.
5. **Removing:** remove a photo and publish: a `delete` line, and the
   photo leaves **Deleted Photos to Remove**. Make the command confirm
   nothing: the photo stays there, and is sent again at the next publish.
6. **Format:** change the service's format to TIFF and republish a photo:
   the rendition has the `.tif` extension. Change it back.
7. **Renaming and moving:** rename a collection, rename a set, move a
   collection into a set nested in another, and move a set: each logs a
   `publish` without photos, with the changed collections' new paths and
   the others unchanged; nothing is marked to republish.
8. **Deleted collection:** delete a collection and choose **Delete**: one
   `deletePublishedCollection` line, and a `publish` without photos whose
   `service` lacks it. Delete a set holding two collections and choose
   **Delete**: one line, naming `LrPublishedCollectionSet`, and both are
   missing. Delete another collection and leave its photos: no call; the
   next publish to any collection lists the collections without it.
9. **Go to Published** Collection and Photo are dimmed.
10. **Cancel** while photos are rendering: the command isn't run, the
    log says `publish canceled`, and the photos still wait to be
    published. Publish the collection again: they're sent.
11. **A failing command:** set the command line to a script that exits
    nonzero after writing to stderr: the photos fail with the end of
    stderr, and the log names the retained folder. Replace the rendition
    paths in `request.json` with existing files, then replay it with the
    real command. A response with the wrong `protocol`, or none, fails
    the same way.
12. **Warnings:** make the command return the same warning for two
    collections and publish both: one dialog, two log lines.
