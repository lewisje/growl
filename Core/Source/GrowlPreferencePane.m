//
//  GrowlPreferencePane.m
//  Growl
//
//  Created by Karl Adam on Wed Apr 21 2004.
//  Copyright 2004-2006 The Growl Project. All rights reserved.
//
// This file is under the BSD License, refer to License.txt for details

#import "GrowlPreferencePane.h"
#import "GrowlPreferencesController.h"
#import "GrowlDefinesInternal.h"
#import "GrowlDefines.h"
#import "GrowlTicketController.h"
#import "GrowlApplicationTicket.h"
#import "GrowlPlugin.h"
#import "GrowlPluginController.h"
#import "GrowlNotificationDatabase.h"
#import "GrowlProcessUtilities.h"
#import "GrowlBrowserEntry.h"
#import "NSStringAdditions.h"
#import "TicketsArrayController.h"
#import "ACImageAndTextCell.h"

#import "GrowlPrefsViewController.h"
#import "GrowlGeneralViewController.h"
#import "GrowlApplicationsViewController.h"
#import "GrowlDisplaysViewController.h"
#import "GrowlAboutViewController.h"

#import <ApplicationServices/ApplicationServices.h>
#include <SystemConfiguration/SystemConfiguration.h>
#include "GrowlPositionPicker.h"
#include <ifaddrs.h>
#include <arpa/inet.h>

#include <Security/SecKeychain.h>
#include <Security/SecKeychainItem.h>

#include <Carbon/Carbon.h>

#define GeneralPrefs       @"GeneralPrefs"
#define ApplicationPrefs   @"ApplicationPrefs"
#define DisplayPrefs       @"DisplayPrefs"
#define NetworkPrefs       @"NetworkPrefs"
#define HistoryPrefs       @"HistoryPrefs"
#define AboutPane          @"About"

/** A reference to the SystemConfiguration dynamic store. */
static SCDynamicStoreRef dynStore;

/** Our run loop source for notification. */
static CFRunLoopSourceRef rlSrc;

static void scCallback(SCDynamicStoreRef store, CFArrayRef changedKeys, void *info);

@interface GrowlPreferencePane (PRIVATE)

- (void) populateDisplaysPopUpButton:(NSPopUpButton *)popUp nameOfSelectedDisplay:(NSString *)nameOfSelectedDisplay includeDefaultMenuItem:(BOOL)includeDefault;

@end

@implementation GrowlPreferencePane
@synthesize services;
@synthesize networkAddressString;

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
   if (rlSrc)
		CFRunLoopRemoveSource(CFRunLoopGetCurrent(), rlSrc, kCFRunLoopDefaultMode);
   if (dynStore)
		CFRelease(dynStore);
	[browser         release];
	[services        release];
	[super dealloc];
}

