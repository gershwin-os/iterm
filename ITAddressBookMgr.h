/*
 **  ITAddressBookMgr.h
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: keeps track of the address book data.
 **
 **  This program is free software; you can redistribute it and/or modify
 **  it under the terms of the GNU General Public License as published by
 **  the Free Software Foundation; either version 2 of the License, or
 **  (at your option) any later version.
 **
 **  This program is distributed in the hope that it will be useful,
 **  but WITHOUT ANY WARRANTY; without even the implied warranty of
 **  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 **  GNU General Public License for more details.
 **
 **  You should have received a copy of the GNU General Public License
 **  along with this program; if not, write to the Free Software
 **  Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.
 */

#import <Foundation/Foundation.h>

#define KEY_CHILDREN					@"Children"
#define KEY_NAME						@"Name"
#define KEY_DESCRIPTION					@"Description"
#define KEY_COMMAND						@"Command"
#define KEY_WORKING_DIRECTORY			@"Working Directory"
#define KEY_TERMINAL_PROFILE			@"Terminal Profile"
#define KEY_KEYBOARD_PROFILE			@"Keyboard Profile"
#define KEY_DISPLAY_PROFILE				@"Display Profile"
#define KEY_SHORTCUT					@"Shortcut"
#define KEY_DEFAULT_BOOKMARK			@"Default Bookmark"
#define KEY_RENDEZVOUS_GROUP			@"Rendezvous Group"
#define KEY_RENDEZVOUS_SERVICE			@"Rendezvous Service"
#define KEY_RENDEZVOUS_SERVICE_ADDRESS  @"Rendezvous Service Address"


@class TreeNode;

@interface ITAddressBookMgr : NSObject 
{
	TreeNode *bookmarks;
	NSNetServiceBrowser *sshRendezvousBrowser;
	NSNetServiceBrowser *ftpRendezvousBrowser;
	NSNetServiceBrowser *telnetRendezvousBrowser;
	TreeNode *rendezvousGroup;
	NSMutableArray *rendezvousServices;
}

+ (id)sharedInstance;

- (void) setBookmarks: (NSDictionary *) aDict;
- (NSDictionary *) bookmarks;

- (void) migrateOldBookmarks;

// Model for NSOutlineView tree structure
- (id) child:(int)index ofItem:(id)item;
- (BOOL) isExpandable:(id)item;
- (int) numberOfChildrenOfItem:(id)item;
- (id) objectForKey: (id) key inItem: (id) item;
- (void) setObjectValue: (id) object forKey: (id) key inItem: (id) item;
- (void) addFolder: (NSString *) folderName toNode: (TreeNode *) aNode;
- (void) addBookmarkWithData: (NSDictionary *) data toNode: (TreeNode *) aNode;
- (void) setBookmarkWithData: (NSDictionary *) data forNode: (TreeNode *) aNode;
- (void) deleteBookmarkNode: (TreeNode *) aNode;
- (BOOL) mayDeleteBookmarkNode: (TreeNode *) aNode;
- (TreeNode *) rootNode;

- (NSDictionary *) defaultBookmarkData;
- (NSDictionary *) dataForBookmarkWithName: (NSString *) bookmarkName;

@end

@interface ITAddressBookMgr (Private)

- (BOOL) _checkForDefaultBookmark: (TreeNode *) rootNode defaultBookmark: (TreeNode **)defaultBookmark;
- (NSDictionary *) _getBookmarkNodeWithName: (NSString *) aName searchFromNode: (TreeNode *) aNode;
- (TreeNode *) _getRendezvousServiceTypeNode: (NSString *) aType;

@end
