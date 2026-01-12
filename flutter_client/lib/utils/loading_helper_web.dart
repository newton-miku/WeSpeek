import 'dart:js_interop';

@JS('hideLoadingIndicator')
external void _hideLoadingIndicator();

void hideLoading() {
  try {
    _hideLoadingIndicator();
  } catch (_) {}
}
