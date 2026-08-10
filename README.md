# im-maliit — a GTK3 input method module for Maliit

**Lets GTK applications use Ubuntu Touch's on-screen keyboard.**

Without this, they cannot. Ubuntu Touch ships a Maliit input context for **Qt
only**, and Mir advertises **no text-input Wayland protocol**, so GTK's
`im-wayland.so` has nothing to talk to either. Lomiri's session even sets
`GTK_IM_MODULE=maliit` — naming a GTK module that does not exist on the device.

The result is that no GTK application on Ubuntu Touch can raise the keyboard,
which makes most ported desktop Linux apps unusable on a phone regardless of how
well they otherwise run.

This module speaks Maliit's D-Bus protocol directly, the same way the Qt plugin
does, so it works on Wayland and through XWayland alike.

## Status

Working. Verified in two independent applications on a **Volla Phone Plinius**
(`ansuz`), Ubuntu Touch 24.04.4, arm64:

- Firefox — typing, word suggestions, word replacement
- a plain GTK3 app with an ordinary `GtkEntry` — typing, backspace, cursor
  placement, selection

Not tested on any other device or Ubuntu Touch version.

Known gaps: `contentType` is always free text, so there are no email, number or
URL keyboard layouts; selection and copy/paste callbacks are acknowledged but
ignored; injected key events carry no modifier state.

## Building

```sh
make                     # host build, for a quick syntax check
```

For Ubuntu Touch you need an **aarch64** build. Any cross-toolchain with GTK3
arm64 development files works; a container is the least painful route:

```sh
docker run --rm -v "$PWD:$PWD" -w "$PWD" \
  --platform linux/arm64 ubuntu:24.04 \
  sh -c 'apt-get update && apt-get install -y build-essential libgtk-3-dev && make'
```

The module depends only on **GTK3, GLib and GIO**.

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
# GTK+ Input Method Modules file
"im-maliit.so"
"maliit" "Maliit" "gtk30" "" ""

```

Two things that are easy to get wrong here:

- **GTK passes the path straight to `dlopen()`.** It does *not* resolve a
  relative path against the cache file's directory, so the package directory has
  to be on `LD_LIBRARY_PATH`. An absolute path in the cache would work but fails
  `click-review`'s `lint:hardcoded_paths`.
- Click AppArmor policy **already permits** `org.maliit.server` and
  `/{,var/}run/user/*/maliit-server`, so no policy changes and no extra
  `policy_groups` are needed.

[ut-gtk3-app-template](https://github.com/TheSittingPenguin96/ut-gtk3-app-template)
does all of this for you.

### System-wide

```sh
sudo make install
sudo gtk-query-immodules-3.0 --update-cache
```

Ubuntu Touch's root filesystem is read-only, so this is for a distribution
image or a rootfs you control — not a phone you are just using.

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