- (void) awakeFromNib {
    
    [self.window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
    
    preferencesController = [GrowlPreferencesController sharedController];
    
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self selector:@selector(reloadPrefs:)     name:GrowlPreferencesChanged object:nil];
    
    NSURL *fileURL = [[NSBundle mainBundle] URLForResource:@"GrowlDefaults" withExtension:@"plist"];
    NSDictionary *defaultDefaults = [NSDictionary dictionaryWithContentsOfURL:fileURL];
    if (defaultDefaults) {
        [preferencesController registerDefaults:defaultDefaults];
    }

	ACImageAndTextCell *imageTextCell = [[[ACImageAndTextCell alloc] init] autorelease];

	// create a deep mutable copy of the forward destinations
	NSArray *destinations = [preferencesController objectForKey:GrowlForwardDestinationsKey];
	NSMutableArray *theServices = [NSMutableArray array];
	for(NSDictionary *destination in destinations) {
		GrowlBrowserEntry *entry = [[GrowlBrowserEntry alloc] initWithDictionary:destination];
		[entry setOwner:self];
		[theServices addObject:entry];
		[entry release];
	}
	[self setServices:theServices];
    
   self.networkAddressString = nil;
   
   SCDynamicStoreContext context = {0, self, NULL, NULL, NULL};
   
	dynStore = SCDynamicStoreCreate(kCFAllocatorDefault,
                                   CFBundleGetIdentifier(CFBundleGetMainBundle()),
                                   scCallback,
                                   &context);
	if (!dynStore) {
		NSLog(@"SCDynamicStoreCreate() failed: %s", SCErrorString(SCError()));
	}
   
   const CFStringRef keys[1] = {
		CFSTR("State:/Network/Interface/*"),
	};
	CFArrayRef watchedKeys = CFArrayCreate(kCFAllocatorDefault,
                                          (const void **)keys,
                                          1,
                                          &kCFTypeArrayCallBacks);
	if (!SCDynamicStoreSetNotificationKeys(dynStore,
                                          NULL,
                                          watchedKeys)) {
		NSLog(@"SCDynamicStoreSetNotificationKeys() failed: %s", SCErrorString(SCError()));
		CFRelease(dynStore);
		dynStore = NULL;
	}
	CFRelease(watchedKeys);
   
   rlSrc = SCDynamicStoreCreateRunLoopSource(kCFAllocatorDefault, dynStore, 0);
	CFRunLoopAddSource(CFRunLoopGetCurrent(), rlSrc, kCFRunLoopDefaultMode);
   CFRelease(rlSrc);
   
    [historyTable setAutosaveName:@"GrowlPrefsHistoryTable"];
    [historyTable setAutosaveTableColumns:YES];
    
    [serviceNameColumn setDataCell:imageTextCell];
	[networkTableView reloadData];
	    
    GrowlNotificationDatabase *db = [GrowlNotificationDatabase sharedInstance];
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(growlDatabaseDidUpdate:) 
                                                 name:@"GrowlDatabaseUpdated" 
                                               object:db];
       
    [self reloadPreferences:nil];

}

- (void)showWindow:(id)sender
{
    //if we're visible but not on the active space then go ahead and close the window
    if ([self.window isVisible] && ![self.window isOnActiveSpace])
        [self.window orderOut:self];
        
    //we change the collection behavior so that the window is brought over to the active space
    //instead of restoring its position on its previous home. If we don't perform a collection
    //behavior reset the window will cause us to space jump.
    [self.window setCollectionBehavior: NSWindowCollectionBehaviorCanJoinAllSpaces];
    [super showWindow:sender];
    [self.window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace];
   
    if([preferencesController selectedPreferenceTab] == 3)
      [self startBrowsing];
}

- (void)windowWillClose:(NSNotification *)notification
{
   [self stopBrowsing];
}


#pragma mark -

/*!
 * @brief Returns the bundle version of the Growl.prefPane bundle.
 */
- (NSString *) bundleVersion {
	return [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey];
}


/*!
 * @brief Called when a GrowlPreferencesChanged notification is received.
 */
- (void) reloadPrefs:(NSNotification *)notification {
	// ignore notifications which are sent by ourselves
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
   
   [self reloadPreferences:[notification object]];
	
	[pool release];
}

/*!
 * @brief Reloads the preferences and updates the GUI accordingly.
 */
- (void) reloadPreferences:(NSString *)object {
   if(!object || [object isEqualToString:GrowlHistoryLogEnabled]){
      if([preferencesController isGrowlHistoryLogEnabled])
         [historyOnOffSwitch setSelectedSegment:0];
      else
         [historyOnOffSwitch setSelectedSegment:1];
   }
   
   if(!object || [object isEqualToString:GrowlStartServerKey])
      [self updateAddresses];
    
    if(!object || [object isEqualToString:GrowlSelectedPrefPane])
        [self setSelectedTab:[preferencesController selectedPreferenceTab]];

}

- (void) writeForwardDestinations {
   NSArray *currentNames = [[preferencesController objectForKey:GrowlForwardDestinationsKey] valueForKey:@"computer"];
	NSMutableArray *destinations = [[NSMutableArray alloc] initWithCapacity:[services count]];

   [services enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
      if([obj use] || [obj password] || [obj manualEntry] || [currentNames containsObject:[obj computerName]])
         [destinations addObject:[obj properties]];
   }];
	[preferencesController setObject:destinations forKey:GrowlForwardDestinationsKey];
	[destinations release];
}

#pragma mark -
#pragma mark Bindings accessors (not for programmatic use)

