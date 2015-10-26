# showcase

The code here was taken off projects and should not run on their own.
It was modified to remove any specific terms or links that could not appear and it is only for showcase purposes.

File description

/animation/LoadingAnimation.*

A very specific loading animation was required and therefore i had to built one from scratch using QuartzCore and CoreAnimation API.
This was used in an iOS app.

/beacon/BeaconController.*

A controller whose job was to check for iBeacon devices.
When one was found a webcall was performed to link that beacon to some data server-side.
This was used in an iOS app.

/media-capture/FramegrabberController.*

The goal was to capture frames from a specific hardware using that hardware static C library and creating a video from it.
This was used in a MacOS app.

/media-capture/RecordingCommand.*

This showcase the use of AVFoundation to record and control a recording.
This was used in a MacOS app.

/socket/LibSockets.m

Basic functions used to use CoreFoundation sockets.
This was used in a Client/Server MacOS app.

/sockets/RemoteSockets.*

Continuation of the previous file, CoreFoundation sockets code to read and write from them.
This was used in a Client/Server MacOS app.

/views/PickerScrollPhotoView.*

ViewController used to capture a picture using the camera.
It allows the picture to be displayed so the use can select the portion of the picture he want to preserve.
This was used in an iOS app.

/network/WebcallApi.*

Manage all the webcall in an app by creating a NSURLSessionConfiguration object.
Reachability in handled and will change the configuration on the fly depending on the phone connexion speed.
Session is handled using cookies and the session automatically reconnect when it expires.
This was used in an iOS app.
