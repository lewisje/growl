# Requirements list proposal for Growl 2.0 #

This is the list of items which are required for 2.0.

  * Notification Center support
  * Plugin API for action plugins with UI



# Notification Center support #

Add support for Notification Center. This makes 2.0 the 10.8 release.

# Plugin API for action plugins #

Growl 1.3.x and below only support one kind of plugin, the display plugin. Multiple other application developers have created plugins that are actually actions, and put them into the displays. We also have multiple action plugins.

This task is for creating an API and presenting a UI for it in Growl which is easy to understand. The API likely comes in 1.4, without being exposed in the UI. 2.0 will introduce the UI for this.

Main starting targets for the API are Boxcar and Prowl. Defining their needs for the API and then working with them on it will produce a better end result.