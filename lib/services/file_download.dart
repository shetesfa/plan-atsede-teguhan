// File download helper — one call, platform-aware.
//
// Web: triggers a REAL browser download (anchor element + download
// attribute). This is NOT a popup, so it is not blocked after async
// work the way window.open() is — it lands in the download shelf.
// Mobile/desktop: saves the bytes to the app documents folder.
//
// PR #46 (2026-11-28): the Plans header export icon and the document
// editor's "ወደ PDF አውርድ" button used Printing.sharePdf, which on the
// web opens a print dialog and often does nothing visible — the
// buttons looked dead. This helper makes the download actually happen.
export 'file_download_stub.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
