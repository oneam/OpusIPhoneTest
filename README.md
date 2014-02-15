This is a study to see how well the Opus audio codec works on a iPhone.

The opus code itself has purposely been left out. It can be downloaded from http://www.opus-codec.org/downloads/

Last tested on XCode 5.0.2 on OSX Mavericks using Opus 1.1.

Build Instructions
===========

1. Download and extract the Opus source code using `rake setup`
2. Build the OpusIPhoneTest project using XCode

The Opus library .xcodeproj was originally created using gyp and the opus.gyp file extracted from the WebRTC open source project (https://code.google.com/p/webrtc/). It has subsequently been updated to support Opus 1.1 and the original opus.gyp removed so that I don't wonder why it doesn't work in the future.
