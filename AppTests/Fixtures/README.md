# Original local playback fixture

`generated-colors.mp4` is an original synthetic eight-second color-pattern video,
created for this project without downloading media or using third-party footage.
It has H.264 baseline video and no audio. It is only bundled in the test target.
Fixture generation failed in the cloud iOS Simulator's AVAssetWriter path; this
pre-encoded fixture keeps encoding support separate from playback verification.

Reproduce with FFmpeg:

```
ffmpeg -f lavfi -i 'testsrc2=size=160x90:rate=30' -t 8 -c:v libx264 \
  -profile:v baseline -pix_fmt yuv420p -movflags +faststart -an generated-colors.mp4
```

The synthetic fixture is dedicated to the public domain (CC0-1.0).
Test source remains GPL-3.0-only. No YouTube content or credentials are included.
