"""JavaScriptCore-backed JS-challenge solver for yt-dlp.

iOS cannot spawn child processes, so yt-dlp's built-in runtimes (deno, node,
bun, quickjs) are unusable. yt-dlp's EJS solver only needs "run this script
and give me what it printed", so we implement that on top of a callback into
the host app, which evaluates the script with the system JavaScriptCore.

The host registers its callbacks with `install_native()` right after startup
(function pointers, passed as integers, resolved here with ctypes).
"""
from __future__ import annotations

import ctypes

from yt_dlp.extractor.youtube.jsc._builtin.ejs import EJSBaseJCP
from yt_dlp.extractor.youtube.jsc.provider import (
    JsChallengeProvider,
    JsChallengeProviderError,
    JsChallengeRequest,
    register_preference,
    register_provider,
)

_evaluate = None  # Callable[[str], str] | None


def install_python(fn):
    """Install a plain-Python evaluator (used by tests)."""
    global _evaluate
    _evaluate = fn


def install_native(eval_addr: int, free_addr: int) -> None:
    """Install host callbacks given as raw function-pointer addresses.

    eval:  char *drizon_js_eval(const char *script)  -> malloc'd UTF-8 string
    free:  void   drizon_js_free(void *ptr)
    """
    eval_fn = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_char_p)(eval_addr)
    free_fn = ctypes.CFUNCTYPE(None, ctypes.c_void_p)(free_addr)

    def _call(script: str) -> str:
        ptr = eval_fn(script.encode('utf-8'))
        if not ptr:
            raise JsChallengeProviderError('JavaScriptCore returned no output')
        try:
            return ctypes.string_at(ptr).decode('utf-8')
        finally:
            free_fn(ptr)

    install_python(_call)


@register_provider
class JavaScriptCoreJCP(EJSBaseJCP):
    PROVIDER_VERSION = '1.0.0'
    BUG_REPORT_LOCATION = 'the Drizon issue tracker'
    JS_RUNTIME_NAME = 'javascriptcore'

    def is_available(self) -> bool:
        return _evaluate is not None and self._available

    @property
    def runtime_info(self):
        # No external runtime exists; the base class only uses this for gating,
        # which is_available() above replaces.
        return None

    def _run_js_runtime(self, stdin: str, /) -> str:
        if _evaluate is None:
            raise JsChallengeProviderError('JavaScriptCore bridge is not installed')
        return _evaluate(stdin)


@register_preference(JavaScriptCoreJCP)
def _preference(provider: JsChallengeProvider, requests: list[JsChallengeRequest]) -> int:
    return 1000