- (GrowlTicketController *) ticketController {
   if(!ticketController)
      ticketController = [GrowlTicketController sharedController];
   return ticketController;
}
- (GrowlPluginController *) pluginController {
	if (!pluginController)
		pluginController = [GrowlPluginController sharedController];

	return pluginController;
}
- (GrowlPreferencesController *) preferencesController {
	if (!preferencesController)
		preferencesController = [GrowlPreferencesController sharedController];

	return preferencesController;
}

- (GrowlNotificationDatabase *) historyController {
   if(!historyController)
      historyController = [GrowlNotificationDatabase sharedInstance];
   
   return historyController;
}


#pragma mark Toolbar support

-(void)setSelectedTab:(NSUInteger)tab
{
    [toolbar setSelectedItemIdentifier:[NSString stringWithFormat:@"%lu", tab]];
   
    if(tab == 3){
       [self startBrowsing];
    }else{
       [self stopBrowsing];
    }
   
   NSString *newTab = nil;
   Class newClass = [GrowlPrefsViewController class];
   switch (tab) {
      case 0:
         newTab = GeneralPrefs;
         newClass = [GrowlGeneralViewController class];
         break;
      case 1:
         newTab = ApplicationPrefs;
         newClass = [GrowlApplicationsViewController class];
         break;
      case 2:
         newTab = DisplayPrefs;
         newClass = [GrowlDisplaysViewController class];
         break;
      case 3:
         newTab = NetworkPrefs;
         break;
      case 4:
         newTab = HistoryPrefs;
         break;
      case 5:
         newTab = AboutPane;
         newClass = [GrowlAboutViewController class];
         break;
      default:
         newTab = GeneralPrefs;
         NSLog(@"Attempt to view unknown tab");
         break;
   }
   
   if(!prefViewControllers)
      prefViewControllers = [[NSMutableDictionary alloc] init];
   
   GrowlPrefsViewController *nextController = [prefViewControllers valueForKey:newTab];
   if(!nextController){
      nextController = [[newClass alloc] initWithNibName:newTab
                                                  bundle:nil 
                                             forPrefPane:self];
      [prefViewControllers setValue:nextController forKey:newTab];
      [nextController release];
   }
   
   NSWindow *aWindow = [self window];
   NSRect newFrameRect = [aWindow frameRectForContentRect:[[nextController view] frame]];
   NSRect oldFrameRect = [aWindow frame];
   
   NSSize newSize = newFrameRect.size;
   NSSize oldSize = oldFrameRect.size;
   
   NSRect frame = [aWindow frame];
   frame.size = newSize;
   frame.origin.y -= (newSize.height - oldSize.height);
   
   [aWindow setContentView:[nextController view]];
   [aWindow setFrame:frame display:YES animate:YES];
}

-(IBAction)selectedTabChanged:(id)sender
{
    [preferencesController setSelectedPreferenceTab:[[sender itemIdentifier] integerValue]];
}

-(BOOL)validateToolbarItem:(NSToolbarItem *)theItem
{
    return [[toolbar visibleItems] containsObject:theItem];
}

-(NSArray*)toolbarSelectableItems:(NSToolbar*)theToolbar
{
    return [toolbar visibleItems];
}

#pragma mark Network Tab Methods

- (IBAction) removeSelectedForwardDestination:(id)sender
{
   GrowlBrowserEntry *toRemove = [services objectAtIndex:[networkTableView selectedRow]];
   [networkTableView noteNumberOfRowsChanged];
   [self willChangeValueForKey:@"services"];
   [services removeObjectAtIndex:[networkTableView selectedRow]];
   [self didChangeValueForKey:@"services"];
   [self writeForwardDestinations];
   
   if(![toRemove password])
      return;

   OSStatus status;
	SecKeychainItemRef itemRef = nil;
	const char *uuidChars = [[toRemove uuid] UTF8String];
	status = SecKeychainFindGenericPassword(NULL,
                                           (UInt32)strlen("GrowlOutgoingNetworkConnection"), "GrowlOutgoingNetworkConnection",
                                           (UInt32)strlen(uuidChars), uuidChars,
                                           NULL, NULL, &itemRef);
   if (status == errSecItemNotFound) {
      // Do nothing, we cant find it
	} else {
		status = SecKeychainItemDelete(itemRef);
      if(status != errSecSuccess)
         NSLog(@"Error deleting the password for %@: %@", [toRemove computerName], [(NSString*)SecCopyErrorMessageString(status, NULL) autorelease]);
      if(itemRef)
         CFRelease(itemRef);
    }
}

