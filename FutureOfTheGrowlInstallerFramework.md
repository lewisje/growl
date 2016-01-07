# Introduction #

The Growl framework is currently available in two flavors, one of which (Growl-WithInstaller.framework, or G-WI) includes a zip archive of Growl.prefPane and code and a UI to install it. When the application using the framework launches, the framework checks whether the user has Growl installed, and if they don't, asks whether they'd like to install it.

Because the current implementation includes the Growl prefpane (and GHA, and GrowlAction, and GrowlMenu), we can't release Growl-WithInstaller.framework until we release the new prefpane (and GHA, etc.). This is usually not a problem, since we release all of the components at the same time—but with 1.2, we want to get a new framework into app developers' hands before the Growl 1.2 release, which means we'd have to either release Growl.framework _way_ ahead of G-WI, or release G-WI ahead of the main Growl release (which would be really weird, since a newer Growl would be available in applications than from the Growl website).

So what we're _thinking about_ is killing off G-WI and adding a download installer to the main framework. This page is for designing that installer.

# Goals #

  * Must not come off as spammy or seem like malware.
  * Be up-front that this is an optional feature and they don't have to install it.
  * Explain clearly what benefit this will provide the user.
  * Provide a way to permanently disable the prompt.
  * Applications must be able to disable the installer entirely if they don't want it.

# Suggested wording #

(SurfWriter = application name)

## Title: Install Growl? ##
### [SurfWriter icon](.md) SurfWriter wants to use Growl [Growl icon](.md) ###

You do not currently have Growl installed.

Growl is a free program that some applications, such as SurfWriter, can use to notify you when things happen.

This is what a Growl notification looks like.

[Screenshot of the user's menu bar and desktop, with a Smoke notification dubbed in. The application could provide a custom example in its registration dictionary; if it doesn't, the notification will have a default title and description.](.md)

SurfWriter will not ask you about Growl again. You do not need to install Growl to use SurfWriter.

If you choose “Don't Install”, and you change your mind later, you can download Growl from http://growl.info/ and use its Installer package to install it. [line break](.md)
If you choose “Download and Install”, this dialog will download and install Growl for you.

Buttons:

  * Don't Install
  * Download and Install

(There is no default button. The user must click one of them, or press Escape to choose “Don't Install”. This should prevent accidental installations.)

# Other considerations #

  * The installer should check reachability to growl.info before presenting the installer prompt.
  * We may want to explore way of presenting the prompt other than a Sparkle-like dialog box on launch. A delay would be simple; more complex but possibly better would be an alternative form of dialog box that fades in at one corner of the screen instead of barging in at the center of the screen.
  * The installer should record the last time it appeared by storing a date in the global defaults domain, so as to appear the user getting buffeted by multiple prompts in a row. One prompt per day should be enough.