# Building MaeShare

MaeShare is built for `armel` with a Maemo 5 (Fremantle) cross toolchain. Two parts are
compiled here; a third (the network core) is inherited from MeeShare.

## Quick way: make

The root `Makefile` does the steps below for the client and the package (`make help`):

```sh
make CXX=<cross g++> SYSROOT=<Fremantle sysroot with Qt 4.7> MOC=<moc of Qt 4.7> QJSON=<qjson sources>   # build/maeshare
make i18n-check                                                    # translations complete? (needs node)
make deb BASE_DEB=maeshare_1.0.3_armel.deb ...                     # package on top of the author's release
make deploy DEVICE=root@<phone>                                    # copy the program and the QML files to a phone
```

`probe` (the network core), the alias word lists and the sharing plugin are not built here: `make deb` takes them from the release package of the author.
The moc must be the one of Qt 4.7 (the moc of the SDK is an i386 scratchbox program; build one from the Qt 4.7.4 sources: qmake, `src/tools/bootstrap`, `src/tools/moc`).
The manual steps follow.

## What is in this archive

```
src/app/              Qt 4.7 / QML client: app.cpp, transfer.h, singleinstance.h, qml/
src/sharing-plugin/   Maemo libsharing plugin: libmaeshare-plugin.c, service XML, Makefile
```

This archive is source only. The prebuilt `maeshare_1.0.0_armel.deb` ships as a separate
asset on the release page; `dist/` appears here only if you build a package yourself.

The network core is the `probe` helper (LocalSend v2 REST implementation) inside
`/opt/maeshare/probe`. Its source is the MeeShare / ChengChihz-MeeGo-Share controller
layer (Apache-2.0), compiled from that upstream tree and linked into the package; it is
not duplicated in this archive to keep a single authoritative copy of the attribution
chain. See `NOTICE`.

## Toolchain

- `arm-linux-gnueabi-gcc` (Maemo 5 cross compiler, glibc 2.5 sysroot)
- Qt 4.7.4 target libraries (CSSU) + a matching host `moc` (Qt 4.7 `moc` is required —
  4.8-generated code will not link against 4.7)
- QJson (compiled once for the host and once for armel)

## Building the client

```sh
# qml was already generated for Qt 4.7; moc uses transfer.h / singleinstance.h
moc transfer.h -o moc_transfer.cpp
moc singleinstance.h -o moc_singleinstance.cpp
arm-linux-gnueabi-g++ -fPIC -O2 -I<qt47 include> -I<qjson include> \
    app.cpp moc_transfer.cpp moc_singleinstance.cpp main.cpp \
    -o n900-lanshare -lQtDeclarative -lQtGui -lQtNetwork -lQtCore -lstdc++ -lm
```

`main.cpp` (QApplication bootstrap) comes from the upstream MeeShare tree, the QML
resources (`qml/*.qml`, `qml/i18n.js`, `qml/icons/`) are copied next to the binary at
install time.

## Building the share plugin

The plugin only needs libc and libdl — no glib, no GTK, no Qt:

```sh
cd src/sharing-plugin
arm-linux-gnueabi-gcc -fPIC -O2 -shared -Wl,-soname,libmaeshare.so \
    -o libmaeshare.so libmaeshare-plugin.c
```

The `Makefile` in that directory wraps the same command (`make`, `make deploy`).
Install:

```sh
cp libmaeshare.so        /usr/lib/sharing/plugins/
cp maeshare.service.xml  /usr/share/sharing/services/
cp sharing_maeshare.png  /usr/share/icons/hicolor/48x48/apps/
pkill -x sharing-manager
DISPLAY=:0 DBUS_SESSION_BUS_ADDRESS=<session bus> setsid /usr/bin/sharing-manager
```

## Packaging

The `.deb` in `dist/` was produced with `dpkg-deb --build` from a staging root containing
`/opt/maeshare` (binary + QML + icons), the three share-integration files above, and
`DEBIAN/{control,postinst,prerm}`. The hooks restart `sharing-manager` so the new service
descriptor is picked up.

### Release hygiene

Build with path mapping so the shipped binaries do not carry the build machine's
absolute paths (asserts and debug strings embed `__FILE__`):

```sh
-ffile-prefix-map=/home/<user>=. -ffile-prefix-map=<sysroot>=sysroot
```

The `.deb` itself must contain only program files: no `*.pem` / `*.key` (the device
generates its identity in `~/.config/localsend` on first launch), no `.conf`, no history
files, no test harness QML. The package ships no per-device data.

## ABI notes worth reading before you change the plugin

The Maemo share framework is undocumented; four details decide whether a plugin works at
all (see `README.md` for the full write-up):

1. `sharing_plugin_interface_init` must return `0`, otherwise the module is unloaded
   immediately.
2. Account callbacks receive **shifted** arguments: parameter 1 is the `SharingService*`,
   parameter 2 is the `SharingAccount*`.
3. The plugin must provision its own account (store + `username`/`password`/`realm`/
   `valid` parameters) and return `0`; `account_validate` must return `0` as well.
4. `sharing_entry_media_get_localpath()` points at a temporary outbox file that is
   deleted as soon as `send` returns — copy it first.
