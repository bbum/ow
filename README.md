ow
==

OS X and iOS tools for interacting with Owon Oscilloscopes.

Currently allows screenshots and binary (not deep memory) dumps to be captured over the network.   Will also summarize a binary file.

Example:

     ~/ow net screen /tmp/screen.bmp
     
The above will capture whatever is currently on the screen on the oscilloscope to /tmp/screen.bmp.  Note that the host and port are read from the defaults database or can be specified on the command line.

Implementation Notes
--------------------

The implementation is such that both network downloading and binary file analysis can easily be extracted for use in other programs. Note that the code will *almost* work on iOS;  the use of NSInputStream and NSOutputStream will need to be refactored to use CF*Stream.

The command line tool does all command line argument processing through a slightly modified version of Dave Dribin's wonderful DDCLI project.  The modifications enable the whole *program <opts> subcommand <opts> <args>* pattern akin to `launchctl`, `git`, `svn`, etc… to be easily implemented.

If you were to want to embed Owon oscilliscope support into your OS X or iOS application, start with the classes in the **Owon Oscilliscope Classes** group.  In particular, the **OwOscilloscope** class provides a simple to use interface for talking to an Owon scope (currently limited to LAN based communications).   The **OwBinFile** class implements decoding of the binary data files from an Owon scope (it is currently incomplete;  needs to have the math added that converts the raw samples into actual data).

See http://www.dribin.org/dave/blog/archives/2008/04/29/ddcli/ for more info.

To Do
-----

- Implement CSV export in **OwBinFile**.   This includes adding the math bits necessary to apply the time/voltage multipliers/divisors to the raw samples.

- Add support for binary files that contain more than one channel's worth of data.

- Add support for deep memory data file decoding.

- Add an interactive mode.   Prompt the user for a name.  When user enters a name, sample a binary file and/or screenshot.   Then prompt the user for the next name.  This would allow one to easily run through a series of test scenarios;  "baseline", "control set to 5", "control set to 10", "pressed stop button", etc...

