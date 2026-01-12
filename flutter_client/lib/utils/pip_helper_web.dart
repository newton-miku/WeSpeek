import 'dart:js_interop';
import 'package:web/web.dart' as web;

void enablePiP(int? textureId) {
  final document = web.window.document;
  final videos = document.getElementsByTagName('video');
  if (videos.length > 0) {
    final video = videos.item(videos.length - 1) as web.HTMLVideoElement;
    video.requestPictureInPicture().toDart;
  }
}
