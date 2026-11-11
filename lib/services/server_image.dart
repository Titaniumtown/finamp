import 'package:flutter/painting.dart';
import 'package:http_image_provider/http_image_provider.dart';

import 'server_http_client.dart';

/// Loads an image from the Jellyfin server using [ServerHttpClient], so it reuses the
/// existing connections instead of opening new ones.
ImageProvider serverImage(Uri url) => HttpImageProvider(url, client: ServerHttpClient.instance);
