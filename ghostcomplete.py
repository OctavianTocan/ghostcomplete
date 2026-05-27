#!/usr/bin/env python3
"""GhostComplete — system-wide LLM autocomplete for macOS.

Reads what you're typing in any app via the Accessibility API,
sends context to a cloud LLM, and shows the suggestion as ghost
text in a floating overlay.  Tab to accept, Esc to dismiss.

Requires: macOS 14+, Accessibility + Input Monitoring permissions.
"""

import sys
import json
import os
import threading
import time
import urllib.request

from PyObjCTools import AppHelper
from AppKit import (
    NSApplication,
    NSWindow,
    NSTextField,
    NSColor,
    NSFont,
    NSMakeRect,
    NSWindowStyleMaskBorderless,
    NSBackingStoreBuffered,
    NSApplicationActivationPolicyAccessory,
    NSFloatingWindowLevel,
    NSScreen,
)
from Quartz import (
    CGEventTapCreate,
    CGEventGetIntegerValueField,
    CGEventGetFlags,
    CGEventMaskBit,
    CGEventCreateKeyboardEvent,
    CGEventKeyboardSetUnicodeString,
    CGEventPost,
    CGEventSourceCreate,
    CFMachPortCreateRunLoopSource,
    CFRunLoopAddSource,
    CFRunLoopGetCurrent,
    kCGSessionEventTap,
    kCGHeadInsertEventTap,
    kCGEventTapOptionDefault,
    kCGEventKeyDown,
    kCFRunLoopCommonModes,
    kCGHIDEventTap,
    kCGEventSourceStateHIDSystemState,
    kCGKeyboardEventKeycode,
    kCGEventFlagMaskCommand,
    kCGEventFlagMaskControl,
)
from ApplicationServices import (
    AXUIElementCreateSystemWide,
    AXUIElementCopyAttributeValue,
    AXIsProcessTrusted,
)

# ── Configuration ────────────────────────────────────────────────────
# OpenAI-compatible endpoint. Works with OpenAI, OpenRouter, LiteLLM,
# Ollama (http://localhost:11434/v1/chat/completions), etc.
API_URL = "https://api.openai.com/v1/chat/completions"
API_KEY = os.getenv("OPENAI_API_KEY", "")
MODEL   = "gpt-4o-mini"

DEBOUNCE     = 0.5   # seconds of silence before requesting a completion
MAX_CONTEXT  = 500   # characters of trailing text sent to the LLM
API_TIMEOUT  = 4     # seconds
FONT_SIZE    = 14
GHOST_ALPHA  = 0.55
TYPE_DELAY   = 0.005 # seconds between synthetic keystrokes
# ─────────────────────────────────────────────────────────────────────

TAB    = 48
ESCAPE = 53

_gc = None  # global handle for the event-tap callback


def _tap_callback(proxy, event_type, event, refcon):
    """CGEventTap callback — runs on the main thread for every keyDown."""
    keycode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode)
    flags   = CGEventGetFlags(event)

    if flags & (kCGEventFlagMaskCommand | kCGEventFlagMaskControl):
        return event

    if keycode == TAB and _gc and _gc.showing:
        AppHelper.callAfter(_gc.accept)
        return None  # swallow Tab

    if keycode == ESCAPE and _gc and _gc.showing:
        AppHelper.callAfter(_gc.dismiss)
        return None

    # Any other key: hide current ghost text, restart debounce
    if _gc:
        AppHelper.callAfter(_gc.dismiss)
        _gc._restart_debounce()

    return event