- (IBAction)newManualForwader:(id)sender {
    GrowlBrowserEntry *newEntry = [[[GrowlBrowserEntry alloc] initWithComputerName:@""] autorelease];
    [newEntry setManualEntry:YES];
    [newEntry setOwner:self];
    [networkTableView noteNumberOfRowsChanged];
    [self willChangeValueForKey:@"services"];
    [services addObject:newEntry];
    [self didChangeValueForKey:@"services"];
}

-(void)startBrowsing
{
   if(!browser){
      browser = [[NSNetServiceBrowser alloc] init];
      [browser setDelegate:self];
      [browser searchForServicesOfType:@"_gntp._tcp." inDomain:@""];
   }
}

-(void)stopBrowsing
{
   if(browser){
      [browser stop];
      //Will release in stoppedBrowsing delegate
   }
}

-(void)updateAddresses
{
   if(![preferencesController isGrowlServerEnabled]){
      self.networkAddressString = nil;
      return;
   }
   NSMutableString *newString = nil;
   struct ifaddrs *interfaces = NULL;
   struct ifaddrs *current = NULL;
   
   if(getifaddrs(&interfaces) == 0)
   {
      current = interfaces;
      while (current != NULL) {
         NSString *currentString = nil;
         
         NSString *interface = [NSString stringWithUTF8String:current->ifa_name];
         
         if(![interface isEqualToString:@"lo0"] && ![interface isEqualToString:@"utun0"])
         {
            if (current->ifa_addr->sa_family == AF_INET) {
               char stringBuffer[INET_ADDRSTRLEN];
               struct sockaddr_in *ipv4 = (struct sockaddr_in *)current->ifa_addr;
               if (inet_ntop(AF_INET, &(ipv4->sin_addr), stringBuffer, INET_ADDRSTRLEN))
                  currentString = [NSString stringWithFormat:@"%s", stringBuffer];
            } else if (current->ifa_addr->sa_family == AF_INET6) {
               char stringBuffer[INET6_ADDRSTRLEN];
               struct sockaddr_in6 *ipv6 = (struct sockaddr_in6 *)current->ifa_addr;
               if (inet_ntop(AF_INET6, &(ipv6->sin6_addr), stringBuffer, INET6_ADDRSTRLEN))
                  currentString = [NSString stringWithFormat:@"%s", stringBuffer];
            }          
            
            if(currentString && ![currentString isLocalHost]){
               if(!newString)
                  newString = [[currentString mutableCopy] autorelease];
               else
                  [newString appendFormat:@"\n%@", currentString];
            }
         }
         
         current = current->ifa_next;
      }
   }
   if(newString){
      self.networkAddressString = newString;
      NSLog(@"new addresses %@", newString);
   }
   else
      self.networkAddressString = nil;
   
   freeifaddrs(interfaces);
}

static void scCallback(SCDynamicStoreRef store, CFArrayRef changedKeys, void *info) {
	GrowlPreferencePane *prefPane = info;
	CFIndex count = CFArrayGetCount(changedKeys);
	for (CFIndex i=0; i<count; ++i) {
		CFStringRef key = CFArrayGetValueAtIndex(changedKeys, i);
      if (CFStringCompare(key, CFSTR("State:/Network/Interface"), 0) == kCFCompareEqualTo) {
			[prefPane updateAddresses];
		}
	}
}

#pragma mark TableView data source methods

- (NSInteger) numberOfRowsInTableView:(NSTableView*)tableView {
	if(tableView == networkTableView) {
		return [[self services] count];
	}
	return 0;
}

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
	if(aTableColumn == servicePasswordColumn) {
		[[services objectAtIndex:rowIndex] setPassword:anObject];
	}

}

