# Photos (for Nextcloud)
Photos (for Nextcloud) is a new gallery app for viewing your photos hosted on Nextcloud servers

[<img src="https://play.google.com/intl/en_us/badges/static/images/badges/en_badge_web_generic.png" alt="Google Play" width="160" />](https://play.google.com/store/apps/details?id=com.nkming.nc_photos.paid&referrer=utm_source%3Drepo)  
Or the [free ad-supported version](https://play.google.com/store/apps/details?id=com.nkming.nc_photos&referrer=utm_source%3Drepo)

*\*See [Web Support](#web-support) if you want to try the experimental web app*

Features:
- Support JPEG, PNG, WebP, HEIC, GIF images
- Support MP4, WebM videos (codec support may vary between devices/browsers)
- EXIF support (JPEG and HEIC only)
- Organize photos with albums that are independent of your file hierarchy
- Sign-in to multiple servers
- and more to come!

Translations (sorted by ISO name):
- français (contributed by mgreil)
- ελληνικά (contributed by Chris Karasoulis)
- Español (contributed by luckkmaxx)

This app does not require any server-side plugins.

## Video Previews/Thumbnails
The previews shown in the app are generated by the Nextcloud server. By default, Nextcloud server does not generate previews for video files. To enable this feature:
1. Install `avconv` or `ffmpeg` on the server
2. Modify `config.php` according to https://docs.nextcloud.com/server/latest/admin_manual/configuration_server/config_sample_php_parameters.html#previews
    - The most important change is adding `OC\\Preview\\Movie` to `enabledPreviewProviders`
    - If `enabledPreviewProviders` is missing in your `config.php`, the following snippet will preserve the default settings
```
<?php
$CONFIG = array (
  ...
  'enabledPreviewProviders' =>
  array (
    0 => 'OC\\Preview\\BMP',
    1 => 'OC\\Preview\\GIF',
    2 => 'OC\\Preview\\JPEG',
    3 => 'OC\\Preview\\MarkDown',
    4 => 'OC\\Preview\\MP3',
    5 => 'OC\\Preview\\PNG',
    6 => 'OC\\Preview\\TXT',
    7 => 'OC\\Preview\\XBitmap',
    8 => 'OC\\Preview\\OpenDocument',
    9 => 'OC\\Preview\\Krita',
    10 => 'OC\\Preview\\Movie',
  ),
);
```

## HEIC Previews/Thumbnails
Add `OC\\Preview\\HEIC` to `enabledPreviewProviders` in `config.php`. See [Video Previews/Thumbnails](#video-previewsthumbnails) for more details.

## Web Support
Web support is **EXPERIMENTAL** and is provided on a best effort basis. It may be subject to change at any time without notice. Please read carefully the instructions listed below or else the app will likely fail to work.

### Enable CORS support on Nextcloud server
By default your browser will block **all** requests due to the lack of CORS support. To fix it, you can add the following lines to `.htaccess` in your Nextcloud installation directory. This can only be done by admins with remote access rights to the Nextcloud server.
```
...
  ModPagespeed Off
</IfModule>
#### DO NOT CHANGE ANYTHING ABOVE THIS LINE ####

# Copy from this line
RewriteCond %{REQUEST_METHOD} OPTIONS
RewriteRule .* / [R=200,L]
SetEnvIf Origin "http(s)?://nkming2.gitlab.io$" AccessControlAllowOrigin=$0
Header always set Access-Control-Allow-Origin %{AccessControlAllowOrigin}e env=AccessControlAllowOrigin
Header always merge Vary Origin
Header always set Access-Control-Allow-Methods "*"
Header always set Access-Control-Allow-Headers "*"
Header always set Access-Control-Allow-Credentials "true"
Header always set Access-Control-Max-Age "86400"
# up to this line

ErrorDocument 403 /
ErrorDocument 404 /
<IfModule mod_rewrite.c>
...
```

You may need to reload the server config and clear browser cache afterwards.

If it's not possible to gain remote access to the server, you can instead disable CORS support in your browser. **WARNING: This is highly discouraged and must only be done with caution**

### HTTP/HTTPS
You are suggested to configure your server to accept HTTPS connections. If that's again, not possible, you must use the HTTP link below as your browser would block all HTTP communications coming from a HTTPS site.

### Ok, I'm ready
Cool. Follow the [https link](https://nkming2.gitlab.io/nc-photos-web) or the [http link](http://nkming2.gitlab.io/nc-photos-web) (use this only if your server doesn't support HTTPS)