class GhostComplete:
    def __init__(self):
        self.suggestion = ""
        self.showing    = False
        self._overlay   = None
        self._label     = None
        self._timer     = None
        self._tap       = None
        self._tap_src   = None

    # ── Lifecycle ────────────────────────────────────────────────────

    def run(self):
        global _gc
        _gc = self

        app = NSApplication.sharedApplication()
        app.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

        if not AXIsProcessTrusted():
            print(
                "\n⚠  Accessibility permission not granted.\n"
                "   System Settings → Privacy & Security → Accessibility\n"
                f"   Add:  {sys.executable}\n"
            )
            sys.exit(1)

        self._make_overlay()
        self._install_tap()

        print("GhostComplete running.  Tab = accept · Esc = dismiss · Ctrl-C = quit")
        AppHelper.runEventLoop()

    # ── Overlay window ───────────────────────────────────────────────

    def _make_overlay(self):
        rect = NSMakeRect(0, 0, 600, 24)
        w = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            rect, NSWindowStyleMaskBorderless, NSBackingStoreBuffered, False,
        )
        w.setLevel_(NSFloatingWindowLevel + 1)
        w.setOpaque_(False)
        w.setBackgroundColor_(NSColor.clearColor())
        w.setIgnoresMouseEvents_(True)
        w.setHasShadow_(False)
        # Show on all Spaces and over fullscreen apps
        w.setCollectionBehavior_(1 | 8 | 256)

        lbl = NSTextField.alloc().initWithFrame_(rect)
        lbl.setBezeled_(False)
        lbl.setDrawsBackground_(False)
        lbl.setEditable_(False)
        lbl.setSelectable_(False)
        lbl.setTextColor_(
            NSColor.colorWithCalibratedRed_green_blue_alpha_(
                0.5, 0.5, 0.5, GHOST_ALPHA,
            )
        )
        lbl.setFont_(NSFont.systemFontOfSize_(FONT_SIZE))
        w.contentView().addSubview_(lbl)

        self._overlay = w
        self._label   = lbl

    # ── Event tap ────────────────────────────────────────────────────

    def _install_tap(self):
        mask = CGEventMaskBit(kCGEventKeyDown)
        self._tap = CGEventTapCreate(
            kCGSessionEventTap,
            kCGHeadInsertEventTap,
            kCGEventTapOptionDefault,
            mask,
            _tap_callback,
            None,
        )
        if self._tap is None:
            print(
                "\n⚠  Could not create event tap.\n"
                "   System Settings → Privacy & Security → Input Monitoring\n"
                f"   Add:  {sys.executable}\n"
            )
            sys.exit(1)

        self._tap_src = CFMachPortCreateRunLoopSource(None, self._tap, 0)
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(), self._tap_src, kCFRunLoopCommonModes,
        )

    # ── Debounce ─────────────────────────────────────────────────────

    def _restart_debounce(self):
        if self._timer:
            self._timer.cancel()
        self._timer = threading.Timer(DEBOUNCE, self._on_debounce)
        self._timer.start()

    def _on_debounce(self):
        ctx = self._read_context()
        if not ctx or len(ctx.strip()) < 10:
            return
        suggestion = self._complete(ctx)
        if suggestion:
            AppHelper.callAfter(self._show, suggestion)

    # ── Accessibility reads ──────────────────────────────────────────

    def _read_context(self):
        """Return the trailing text from the focused text field, or None."""
        system = AXUIElementCreateSystemWide()

        err, app_ref = AXUIElementCopyAttributeValue(
            system, "AXFocusedApplication", None,
        )
        if err:
            return None

        err, elem = AXUIElementCopyAttributeValue(
            app_ref, "AXFocusedUIElement", None,
        )
        if err:
            return None

        err, val = AXUIElementCopyAttributeValue(elem, "AXValue", None)
        if err or val is None:
            return None

        text = str(val)
        return text[-MAX_CONTEXT:]

    def _get_overlay_origin(self):
        """Best-effort screen position for the overlay. Returns (x, y) in
        Cocoa coordinates (origin bottom-left) or None."""
        system = AXUIElementCreateSystemWide()

        err, app_ref = AXUIElementCopyAttributeValue(
            system, "AXFocusedApplication", None,
        )
        if err:
            return None

        err, elem = AXUIElementCopyAttributeValue(
            app_ref, "AXFocusedUIElement", None,
        )
        if err:
            return None

        err_p, pos_val  = AXUIElementCopyAttributeValue(elem, "AXPosition", None)
        err_s, size_val = AXUIElementCopyAttributeValue(elem, "AXSize", None)
        if err_p or err_s or pos_val is None or size_val is None:
            return None

        try:
            from Quartz import AXValueGetValue, kAXValueTypeCGPoint, kAXValueTypeCGSize
            ok1, pt = AXValueGetValue(pos_val,  kAXValueTypeCGPoint, None)
            ok2, sz = AXValueGetValue(size_val, kAXValueTypeCGSize,  None)
            if ok1 and ok2:
                screen_h = NSScreen.mainScreen().frame().size.height
                # Place overlay just below the text element
                cocoa_y = screen_h - pt.y - sz.height - 26
                return (pt.x + 4, cocoa_y)
        except Exception:
            pass

        return None

    # ── LLM API ──────────────────────────────────────────────────────

    def _complete(self, context):
        body = json.dumps({
            "model": MODEL,
            "messages": [
                {
                    "role": "system",
                    "content": (
                        "You are an inline autocomplete engine. "
                        "Given the text the user has typed so far, predict "
                        "the most likely continuation. Reply with ONLY the "
                        "continuation text — no quotes, no explanation. "
                        "Keep it to one short sentence or natural phrase. "
                        "Do not repeat any of the input."
                    ),
                },
                {"role": "user", "content": context},
            ],
            "max_tokens": 50,
            "temperature": 0.3,
        }).encode()

        req = urllib.request.Request(
            API_URL,
            data=body,
            headers={
                "Content-Type":  "application/json",
                "Authorization": f"Bearer {API_KEY}",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=API_TIMEOUT) as r:
                data = json.loads(r.read())
            return data["choices"][0]["message"]["content"].strip()
        except Exception as e:
            print(f"[ghostcomplete] API error: {e}")
            return None

    # ── Show / Accept / Dismiss ──────────────────────────────────────

    def _show(self, text):
        self.suggestion = text
        self.showing    = True
        self._label.setStringValue_(text)

        origin = self._get_overlay_origin()
        if origin:
            self._overlay.setFrameOrigin_(origin)

        self._overlay.orderFront_(None)

    def accept(self):
        if not self.suggestion:
            return
        text = self.suggestion
        self.dismiss()
        self._type_string(text)

    def dismiss(self):
        self.suggestion = ""
        self.showing    = False
        self._overlay.orderOut_(None)

    def _type_string(self, text):
        """Insert text by posting synthetic keyboard events."""
        src = CGEventSourceCreate(kCGEventSourceStateHIDSystemState)
        for ch in text:
            down = CGEventCreateKeyboardEvent(src, 0, True)
            CGEventKeyboardSetUnicodeString(down, 1, ch)
            CGEventPost(kCGHIDEventTap, down)

            up = CGEventCreateKeyboardEvent(src, 0, False)
            CGEventKeyboardSetUnicodeString(up, 1, ch)
            CGEventPost(kCGHIDEventTap, up)

            time.sleep(TYPE_DELAY)


if __name__ == "__main__":
    GhostComplete().run()
