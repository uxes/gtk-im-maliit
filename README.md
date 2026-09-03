# im-maliit — a GTK4 input method module for Maliit

**Lets GTK4 applications use Ubuntu Touch's on-screen keyboard.**

This is a GTK4 port of [gtk-im-maliit](https://github.com/TheSittingPenguin96/gtk-im-maliit)
(the original GTK3 module). Without such a module, GTK apps cannot use the
keyboard on Ubuntu Touch: it ships a Maliit input context for **Qt
only**, and Mir advertises **no text-input Wayland protocol**, so GTK's
`im-wayland.so` has nothing to talk to either. Lomiri's session even sets
`GTK_IM_MODULE=maliit` — naming a GTK module that does not exist on the device.

The result is that no GTK application on Ubuntu Touch can raise the keyboard,
which makes most ported desktop Linux apps unusable on a phone regardless of how
well they otherwise run.

This module speaks Maliit's D-Bus protocol directly, the same way the Qt plugin
does, so it works on Wayland and through XWayland alike.

## Provenance

This repo is vibecoded slop, based on the (also vibecoded)
[gtk-im-maliit](https://github.com/TheSittingPenguin96/gtk-im-maliit) (GTK3),
itself derived from the [uFirefox](https://gitlab.com/debclick/uFirefox/) hack.

Verified working on a Fairphone 5 (Ubuntu Touch 24.04-1.x) with the Meshy
app. Fine to use as a stopgap until Mir gets a proper Wayland text-input
implementation — at that point this module becomes unnecessary.

## Status

Work in progress. The GTK3 original is verified on Ubuntu Touch 24.04, arm64.
The GTK4 port compiles; on-device verification is pending (Fairphone 5,
Ubuntu Touch 24.04-1.x, arm64).

Known gaps carried over from the original: selection and copy/paste callbacks
are acknowledged but ignored; injected key events carry no modifier state.

## Building

```sh
make                     # host build, for a quick syntax check
```

For Ubuntu Touch you need an **aarch64** build. Any cross-toolchain with GTK4
arm64 development files works; a container is the least painful route:

```sh
docker run --rm -v "$PWD:$PWD" -w "$PWD" \
  --platform linux/arm64 ubuntu:24.04 \
  sh -c 'apt-get update && apt-get install -y build-essential libgtk-4-dev && make'
```

For repeated builds, build the image once and reuse it (based on the same
container Clickable uses, so headers/ABI match the target exactly):

```sh
podman build -t im-maliit-builder -f Dockerfile.build .
podman run --rm --platform linux/arm64 -v "$PWD:/work:Z" \
  im-maliit-builder sh -c 'cd /work && make'
```

The module depends only on **GTK4, GLib and GIO**.

## Using it

### In a click app (recommended)

Ship `im-maliit.so` inside your package and point GTK at it:

```sh
export GTK_IM_MODULE=maliit
export GTK_IM_MODULE_FILE="$APP_DIR/immodules.cache"
export LD_LIBRARY_PATH="$APP_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
```

with an `immodules.cache` containing:

```
# GTK4 Input Method Modules file
"im-maliit.so"
"maliit" "Maliit" "gtk40" "" ""

```

Two things that are easy to get wrong here:

- **GTK passes the path straight to `dlopen()`.** It does *not* resolve a
  relative path against the cache file's directory, so the package directory has
  to be on `LD_LIBRARY_PATH`. An absolute path in the cache would work but fails
  `click-review`'s `lint:hardcoded_paths`.
- Click AppArmor policy **already permits** `org.maliit.server` and
  `/{,var/}run/user/*/maliit-server`, so no policy changes and no extra
  `policy_groups` are needed.

### System-wide

Ubuntu Touch's root filesystem is read-only, so this is for a distribution
image or a rootfs you control — not a phone you are just using. Click apps
should ship the module inside the package; that is the supported path.

## Protocol

As implemented by `maliit-framework` 2.3.0:

| Step | Detail |
| --- | --- |
| Discover | session bus, `org.maliit.server`, object `/org/maliit/server/address`, property `org.maliit.Server.Address.address` |
| Connect | peer connection to that address, in practice `/run/user/<uid>/maliit-server` |
| Call | `com.meego.inputmethod.uiserver1` at `/com/meego/inputmethod/uiserver1` |
| Export | `com.meego.inputmethod.inputcontext1` at `/com/meego/inputmethod/inputcontext` |

**Note the asymmetry in the last row**: the interface ends in `1`, the object
path does not. maliit-framework registers the client adaptor at
`InputContextAdaptorPath` in `connection/dbusserverconnection.cpp`. Export at
`.../inputcontext1` and the keyboard still appears — the show request is
outbound — while every keystroke coming back is silently dropped.

Outbound: `activateContext`, `updateWidgetInformation`, `showInputMethod`,
`hideInputMethod`, `reset`.

Inbound: `commitString` and `updatePreedit` become GTK `commit` and
`preedit-changed`. `keyEvent` carries editing keys as **Qt::Key** values.
Backspace and Delete are applied with `gtk_im_context_delete_surrounding()`
rather than synthesised key events — `gdk_event_put()` has to find its own way
through the focus chain, and text typed before a widget last lost focus could
not be deleted. Other keys use the synthetic path, which is correct for them.

Methods with return values — `preeditRectangle`, `selection` — must always be
answered or the server blocks.

Interface definitions:
<https://github.com/maliit/framework/tree/master/dbus_interfaces>

## Application notes

Two things every touch app needs, neither of which this module can do for you:

**Dismiss the keyboard when the user taps away from a text field.** Maliit hides
itself when the input context loses focus, but nothing takes focus off a
`GtkEntry` when the user taps a label or empty space. Handle
`button-press-event` on the **toplevel window** and clear the focus widget:

```c
if (gtk_widget_has_focus(entry)) {
    gtk_window_set_focus(GTK_WINDOW(window), NULL);
}
return GDK_EVENT_PROPAGATE;
```

Do this on the toplevel, not with a `GtkEventBox` inside a `GtkScrolledWindow`:
the event box swallows the press and kinetic scrolling stops working. A
`GtkGestureMultiPress` on the content has the opposite problem — the scrolled
window claims the touch sequence first and the gesture never fires.

**Scale your interface.** Phone panels are high-DPI but report scale 1, so an
unscaled GTK app renders at desktop size. `GDK_SCALE=2` suits a 1080-wide
screen.

## Licence

**GPL-3.0-or-later** — see [LICENSE](LICENSE).

## Origin

Written for [firefox-ut](https://github.com/TheSittingPenguin96/firefox-ut),
which packages Mozilla's official Firefox for Ubuntu Touch, and split out
because the gap it fills is platform-wide rather than Firefox-specific.
