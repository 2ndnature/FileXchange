FileXchange
===========

FileXchange offers a way for iOS apps to send multiple files to each other. It uses the "Open In..." feature of iOS to hand over a list of the files and information on how to retrieve them from the sender.

Transfers and communication are done using Robbie Hanson's CocoaHTTPServer class.

PhotoCopy
=========
Photosmith and ShutterSnitch use FileXchange to share photos specifically, dubbing the service "PhotoCopy".

If you wish to add PhotoCopy to your app:

 * To avoid confusion, use the exact name "PhotoCopy" in your UI. One word, with a capital P and C.
 * Included in the FileXchangeSender project are icons you can use if your UI needs graphics.

If you have any questions about implementation or want your PhotoCopy-enabled app listed here, please tweet me @2ndNatureDev.

FileXchange and PhotoCopy are free for all to use / implement.

Apps that use PhotoCopy
=======================
[Photosmith](http://www.photosmithapp.com)
[ShutterSnitch](http://www.shuttersnitch.com)
[FlickStackr](http://ipont.ca/ip/flickstackr/index.html)