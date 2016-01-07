# Introduction #

Versions not listed should be assumed to have the same requirements as the previous version.

Some versions listed here may not have come out yet. They are listed here for planning purposes.

# Growl (user product) #

Note: 1.3 is the first version to be released as an application in the Mac App Store. Previous versions were self-published as a preference pane containing a hidden application.


| Version | OS X Version | Hardware Requirements |
|:--------|:-------------|:----------------------|
| 1.1     | 10.4         |
| 1.2     | 10.5         |
| 1.3     | 10.7         | 64 bit Intel Mac      |
| 2.0     | 10.7         | 64 bit Intel Mac      |

# Growl (developer framework) #

| Version | Min. OS X (not crash) | Min. OS X (notify) | Min. Growl | Uses Mist when Growl isn't running| Works with 1.3 | Sends to Notification Center on 10.8 when Growl isn't running |
|:--------|:----------------------|:-------------------|:-----------|:----------------------------------|:---------------|:--------------------------------------------------------------|
| 0.5     | ?                     | ?                  | 0.5        | No                                | No             | No                                                            |
| 1.2     | 10.5                  | 10.5               | 0.7.6      | No                                | No             | No                                                            |
| 1.2.1   | 10.5                  | 10.5               | 0.7.6      | No                                | Yes            | No                                                            |
| 1.2.2   | 10.5                  | 10.5               | 0.7.6      | No                                | Yes            | No                                                            |
| 1.2.3   | 10.5                  | 10.5               | 0.7.6      | No                                | Yes            | No                                                            |
| 1.3     | 10.6                  | 10.6               | 1.2.2      | Yes                               | Yes            | No                                                            |
| 2.0     | 10.6                  | 10.6               | 1.2.2      | Yes `*`                           | Yes            |  Yes                                                          |

`*` Uses Mist on 10.6 and 10.7, on 10.8 mist is not used and messages are sent to Notification Center

# GrowlTunes #

| Version | Min. OS X | Min. iTunes |
|:--------|:----------|:------------|
| 1.2     | 10.5      | Any         |
| 1.2.1   | 10.5      | 4.7         |
| 1.3     | 10.7      |             |