- (id) tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
	// we check to make sure we have the image + text column and then set its image manually
   if (aTableColumn == servicePasswordColumn) {
		return [[services objectAtIndex:rowIndex] password];
	} else if (aTableColumn == serviceNameColumn) {
        NSCell *cell = [aTableColumn dataCellForRow:rowIndex];
        static NSImage *manualImage = nil;
        static NSImage *bonjourImage = nil;
        if(!manualImage){
            manualImage = [[NSImage imageNamed:NSImageNameNetwork] retain];
            bonjourImage = [[NSImage imageNamed:NSImageNameBonjour] retain];
            NSSize imageSize = NSMakeSize([cell cellSize].height, [cell cellSize].height);
            [manualImage setSize:imageSize];
            [bonjourImage setSize:imageSize];
        }
        GrowlBrowserEntry *entry = [services objectAtIndex:rowIndex];
        if([entry manualEntry])
            [cell setImage:manualImage];
        else
            [cell setImage:bonjourImage];
    }

	return nil;
}


#pragma mark NSNetServiceBrowser Delegate Methods

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)netServiceBrowser
{
   //We switched away from the network pane, remove any unused services which are not already in the file
   NSArray *destinationNames = [[preferencesController objectForKey:GrowlForwardDestinationsKey] valueForKey:@"computer"];
   NSMutableArray *toRemove = [NSMutableArray array];
   [services enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
      if(![obj use] && ![obj password] && ![obj manualEntry] && ![destinationNames containsObject:[obj computerName]])
         [toRemove addObject:obj];
   }];
   [self willChangeValueForKey:@"services"];
   [services removeObjectsInArray:toRemove];
   [self didChangeValueForKey:@"services"];
   
   /* Now we can get rid of the browser, otherwise we don't get this delegate call, 
    * and possibly, something behind the scenes might not like releasing earlier*/
   [browser release];
    browser = nil;
}

- (void) netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didFindService:(NSNetService *)aNetService moreComing:(BOOL)moreComing {
	// check if a computer with this name has already been added
	NSString *name = [aNetService name];
	GrowlBrowserEntry *entry = nil;
	for (entry in services) {
		if ([[entry computerName] caseInsensitiveCompare:name] == NSOrderedSame) {
			[entry setActive:YES];
			return;
		}
	}

	// don't add the local machine    
    if([name isLocalHost])
        return;

	// add a new entry at the end
	entry = [[GrowlBrowserEntry alloc] initWithComputerName:name];
    [entry setDomain:[aNetService domain]];
    [entry setOwner:self];
    
	[self willChangeValueForKey:@"services"];
	[services addObject:entry];
	[self didChangeValueForKey:@"services"];
	[entry release];

	if (!moreComing)
		[self writeForwardDestinations];
}

- (void) netServiceBrowser:(NSNetServiceBrowser *)aNetServiceBrowser didRemoveService:(NSNetService *)aNetService moreComing:(BOOL)moreComing 
{
   NSArray *destinationNames = [[preferencesController objectForKey:GrowlForwardDestinationsKey] valueForKey:@"computer"];
	GrowlBrowserEntry *toRemove = nil;
	NSString *name = [aNetService name];
	for (GrowlBrowserEntry *currentEntry in services) {
		if ([[currentEntry computerName] isEqualToString:name]) {
			[currentEntry setActive:NO];
         [networkTableView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:[services indexOfObject:currentEntry]] 
                                     columnIndexes:[NSIndexSet indexSetWithIndex:1]];
         
         /* If we dont need this one anymore, get rid of it */
         if(!currentEntry.use && !currentEntry.password && ![destinationNames containsObject:currentEntry.computerName])
            toRemove = currentEntry;
			break;
		}
	}
   
   if(toRemove){
      [self willChangeValueForKey:@"services"];
      [services removeObject:toRemove];
      [self didChangeValueForKey:@"services"];
   }

	if (!moreComing)
		[self writeForwardDestinations];
}

#pragma mark Display pop-up menus

