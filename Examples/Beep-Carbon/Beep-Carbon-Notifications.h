/*
 *  Beep-Carbon-Notifications.h
 *  Growl
 *
 *  Created by Mac-arena the Bored Zo on Fri Jun 11 2004.
 *  Public domain.
 *
 */

#include <Carbon/Carbon.h>
#include <Growl/Growl.h>

struct CFnotification {
	CFStringRef name;
	CFStringRef title;
	CFStringRef desc;
//	CGImageRef  image;
	CFDataRef   imageData;
	int priority;
	CFMutableDictionaryRef userInfo;
	CFIndex     refCount;
	Boolean isSticky; //not part of flags so that its address can be taken for CFNumber
	struct {
		unsigned reserved  :31;
		unsigned isDefault :1;
	} flags;
};

struct CFnotification *CreateCFNotification(CFStringRef name, CFStringRef title, CFStringRef desc, int priority, CFDataRef imageData, Boolean isSticky, Boolean isDefault);
struct CFnotification *RetainCFNotification(struct CFnotification *notification);
void ReleaseCFNotification(struct CFnotification *notification);

void PostCFNotification(CFNotificationCenterRef notificationCenter, struct CFnotification *notification, Boolean deliverImmediately);

void AddCFNotificationToMasterList(struct CFnotification *notification);
void RemoveCFNotificationFromMasterList(struct CFnotification *notification);

struct CFnotification *CopyCFNotificationByIndex(CFIndex index);
void RemoveCFNotificationFromMasterListByIndex(CFIndex index);
CFIndex CountCFNotificationsInMasterList(void);

void UpdateCFNotificationUserInfoForGrowl(struct CFnotification *notification);
