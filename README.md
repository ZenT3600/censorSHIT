```
censorSHIT - Simple script to avoid hash-based recognition systems on messaging apps

===

The reason I started writing this script is, as of 2023/08/23, whatsapp
has silently introduced a censorship feature on videos sent on their app.
If your video gets flagged to be censored, the audio will be removed from
the message, leaving only the video.

This program avoids this issue by slightly modifying the video file you want
to send, both in the video stream and audio stream, therefore changing its hash
value and rendering it unknown to whatsapp's detection system.
```