//Empties the pop-up menu and fills it out with a menu item for each display, optionally including a special menu item for the default display, selecting the menu item whose name is nameOfSelectedDisplay.
- (void) populateDisplaysPopUpButton:(NSPopUpButton *)popUp nameOfSelectedDisplay:(NSString *)nameOfSelectedDisplay includeDefaultMenuItem:(BOOL)includeDefault {
	NSMenu *menu = [popUp menu];
	NSString *nameOfDisplay = nil, *displayNameOfDisplay;

	NSMenuItem *selectedItem = nil;

	[popUp removeAllItems];

	if (includeDefault) {
		displayNameOfDisplay = NSLocalizedStringFromTableInBundle(@"Default", nil, [NSBundle bundleForClass:[self class]], /*comment*/ @"Title of menu item for default display");
		NSMenuItem *item = [menu addItemWithTitle:displayNameOfDisplay
										   action:NULL
									keyEquivalent:@""];
		[item setRepresentedObject:nil];

		if (!nameOfSelectedDisplay)
			selectedItem = item;

		[menu addItem:[NSMenuItem separatorItem]];
	}

   NSArray *plugins = [[[GrowlPluginController sharedController] displayPlugins] valueForKey:GrowlPluginInfoKeyName];
	for (nameOfDisplay in [plugins sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
		displayNameOfDisplay = [[pluginController pluginDictionaryWithName:nameOfDisplay] pluginHumanReadableName];
		if (!displayNameOfDisplay)
			displayNameOfDisplay = nameOfDisplay;

		NSMenuItem *item = [menu addItemWithTitle:displayNameOfDisplay
										   action:NULL
									keyEquivalent:@""];
		[item setRepresentedObject:nameOfDisplay];

		if (nameOfSelectedDisplay && [nameOfSelectedDisplay respondsToSelector:@selector(isEqualToString:)] && [nameOfSelectedDisplay isEqualToString:nameOfDisplay])
			selectedItem = item;
	}

	[popUp selectItem:selectedItem];
}

#pragma mark HistoryTab

- (IBAction) toggleHistory:(id)sender
{
   if([(NSSegmentedControl*)sender selectedSegment] == 0){
      [preferencesController setGrowlHistoryLogEnabled:YES];
   }else{
      [preferencesController setGrowlHistoryLogEnabled:NO];
   }
}

-(void)growlDatabaseDidUpdate:(NSNotification*)notification
{
    [historyArrayController fetch:self];
}

-(IBAction)validateHistoryTrimSetting:(id)sender
{
   if([trimByDateCheck state] == NSOffState && [trimByCountCheck state] == NSOffState)
   {
      NSLog(@"User tried turning off both automatic trim options");
      NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Turning off both automatic trim functions is not allowed.", nil)
                                       defaultButton:NSLocalizedString(@"Ok", nil)
                                     alternateButton:nil
                                         otherButton:nil
                           informativeTextWithFormat:NSLocalizedString(@"To prevent the history database from growing indefinitely, at least one type of automatic trim must be active", nil)];
      [alert runModal];
      if ([sender isEqualTo:trimByDateCheck]) {
         [preferencesController setGrowlHistoryTrimByDate:YES];
      }
      
      if([sender isEqualTo:trimByCountCheck]){
         [preferencesController setGrowlHistoryTrimByCount:YES];
      }
   }
}

- (IBAction) deleteSelectedHistoryItems:(id)sender
{
   [[GrowlNotificationDatabase sharedInstance] deleteSelectedObjects:[historyArrayController selectedObjects]];
}

- (IBAction) clearAllHistory:(id)sender
{
   NSAlert *alert = [NSAlert alertWithMessageText:NSLocalizedString(@"Warning! About to delete ALL history", nil)
                                    defaultButton:NSLocalizedString(@"Cancel", nil)
                                  alternateButton:NSLocalizedString(@"Ok", nil)
                                      otherButton:nil
                        informativeTextWithFormat:NSLocalizedString(@"This action cannot be undone, please confirm that you want to delete the entire notification history", nil)];
   [alert beginSheetModalForWindow:[sender window]
                     modalDelegate:self
                    didEndSelector:@selector(clearAllHistoryAlert:didReturn:contextInfo:)
                       contextInfo:nil];
}

- (IBAction) clearAllHistoryAlert:(NSAlert*)alert didReturn:(NSInteger)returnCode contextInfo:(void*)contextInfo
{
   switch (returnCode) {
      case NSAlertDefaultReturn:
         NSLog(@"Doing nothing");
         break;
      case NSAlertAlternateReturn:
         [[GrowlNotificationDatabase sharedInstance] deleteAllHistory];
         break;
   }
}

@end
