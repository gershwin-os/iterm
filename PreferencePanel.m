// $Id: PreferencePanel.m,v 1.83 2004-03-08 08:56:27 ujwal Exp $
/*
 **  PreferencePanel.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Sathyam
 **
 **  Project: iTerm
 **
 **  Description: Implements the model and controller for the preference panel.
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

#import <iTerm/PreferencePanel.h>
#import <iTerm/NSStringITerm.h>
#import <iTerm/AddressBookWindowController.h>
#import <iTerm/iTermController.h>
#import <iTerm/ITAddressBookMgr.h>
#import <iTerm/iTermKeyBindingMgr.h>


static float versionNumber;

@implementation PreferencePanel

+ (PreferencePanel*)sharedInstance;
{
    static PreferencePanel* shared = nil;
    
    if (!shared)
	{
		shared = [[self alloc] initWithWindowNibName: @"PreferencePanel"];
        [shared window]; // force the window to load now
	}
    
    return shared;
}

- (id)initWithWindowNibName: (NSString *) windowNibName
{
    unsigned int storedMajorVersion = 0, storedMinorVersion = 0, storedMicroVersion = 0;
#if DEBUG_OBJALLOC
    NSLog(@"%s(%d):-[PreferencePanel init]", __FILE__, __LINE__);
#endif
    if ((self = [super init]) == nil)
        return nil;
	
	[super initWithWindowNibName: windowNibName];
    
    [self readPreferences];
    
    // get the version
    NSDictionary *myDict = [[NSBundle bundleForClass:[self class]] infoDictionary];
    versionNumber = [(NSNumber *)[myDict objectForKey:@"CFBundleVersion"] floatValue];
    if([prefs objectForKey: @"iTerm Version"])
    {
	sscanf([[prefs objectForKey: @"iTerm Version"] cString], "%d.%d.%d", &storedMajorVersion, &storedMinorVersion, &storedMicroVersion);
	// briefly, version 0.7.0 was stored as 0.70
	if(storedMajorVersion == 0 && storedMinorVersion == 70)
	    storedMinorVersion = 7;
    }
    //NSLog(@"Stored version = %d.%d.%d", storedMajorVersion, storedMinorVersion, storedMicroVersion);
        

    // sync the version number
    [prefs setObject: [myDict objectForKey:@"CFBundleVersion"] forKey: @"iTerm Version"];
                 
    return self;
}

- (void)dealloc
{
    [super dealloc];
}

- (void) readPreferences
{
    prefs = [NSUserDefaults standardUserDefaults];

    defaultAntiAlias=[prefs objectForKey:@"AntiAlias"]?[[prefs objectForKey:@"AntiAlias"] boolValue]: YES;
        
    defaultTabViewType=[prefs objectForKey:@"TabViewType"]?[prefs integerForKey:@"TabViewType"]:0;
    defaultCopySelection=[[prefs objectForKey:@"CopySelection"] boolValue];
    defaultHideTab=[prefs objectForKey:@"HideTab"]?[[prefs objectForKey:@"HideTab"] boolValue]: YES;
    defaultSilenceBell=[[prefs objectForKey:@"SilenceBell"] boolValue];
    defaultOpenAddressBook = [prefs objectForKey:@"OpenAddressBook"]?[[prefs objectForKey:@"OpenAddressBook"] boolValue]: NO;
    defaultPromptOnClose = [prefs objectForKey:@"PromptOnClose"]?[[prefs objectForKey:@"PromptOnClose"] boolValue]: YES;
    defaultBlinkingCursor = [prefs objectForKey:@"BlinkingCursor"]?[[prefs objectForKey:@"BlinkingCursor"] boolValue]: NO;
    defaultFocusFollowsMouse = [prefs objectForKey:@"FocusFollowsMouse"]?[[prefs objectForKey:@"FocusFollowsMouse"] boolValue]: NO;
	
	[[iTermKeyBindingMgr singleInstance] setProfiles: [prefs objectForKey: @"KeyBindings"]];
}

- (void)run
{
	NSEnumerator *kbProfileEnumerator;
	NSString *aString;
	NSString *selectedKBProfile;
	
    [antiAlias setState:defaultAntiAlias?NSOnState:NSOffState];
    
	selectedKBProfile = [kbProfileSelector titleOfSelectedItem];
    [optionKey selectCellAtRow:0 column:[[iTermKeyBindingMgr singleInstance] optionKeyForProfile: selectedKBProfile]];
    [tabPosition selectCellWithTag: defaultTabViewType];
    [selectionCopiesText setState:defaultCopySelection?NSOnState:NSOffState];
    [hideTab setState:defaultHideTab?NSOnState:NSOffState];
    [silenceBell setState:defaultSilenceBell?NSOnState:NSOffState];
    [openAddressBook setState:defaultOpenAddressBook?NSOnState:NSOffState];
    [promptOnClose setState:defaultPromptOnClose?NSOnState:NSOffState];
    [blinkingCursor setState: defaultBlinkingCursor?NSOnState:NSOffState];
	[focusFollowsMouse setState: defaultFocusFollowsMouse?NSOnState:NSOffState];
	[wordChars setStringValue: [prefs objectForKey: @"WordCharacters"]?[prefs objectForKey: @"WordCharacters"]:@""];
	
	[kbProfileSelector removeAllItems];
	kbProfileEnumerator = [[[iTermKeyBindingMgr singleInstance] profiles] keyEnumerator];
	while((aString = [kbProfileEnumerator nextObject]) != nil)
		[kbProfileSelector addItemWithTitle: aString];
	
	[self kbProfileChanged: nil];
	[self tableViewSelectionDidChange: nil];
    
	[[self window] setDelegate: self];
	[self showWindow: self];
	
}

- (IBAction)cancel:(id)sender
{
    [self readPreferences];
	[[self window] close];
}

- (IBAction)ok:(id)sender
{    
    defaultAntiAlias = ([antiAlias state]==NSOnState);

    defaultTabViewType=[[tabPosition selectedCell] tag];
    defaultCopySelection=([selectionCopiesText state]==NSOnState);
    defaultHideTab=([hideTab state]==NSOnState);
    defaultSilenceBell=([silenceBell state]==NSOnState);
    defaultOpenAddressBook = ([openAddressBook state] == NSOnState);
    defaultPromptOnClose = ([promptOnClose state] == NSOnState);
    defaultBlinkingCursor = ([blinkingCursor state] == NSOnState);
    defaultFocusFollowsMouse = ([focusFollowsMouse state] == NSOnState);

    [prefs setBool:defaultAntiAlias forKey:@"AntiAlias"];
    [prefs setBool:defaultCopySelection forKey:@"CopySelection"];
    [prefs setBool:defaultHideTab forKey:@"HideTab"];
    [prefs setBool:defaultSilenceBell forKey:@"SilenceBell"];
    [prefs setInteger:defaultTabViewType forKey:@"TabViewType"];
    [prefs setBool:defaultOpenAddressBook forKey:@"OpenAddressBook"];
    [prefs setBool:defaultPromptOnClose forKey:@"PromptOnClose"];
    [prefs setBool:defaultBlinkingCursor forKey:@"BlinkingCursor"];
    [prefs setBool:defaultFocusFollowsMouse forKey:@"FocusFollowsMouse"];
	[prefs setObject: [wordChars stringValue] forKey: @"WordCharacters"];
	[[iTermKeyBindingMgr singleInstance] setOptionKey: [optionKey selectedColumn] 
										   forProfile: [kbProfileSelector titleOfSelectedItem]];
	[prefs setObject: [[iTermKeyBindingMgr singleInstance] profiles] forKey: @"KeyBindings"];
    
    [[self window] close];
}

- (IBAction)restore:(id)sender
{    
    defaultHideTab=YES;
    defaultCopySelection=YES;
    defaultSilenceBell=NO;
    defaultTabViewType = NSTopTabsBezelBorder;
    defaultOpenAddressBook = NO;
    defaultBlinkingCursor = NO;

    [selectionCopiesText setState:defaultCopySelection?NSOnState:NSOffState];
    [hideTab setState:defaultHideTab?NSOnState:NSOffState];
    [silenceBell setState:defaultSilenceBell?NSOnState:NSOffState];
    [openAddressBook setState:defaultOpenAddressBook?NSOnState:NSOffState];
    [promptOnClose setState:defaultPromptOnClose?NSOnState:NSOffState];
    [tabPosition selectCellWithTag: defaultTabViewType];
    [blinkingCursor setState:defaultBlinkingCursor?NSOnState:NSOffState];
}


// NSWindow delegate
- (void)windowWillLoad;
{
    // We finally set our autosave window frame name and restore the one from the user's defaults.
    [self setWindowFrameAutosaveName: @"Preferences"];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName: @"nonTerminalWindowBecameKey" object: nil userInfo: nil];        
}


// Keybinding stuff
- (IBAction) kbProfileChanged: (id) sender
{
	NSString *selectedKBProfile;
	//NSLog(@"%s; %@", __PRETTY_FUNCTION__, sender);
	
	selectedKBProfile = [kbProfileSelector titleOfSelectedItem];

	[kbProfileDeleteButton setEnabled: ![[iTermKeyBindingMgr singleInstance] isGlobalProfile: selectedKBProfile]];
    [optionKey selectCellAtRow:0 column:[[iTermKeyBindingMgr singleInstance] optionKeyForProfile: selectedKBProfile]];

	[kbEntryTableView reloadData];
}

- (IBAction) kbProfileAdd: (id) sender
{
	[NSApp beginSheet: addKBProfile
       modalForWindow: profilesWindow
        modalDelegate: self
       didEndSelector: @selector(_addKBProfileSheetDidEnd:returnCode:contextInfo:)
          contextInfo: nil];        
}

- (IBAction) kbProfileDelete: (id) sender
{
	[NSApp beginSheet: deleteKBProfile
       modalForWindow: profilesWindow
        modalDelegate: self
       didEndSelector: @selector(_deleteKBProfileSheetDidEnd:returnCode:contextInfo:)
          contextInfo: nil];        
}

- (IBAction) kbProfileAddConfirm: (id) sender
{
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	[NSApp endSheet:addKBProfile returnCode:NSOKButton];
}

- (IBAction) kbProfileAddCancel: (id) sender
{
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	[NSApp endSheet:addKBProfile returnCode:NSCancelButton];
}

- (IBAction) kbProfileDeleteConfirm: (id) sender
{
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	[NSApp endSheet:deleteKBProfile returnCode:NSOKButton];
}

- (IBAction) kbProfileDeleteCancel: (id) sender
{
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	[NSApp endSheet:deleteKBProfile returnCode:NSCancelButton];
}

- (IBAction) kbEntryAdd: (id) sender
{
	int i;

	//NSLog(@"%s", __PRETTY_FUNCTION__);
	[kbEntryKeyCode setStringValue: @""];
	[kbEntryText setStringValue: @""];
	[kbEntryKeyModifierOption setState: NSOffState];
	[kbEntryKeyModifierControl setState: NSOffState];
	[kbEntryKeyModifierShift setState: NSOffState];
	[kbEntryKeyModifierCommand setState: NSOffState];
	[kbEntryKeyModifierOption setEnabled: YES];
	[kbEntryKeyModifierControl setEnabled: YES];
	[kbEntryKeyModifierShift setEnabled: YES];
	[kbEntryKeyModifierCommand setEnabled: YES];
	[kbEntryKeyCode setHidden: YES];
	[kbEntryText setHidden: YES];
				
	[kbEntryKey selectItemAtIndex: 0];
	[kbEntryKey setTarget: self];
	[kbEntryKey setAction: @selector(kbEntrySelectorChanged:)];
	[kbEntryAction selectItemAtIndex: 0];
	[kbEntryAction setTarget: self];
	[kbEntryAction setAction: @selector(kbEntrySelectorChanged:)];
	
	
	
	if([[iTermKeyBindingMgr singleInstance] isGlobalProfile: [kbProfileSelector titleOfSelectedItem]])
	{
		for (i = KEY_ACTION_NEXT_SESSION; i < KEY_ACTION_ESCAPE_SEQUENCE; i++)
		{
			[[kbEntryAction itemAtIndex: i] setEnabled: YES];
			[[kbEntryAction itemAtIndex: i] setAction: @selector(kbEntrySelectorChanged:)];
			[[kbEntryAction itemAtIndex: i] setTarget: self];
		}
	}
	else
	{
		for (i = KEY_ACTION_NEXT_SESSION; i < KEY_ACTION_ESCAPE_SEQUENCE; i++)
		{
			[[kbEntryAction itemAtIndex: i] setEnabled: NO];
			[[kbEntryAction itemAtIndex: i] setAction: nil];
		}
		[kbEntryAction selectItemAtIndex: KEY_ACTION_ESCAPE_SEQUENCE];
	}
	
	
	
	[NSApp beginSheet: addKBEntry
       modalForWindow: profilesWindow
        modalDelegate: self
       didEndSelector: @selector(_addKBEntrySheetDidEnd:returnCode:contextInfo:)
          contextInfo: nil];        
	
}

- (IBAction) kbEntryAddConfirm: (id) sender
{
	[NSApp endSheet:addKBEntry returnCode:NSOKButton];
}

- (IBAction) kbEntryAddCancel: (id) sender
{
	[NSApp endSheet:addKBEntry returnCode:NSCancelButton];
}


- (IBAction) kbEntryDelete: (id) sender
{
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	if([kbEntryTableView selectedRow] >= 0)
	{
		[[iTermKeyBindingMgr singleInstance] deleteEntryAtIndex: [kbEntryTableView selectedRow] 
													  inProfile: [kbProfileSelector titleOfSelectedItem]];
		[kbEntryTableView reloadData];
	}
	else
		NSBeep();
}

- (IBAction) kbEntrySelectorChanged: (id) sender
{
	if(sender == kbEntryKey)
	{
		if([kbEntryKey indexOfSelectedItem] == KEY_HEX_CODE)
		{			
			[kbEntryKeyCode setHidden: NO];
		}
		else
		{			
			[kbEntryKeyCode setStringValue: @""];
			[kbEntryKeyCode setHidden: YES];
		}
	}
	else if(sender == kbEntryAction)
	{
		if([kbEntryAction indexOfSelectedItem] == KEY_ACTION_HEX_CODE ||
		   [kbEntryAction indexOfSelectedItem] == KEY_ACTION_ESCAPE_SEQUENCE)
		{			
			[kbEntryText setHidden: NO];
		}
		else
		{
			[kbEntryText setStringValue: @""];
			[kbEntryText setHidden: YES];
		}
	}	
}

// NSTableView data source
- (int) numberOfRowsInTableView: (NSTableView *)aTableView
{
	if([kbProfileSelector numberOfItems] == 0)
		return (0);
		
	return ([[iTermKeyBindingMgr singleInstance] numberOfEntriesInProfile: [kbProfileSelector titleOfSelectedItem]]);
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	if([[aTableColumn identifier] intValue] ==  0)
	{
		return ([[iTermKeyBindingMgr singleInstance] keyCombinationAtIndex: rowIndex 
																 inProfile: [kbProfileSelector titleOfSelectedItem]]);
	}
	else
	{
		return ([[iTermKeyBindingMgr singleInstance] actionForKeyCombinationAtIndex: rowIndex 
																 inProfile: [kbProfileSelector titleOfSelectedItem]]);
	}
}

// NSTableView delegate
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if([kbEntryTableView selectedRow] < 0)
		[kbEntryDeleteButton setEnabled: NO];
	else
		[kbEntryDeleteButton setEnabled: YES];
}


// accessors for preferences
- (BOOL) antiAlias
{
    return defaultAntiAlias;
}


- (BOOL) copySelection
{
    return (defaultCopySelection);
}

- (void) setCopySelection: (BOOL) flag
{
	defaultCopySelection = flag;
}

- (BOOL) hideTab
{
    return (defaultHideTab);
}

- (BOOL) silenceBell
{
    return (defaultSilenceBell);
}

- (void) setTabViewType: (NSTabViewType) type
{
    defaultTabViewType = type;
}

- (NSTabViewType) tabViewType
{
    return (defaultTabViewType);
}

- (BOOL)openAddressBook
{
    return (defaultOpenAddressBook);
}

- (BOOL)promptOnClose
{
    return (defaultPromptOnClose);
}

- (BOOL) blinkingCursor
{
    return (defaultBlinkingCursor);
}

- (BOOL) focusFollowsMouse
{
    return (defaultFocusFollowsMouse);
}

- (NSString *) wordChars
{
	return ([prefs objectForKey: @"WordCharacters"]);
}

- (IBAction) editDefaultSession: (id) sender
{
    AddressBookWindowController *abWindowController;

#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[iTermController showABWindow:%@]",
          __FILE__, __LINE__, sender);
#endif

    abWindowController = [AddressBookWindowController singleInstance];
    if([[abWindowController window] isVisible] == NO)
	[abWindowController setAddressBook: [[ITAddressBookMgr sharedInstance] addressBook]];
    
    [abWindowController adbEditEntryAtIndex: 0 newEntry: NO];
}

@end

@implementation PreferencePanel (Private)

- (void)_addKBEntrySheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{	
	if(returnCode == NSOKButton)
	{
		unsigned int modifiers = 0;
		unsigned int hexCode = 0;
		
		if([kbEntryKeyModifierOption state] == NSOnState)
			modifiers |= NSAlternateKeyMask;
		if([kbEntryKeyModifierControl state] == NSOnState)
			modifiers |= NSControlKeyMask;
		if([kbEntryKeyModifierShift state] == NSOnState)
			modifiers |= NSShiftKeyMask;
		if([kbEntryKeyModifierCommand state] == NSOnState)
			modifiers |= NSCommandKeyMask;

		if([kbEntryKey indexOfSelectedItem] == KEY_HEX_CODE)
		{
			if(sscanf([[kbEntryKeyCode stringValue] UTF8String], "%x", &hexCode) == 1)
			{
				[[iTermKeyBindingMgr singleInstance] addEntryForKeyCode: hexCode 
															  modifiers: modifiers 
																 action: [kbEntryAction indexOfSelectedItem] 
																   text: [kbEntryText stringValue]
																profile: [kbProfileSelector titleOfSelectedItem]];
			}
		}
		else
		{
			[[iTermKeyBindingMgr singleInstance] addEntryForKey: [kbEntryKey indexOfSelectedItem] 
													  modifiers: modifiers 
														 action: [kbEntryAction indexOfSelectedItem] 
														   text: [kbEntryText stringValue]
														profile: [kbProfileSelector titleOfSelectedItem]];			
		}
		[self kbProfileChanged: nil];
	}
	
	[addKBEntry close];
}

- (void)_addKBProfileSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if(returnCode == NSOKButton && [[kbProfileName stringValue] length] > 0)
	{
		NSEnumerator *kbProfileEnumerator;
		NSString *aString;

		[[iTermKeyBindingMgr singleInstance] addProfileWithName: [kbProfileName stringValue] 
													copyProfile: [kbProfileSelector titleOfSelectedItem]];
		
		[kbProfileSelector removeAllItems];
		kbProfileEnumerator = [[[iTermKeyBindingMgr singleInstance] profiles] keyEnumerator];
		while((aString = [kbProfileEnumerator nextObject]) != nil)
			[kbProfileSelector addItemWithTitle: aString];	
		[kbProfileSelector selectItemWithTitle: [kbProfileName stringValue]];
		[self kbProfileChanged: nil];
	}
	
	[addKBProfile close];
}

- (void)_deleteKBProfileSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	if(returnCode == NSOKButton)
	{
		NSEnumerator *kbProfileEnumerator;
		NSString *aString;
		
		[[iTermKeyBindingMgr singleInstance] deleteProfileWithName: [kbProfileSelector titleOfSelectedItem]];
		
		[kbProfileSelector removeAllItems];
		kbProfileEnumerator = [[[iTermKeyBindingMgr singleInstance] profiles] keyEnumerator];
		while((aString = [kbProfileEnumerator nextObject]) != nil)
			[kbProfileSelector addItemWithTitle: aString];
		if([kbProfileSelector numberOfItems] > 0)
			[kbProfileSelector selectItemAtIndex: 0];
		[self kbProfileChanged: nil];
	}
		
	[deleteKBProfile close];
}


@end
