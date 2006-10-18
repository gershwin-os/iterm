/*
 **  iTermProfileWindowController.h
 **
 **  Copyright (c) 2002, 2003, 2004
 **
 **  Author: Ujwal S. Setlur
 **
 **  Project: iTerm
 **
 **  Description: window controller for profile editors.
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

#import <iTerm/iTermController.h>
#import <iTerm/iTermKeyBindingMgr.h>
#import <iTerm/iTermDisplayProfileMgr.h>
#import <iTerm/iTermTerminalProfileMgr.h>
#import <iTerm/iTermProfileWindowController.h>

@implementation iTermProfileWindowController

static NSArray *profileCategories;
static int categoryChosen;

+ (iTermProfileWindowController*)sharedInstance
{
    static iTermProfileWindowController* shared = nil;

    if (!shared)
	{
		shared = [[self alloc] init];
	}

    profileCategories = [[NSArray arrayWithObjects:[NSNumber numberWithInt: 0],[NSNumber numberWithInt: 1],[NSNumber numberWithInt: 2],nil] retain];
    categoryChosen = -1;
    return shared;
}

- (id) init
{
    NSMutableDictionary *profilesDictionary, *keybindingProfiles, *displayProfiles, *terminalProfiles;
	NSString *plistFile;
    
    if ((self = [super init]) == nil)
        return nil;

    _prefs = [NSUserDefaults standardUserDefaults];
    
    // load saved profiles or default if we don't have any
	keybindingProfiles = [_prefs objectForKey: @"KeyBindings"];
	displayProfiles =  [_prefs objectForKey: @"Displays"];
	terminalProfiles = [_prefs objectForKey: @"Terminals"];
	
	// if we got no profiles, load from our embedded plist
	plistFile = [[NSBundle bundleForClass: [self class]] pathForResource:@"Profiles" ofType:@"plist"];
	profilesDictionary = [NSDictionary dictionaryWithContentsOfFile: plistFile];
	if([keybindingProfiles count] == 0)
		keybindingProfiles = [profilesDictionary objectForKey: @"KeyBindings"];
	if([displayProfiles count] == 0)
		displayProfiles = [profilesDictionary objectForKey: @"Displays"];
	if([terminalProfiles count] == 0)
		terminalProfiles = [profilesDictionary objectForKey: @"Terminals"];
    
	[[iTermKeyBindingMgr singleInstance] setProfiles: keybindingProfiles];
	[[iTermDisplayProfileMgr singleInstance] setProfiles: displayProfiles];
	[[iTermTerminalProfileMgr singleInstance] setProfiles: terminalProfiles];
    
    selectedProfile = nil;
    return self;
}    
- (IBAction) showProfilesWindow: (id) sender
{
	NSEnumerator *anEnumerator;
	NSNumber *anEncoding;
	
    // load nib if we haven't already
    if([self window] == nil)
		[self initWithWindowNibName: @"ProfilesWindow"];
    
	[[self window] setDelegate: self]; // also forces window to load
    
	[self tableViewSelectionDidChange: nil];	
	
	
	// add list of encodings
	[terminalEncoding removeAllItems];
	anEnumerator = [[[iTermController sharedInstance] sortedEncodingList] objectEnumerator];
	while((anEncoding = [anEnumerator nextObject]) != NULL)
	{
		[terminalEncoding addItemWithTitle: [NSString localizedNameOfStringEncoding: [anEncoding unsignedIntValue]]];
		[[terminalEncoding lastItem] setTag: [anEncoding unsignedIntValue]];
	}
	
	[self showWindow: self];
}

- (void)windowDidBecomeKey:(NSNotification *)aNotification
{
    // Post a notification
    [[NSNotificationCenter defaultCenter] postNotificationName: @"nonTerminalWindowBecameKey" object: nil userInfo: nil];        
}

- (void)windowWillClose:(NSNotification *)aNotification
{
    id prefs = [NSUserDefaults standardUserDefaults];
    
    [prefs setObject: [[iTermKeyBindingMgr singleInstance] profiles] forKey: @"KeyBindings"];
	[prefs setObject: [[iTermDisplayProfileMgr singleInstance] profiles] forKey: @"Displays"];
	[prefs setObject: [[iTermTerminalProfileMgr singleInstance] profiles] forKey: @"Terminals"];
	[prefs synchronize];

	[[NSColorPanel sharedColorPanel] close];
	[[NSFontPanel sharedFontPanel] close];	
}

// Profile editing
- (IBAction) profileAdd: (id) sender
{
	categoryChosen = [sender tag] % 3;
    if ([sender tag]>2 && selectedProfile == nil) {
        return;
    }
        
	[NSApp beginSheet: addProfile
	   modalForWindow: [self window]
		modalDelegate: self
	   didEndSelector: @selector(_duplicateProfileSheetDidEnd:returnCode:contextInfo:)
		  contextInfo: nil];        
    
    // duplicate button?
    if ([sender tag]>2) {
        [profileName setStringValue: [NSString stringWithFormat:@"%@ copy", selectedProfile]];
    }
}

- (IBAction) profileDelete: (id) sender
{
	[NSApp beginSheet: deleteProfile
       modalForWindow: [self window]
        modalDelegate: self
       didEndSelector: @selector(_deleteProfileSheetDidEnd:returnCode:contextInfo:)
          contextInfo: nil];        
}

- (IBAction) profileAddConfirm: (id) sender
{
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	id profileMgr;
	
	if(categoryChosen == KEYBOARD_PROFILE_TAB)
	{
		profileMgr = [iTermKeyBindingMgr singleInstance];
	}
	else if(categoryChosen == TERMINAL_PROFILE_TAB)
	{
		profileMgr = [iTermTerminalProfileMgr singleInstance];
	}
	else if(categoryChosen == DISPLAY_PROFILE_TAB)
	{
		profileMgr = [iTermDisplayProfileMgr singleInstance];
	}
	else
		return;
    
    // make sure this profile does not already exist
    if([[profileName stringValue] length]  <= 0 || [[profileMgr profiles] objectForKey: [profileName stringValue]] != nil)
    {
        NSBeep();
        // write some warning
        NSLog(@"duplicated name");
        return;
    }
    else
        [NSApp endSheet:addProfile returnCode:NSOKButton];
}

- (IBAction) profileAddCancel: (id) sender
{
	//NSLog(@"%s", __PRETTY_FUNCTION__);

    [NSApp endSheet:addProfile returnCode:NSCancelButton];
}

- (IBAction) profileDeleteConfirm: (id) sender
{
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	[NSApp endSheet:deleteProfile returnCode:NSOKButton];
}

- (IBAction) profileDeleteCancel: (id) sender
{
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	[NSApp endSheet:deleteProfile returnCode:NSCancelButton];
}

- (IBAction) profileDuplicate: (id) sender
{
    int selectedTabViewItem;
	id profileMgr;
	
	selectedTabViewItem  = [profileTabView indexOfTabViewItem: [profileTabView selectedTabViewItem]];
	
	if(selectedTabViewItem == KEYBOARD_PROFILE_TAB)
	{
		profileMgr = [iTermKeyBindingMgr singleInstance];
	}
	else if(selectedTabViewItem == TERMINAL_PROFILE_TAB)
	{
		profileMgr = [iTermTerminalProfileMgr singleInstance];
	}
	else if(selectedTabViewItem == DISPLAY_PROFILE_TAB)
	{
		profileMgr = [iTermDisplayProfileMgr singleInstance];
	}
	else
		return;

    // find a non-duplicated name
    NSString *aString = [NSString stringWithFormat:@"%@ copy", selectedProfile];
    int i = 1;
    for(; [[profileMgr profiles] objectForKey: aString] != nil; i++)
        aString = [NSString stringWithFormat:@"%@ copy %d", selectedProfile, i];
    [profileMgr addProfileWithName: aString 
                       copyProfile: selectedProfile];
    
    [profileOutline reloadData];
    [self selectProfile:aString withInCategory: categoryChosen];
    
}


// Keybinding profile UI
- (void) kbOptionKeyChanged: (id) sender
{
	
	[[iTermKeyBindingMgr singleInstance] setOptionKey: [kbOptionKey selectedColumn] 
										   forProfile: selectedProfile];
}

- (void) kbProfileChangedTo: (NSString *) selectedKBProfile
{
	//NSLog(@"%s; %@", __PRETTY_FUNCTION__, sender);
	
	[kbProfileDeleteButton setEnabled: ![[iTermKeyBindingMgr singleInstance] isGlobalProfile: selectedKBProfile]];
    [kbOptionKey selectCellAtRow:0 column:[[iTermKeyBindingMgr singleInstance] optionKeyForProfile: selectedKBProfile]];
	
	[kbEntryTableView reloadData];
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
	if ([kbEntryKeyCode respondsToSelector: @selector(setHidden:)] == YES)
	{
		[kbEntryKeyCode setHidden: YES];
		[kbEntryText setHidden: YES];
	}
				
	[kbEntryKey selectItemAtIndex: 0];
	[kbEntryKey setTarget: self];
	[kbEntryKey setAction: @selector(kbEntrySelectorChanged:)];
	[kbEntryAction selectItemAtIndex: 0];
	[kbEntryAction setTarget: self];
	[kbEntryAction setAction: @selector(kbEntrySelectorChanged:)];
	
	
	
	if([[iTermKeyBindingMgr singleInstance] isGlobalProfile: selectedProfile])
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
	
	[self kbEntrySelectorChanged: kbEntryAction];
	
	[NSApp beginSheet: addKBEntry
       modalForWindow: [self window]
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
													  inProfile: selectedProfile];
		[kbEntryTableView reloadData];
	}
	else
		NSBeep();
}

- (IBAction) kbEntrySelectorChanged: (id) sender
{
	if(sender == kbEntryKey)
	{
		if([kbEntryKey indexOfSelectedItem] == KEY_HEX_CODE && [kbEntryKeyCode respondsToSelector: @selector(setHidden:)] == YES)
		{			
			[kbEntryKeyCode setHidden: NO];
		}
		else
		{			
			[kbEntryKeyCode setStringValue: @""];
			if ([kbEntryKeyCode respondsToSelector: @selector(setHidden:)] == YES)
				[kbEntryKeyCode setHidden: YES];
		}
	}
	else if(sender == kbEntryAction)
	{
		if([kbEntryAction indexOfSelectedItem] == KEY_ACTION_HEX_CODE ||
		   [kbEntryAction indexOfSelectedItem] == KEY_ACTION_ESCAPE_SEQUENCE)
		{		
			if ([kbEntryText respondsToSelector: @selector(setHidden:)] == YES)
				[kbEntryText setHidden: NO];
		}
		else
		{
			[kbEntryText setStringValue: @""];
			if([kbEntryText respondsToSelector: @selector(setHidden:)] == YES)
				[kbEntryText setHidden: YES];
		}
	}	
}

// NSTableView data source
- (int) numberOfRowsInTableView: (NSTableView *)aTableView
{
	if([[[iTermKeyBindingMgr singleInstance] profiles] count] == 0 || selectedProfile == nil)
		return (0);

    
	return([[iTermKeyBindingMgr singleInstance] numberOfEntriesInProfile: selectedProfile]);
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
    //NSLog(@"%s: %@", __PRETTY_FUNCTION__, aTableView);
    
    if([[aTableColumn identifier] intValue] ==  0)
	{
		return ([[iTermKeyBindingMgr singleInstance] keyCombinationAtIndex: rowIndex 
																 inProfile: selectedProfile]);
	}
	else
	{
		return ([[iTermKeyBindingMgr singleInstance] actionForKeyCombinationAtIndex: rowIndex 
																		  inProfile: selectedProfile]);
	}
}

// NSTableView delegate
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
    //NSLog(@"%s", __PRETTY_FUNCTION__);

	if([kbEntryTableView selectedRow] < 0)
		[kbEntryDeleteButton setEnabled: NO];
	else
		[kbEntryDeleteButton setEnabled: YES];
}

// Display profile UI
- (void) displayProfileChangedTo: (NSString *) theProfile
{
	NSString *backgroundImagePath;
	
	// load the colors
	[displayFGColor setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_FOREGROUND_COLOR 
																  forProfile: theProfile]];
	[displayBGColor setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_BACKGROUND_COLOR 
																  forProfile: theProfile]];
	[displayBoldColor setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_BOLD_COLOR 
																  forProfile: theProfile]];
	[displaySelectionColor setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_SELECTION_COLOR 
																  forProfile: theProfile]];
	[displaySelectedTextColor setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_SELECTED_TEXT_COLOR 
																  forProfile: theProfile]];
	[displayCursorColor setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_CURSOR_COLOR 
																  forProfile: theProfile]];
	[displayCursorTextColor setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_CURSOR_TEXT_COLOR 
																  forProfile: theProfile]];
	[displayAnsi0Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_0_COLOR 
																  forProfile: theProfile]];
	[displayAnsi1Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_1_COLOR 
																  forProfile: theProfile]];
	[displayAnsi2Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_2_COLOR 
																  forProfile: theProfile]];
	[displayAnsi3Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_3_COLOR 
																  forProfile: theProfile]];
	[displayAnsi4Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_4_COLOR 
																  forProfile: theProfile]];
	[displayAnsi5Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_5_COLOR 
																  forProfile: theProfile]];
	[displayAnsi6Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_6_COLOR 
																  forProfile: theProfile]];
	[displayAnsi7Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_7_COLOR 
																  forProfile: theProfile]];
	[displayAnsi8Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_8_COLOR 
																  forProfile: theProfile]];
	[displayAnsi9Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_9_COLOR 
																  forProfile: theProfile]];
	[displayAnsi10Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_10_COLOR 
																  forProfile: theProfile]];
	[displayAnsi11Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_11_COLOR 
																  forProfile: theProfile]];
	[displayAnsi12Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_12_COLOR 
																  forProfile: theProfile]];
	[displayAnsi13Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_13_COLOR 
																  forProfile: theProfile]];
	[displayAnsi14Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_14_COLOR 
																  forProfile: theProfile]];
	[displayAnsi15Color setColor: [[iTermDisplayProfileMgr singleInstance] color: TYPE_ANSI_15_COLOR 
																  forProfile: theProfile]];
	
	// background image
	backgroundImagePath = [[iTermDisplayProfileMgr singleInstance] backgroundImageForProfile: theProfile];
	if([backgroundImagePath length] > 0)
	{
		NSImage *anImage = [[NSImage alloc] initWithContentsOfFile: backgroundImagePath];
		if(anImage != nil)
		{
			[displayBackgroundImage setImage: anImage];
			[anImage release];
			[displayUseBackgroundImage setState: NSOnState];
		}
		else
		{
			[displayBackgroundImage setImage: nil];
			[displayUseBackgroundImage setState: NSOffState];
		}
	}
	else
	{
		[displayBackgroundImage setImage: nil];
		[displayUseBackgroundImage setState: NSOffState];
	}	
				
	// transparency
	[displayTransparency setStringValue: [NSString stringWithFormat: @"%d", 
		(int)(100*[[iTermDisplayProfileMgr singleInstance] transparencyForProfile: theProfile])]];
	
	// disable bold
	[displayDisableBold setState: [[iTermDisplayProfileMgr singleInstance] disableBoldForProfile: theProfile]];
	
	// fonts
	[self _updateFontsDisplay];
	
	// anti-alias
	[displayAntiAlias setState: [[iTermDisplayProfileMgr singleInstance] windowAntiAliasForProfile: theProfile]];
	
	// window size
	[displayColTextField setStringValue: [NSString stringWithFormat: @"%d",
		[[iTermDisplayProfileMgr singleInstance] windowColumnsForProfile: theProfile]]];
	[displayRowTextField setStringValue: [NSString stringWithFormat: @"%d",
		[[iTermDisplayProfileMgr singleInstance] windowRowsForProfile: theProfile]]];
	
	[displayProfileDeleteButton setEnabled: ![[iTermDisplayProfileMgr singleInstance] isDefaultProfile: theProfile]];

	
}

- (IBAction) displaySetDisableBold: (id) sender
{
	if(sender == displayDisableBold)
	{
		[[iTermDisplayProfileMgr singleInstance] setDisableBold: [sender state] 
														 forProfile: selectedProfile];
	}
}

- (IBAction) displaySetAntiAlias: (id) sender
{
	if(sender == displayAntiAlias)
	{
		[[iTermDisplayProfileMgr singleInstance] setWindowAntiAlias: [sender state] 
												   forProfile: selectedProfile];
	}
}

- (IBAction) displayBackgroundImage: (id) sender
{
	
	if (sender == displayUseBackgroundImage)
	{
		if ([sender state] == NSOffState)
		{
			[displayBackgroundImage setImage: nil];
			[[iTermDisplayProfileMgr singleInstance] setBackgroundImage: @"" forProfile: selectedProfile];
		}
		else
			[self _chooseBackgroundImageForProfile: selectedProfile];
	}
}

- (IBAction) displayChangeColor: (id) sender
{
	
	int type;
	
	type = [sender tag];
	
	[[iTermDisplayProfileMgr singleInstance] setColor: [sender color]
											  forType: type
										   forProfile: selectedProfile];
	
	// update fonts display
	[self _updateFontsDisplay];
	
}

// sent by NSFontManager
- (void)changeFont:(id)fontManager
{
	NSFont *aFont;
	
	//NSLog(@"%s", __PRETTY_FUNCTION__);
	
	
	if(changingNAFont)
	{
		aFont = [fontManager convertFont: [displayNAFontTextField font]];
		[[iTermDisplayProfileMgr singleInstance] setWindowNAFont: aFont forProfile: selectedProfile];
	}
	else
	{
		aFont = [fontManager convertFont: [displayFontTextField font]];
		[[iTermDisplayProfileMgr singleInstance] setWindowFont: aFont forProfile: selectedProfile];
	}
	
	[self _updateFontsDisplay];
	
}


- (IBAction) displaySelectFont: (id) sender
{
	NSFont *aFont;
	NSFontPanel *aFontPanel;
	
	changingNAFont = NO;
	
	aFont = [[iTermDisplayProfileMgr singleInstance] windowFontForProfile: selectedProfile];
	
	// make sure we get the messages from the NSFontManager
    [[self window] makeFirstResponder:self];
	aFontPanel = [[NSFontManager sharedFontManager] fontPanel: YES];
	[aFontPanel setAccessoryView: displayFontAccessoryView];
    [[NSFontManager sharedFontManager] setSelectedFont:aFont isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

- (IBAction) displaySelectNAFont: (id) sender
{
	NSFont *aFont;
	NSFontPanel *aFontPanel;
	
	changingNAFont = YES;
	
	aFont = [[iTermDisplayProfileMgr singleInstance] windowNAFontForProfile: selectedProfile];
	
	// make sure we get the messages from the NSFontManager
    [[self window] makeFirstResponder:self];
	aFontPanel = [[NSFontManager sharedFontManager] fontPanel: YES];
	[aFontPanel setAccessoryView: displayFontAccessoryView];
    [[NSFontManager sharedFontManager] setSelectedFont:aFont isMultiple:NO];
    [[NSFontManager sharedFontManager] orderFrontFontPanel:self];
}

- (IBAction) displaySetFontSpacing: (id) sender
{
	
	if(sender == displayFontSpacingWidth)
		[[iTermDisplayProfileMgr singleInstance] setWindowHorizontalCharSpacing: [sender floatValue] 
																	 forProfile: selectedProfile];
	else if(sender == displayFontSpacingHeight)
		[[iTermDisplayProfileMgr singleInstance] setWindowVerticalCharSpacing: [sender floatValue]
                                                                   forProfile: selectedProfile];
    
}

// NSTextField delegate
- (void)controlTextDidChange:(NSNotification *)aNotification
{
	int iVal;
	float fVal;
	id sender;

	//NSLog(@"%s: %@", __PRETTY_FUNCTION__, [aNotification object]);

	sender = [aNotification object];

	iVal = [sender intValue];
	fVal = [sender floatValue];
	if(sender == displayColTextField)
		[[iTermDisplayProfileMgr singleInstance] setWindowColumns: iVal forProfile: selectedProfile];
	else if(sender == displayRowTextField)
		[[iTermDisplayProfileMgr singleInstance] setWindowRows: iVal forProfile: selectedProfile];
	else if(sender == displayTransparency)
		[[iTermDisplayProfileMgr singleInstance] setTransparency: fVal/100 forProfile: selectedProfile];
	else if(sender == terminalScrollback)
		[[iTermTerminalProfileMgr singleInstance] setScrollbackLines: iVal forProfile: selectedProfile];
	else if(sender == terminalIdleChar)
		[[iTermTerminalProfileMgr singleInstance] setIdleChar: iVal forProfile: selectedProfile];
}

// Terminal profile UI
- (void) terminalProfileChangedTo: (NSString *)theProfile
{
	[terminalType setStringValue: [[iTermTerminalProfileMgr singleInstance] typeForProfile: theProfile]];
	[terminalEncoding setTitle: [NSString localizedNameOfStringEncoding:
		[[iTermTerminalProfileMgr singleInstance] encodingForProfile: theProfile]]];
	[terminalScrollback setStringValue: [NSString stringWithFormat: @"%d",
		[[iTermTerminalProfileMgr singleInstance] scrollbackLinesForProfile: theProfile]]];
	[terminalSilenceBell setState: [[iTermTerminalProfileMgr singleInstance] silenceBellForProfile: theProfile]];
	[terminalShowBell setState: [[iTermTerminalProfileMgr singleInstance] showBellForProfile: theProfile]];
	[terminalEnableGrowl setState: [[iTermTerminalProfileMgr singleInstance] growlForProfile: theProfile]];
	[terminalBlink setState: [[iTermTerminalProfileMgr singleInstance] blinkCursorForProfile: theProfile]];
	[terminalCloseOnSessionEnd setState: [[iTermTerminalProfileMgr singleInstance] closeOnSessionEndForProfile: theProfile]];
	[terminalDoubleWidth setState: [[iTermTerminalProfileMgr singleInstance] doubleWidthForProfile: theProfile]];
	[terminalSendIdleChar setState: [[iTermTerminalProfileMgr singleInstance] sendIdleCharForProfile: theProfile]];
	[terminalIdleChar setStringValue: [NSString stringWithFormat: @"%d",  
		[[iTermTerminalProfileMgr singleInstance] idleCharForProfile: theProfile]]];
	[xtermMouseReporting setState: [[iTermTerminalProfileMgr singleInstance] xtermMouseReportingForProfile: theProfile]];
	
	[terminalProfileDeleteButton setEnabled: ![[iTermTerminalProfileMgr singleInstance] isDefaultProfile: theProfile]];

}

- (IBAction) terminalSetType: (id) sender
{
	[[iTermTerminalProfileMgr singleInstance] setType: [sender stringValue] 
										   forProfile: selectedProfile];
}

- (IBAction) terminalSetEncoding: (id) sender
{
	[[iTermTerminalProfileMgr singleInstance] setEncoding: [[terminalEncoding selectedItem] tag] 
											   forProfile: selectedProfile];
}

- (IBAction) terminalSetSilenceBell: (id) sender
{
	[[iTermTerminalProfileMgr singleInstance] setSilenceBell: [sender state] 
												  forProfile: selectedProfile];
}	

- (IBAction) terminalSetShowBell: (id) sender
{
	[[iTermTerminalProfileMgr singleInstance] setShowBell: [sender state] 
												  forProfile: selectedProfile];
}

- (IBAction) terminalSetEnableGrowl: (id) sender
{
	[[iTermTerminalProfileMgr singleInstance] setGrowl: [sender state] 
                                            forProfile: selectedProfile];
}	

- (IBAction) terminalSetBlink: (id) sender
{
	[[iTermTerminalProfileMgr singleInstance] setBlinkCursor: [sender state] 
												  forProfile: selectedProfile];
}	

- (IBAction) terminalSetCloseOnSessionEnd: (id) sender
{
	[[iTermTerminalProfileMgr singleInstance] setCloseOnSessionEnd: [sender state] 
														forProfile: selectedProfile];
}	

- (IBAction) terminalSetDoubleWidth: (id) sender
{
	[[iTermTerminalProfileMgr singleInstance] setDoubleWidth: [sender state] 
												  forProfile: selectedProfile];
}	

- (IBAction) terminalSetSendIdleChar: (id) sender
{
	[[iTermTerminalProfileMgr singleInstance] setSendIdleChar: [sender state] 
												   forProfile: selectedProfile];
}

- (IBAction) terminalSetXtermMouseReporting: (id) sender
{
	[[iTermTerminalProfileMgr singleInstance] setXtermMouseReporting: [sender state] 
												  forProfile: selectedProfile];
}	


//outline view
// NSOutlineView delegate methods
- (void) outlineViewSelectionDidChange: (NSNotification *) aNotification
{
	int selectedRow;
	id selectedItem;
	
    selectedRow = [profileOutline selectedRow];
	selectedItem = [profileOutline itemAtRow: selectedRow];
    if (selectedProfile) {
        selectedProfile = nil;
    }
	
    //NSLog(@"%s: (%d)%@", __PRETTY_FUNCTION__, selectedRow, selectedItem);

    if (!selectedItem || [selectedItem isKindOfClass:[NSNumber class]]) {
        // Choose the instruction tab
        [profileTabView selectTabViewItemAtIndex:3];
    }
	else {
        selectedProfile = selectedItem;
        if (selectedRow > [profileOutline rowForItem:[profileCategories objectAtIndex:DISPLAY_PROFILE_TAB]]) {
            [self displayProfileChangedTo: selectedItem];
            [profileTabView selectTabViewItemAtIndex:DISPLAY_PROFILE_TAB];
        }
        else if (selectedRow > [profileOutline rowForItem:[profileCategories objectAtIndex:TERMINAL_PROFILE_TAB]]) {
            [self terminalProfileChangedTo: selectedItem];
            [profileTabView selectTabViewItemAtIndex:TERMINAL_PROFILE_TAB];
        }
        else {
            [self kbProfileChangedTo: selectedItem];
            [profileTabView selectTabViewItemAtIndex:KEYBOARD_PROFILE_TAB];
        }
    }
}

// NSOutlineView data source methods
// required
- (id)outlineView:(NSOutlineView *)ov child:(int)index ofItem:(id)item
{
    //NSLog(@"%s: %@", __PRETTY_FUNCTION__, item);
    
    if (item) {
        id value;
        NSEnumerator *enumerator;

        switch ([item intValue]) {
            case KEYBOARD_PROFILE_TAB:
                enumerator = [[[iTermKeyBindingMgr singleInstance] profiles] keyEnumerator];
                break;
            case TERMINAL_PROFILE_TAB:
                enumerator = [[[iTermTerminalProfileMgr singleInstance] profiles] keyEnumerator];
                break;
            default:
                enumerator = [[[iTermDisplayProfileMgr singleInstance] profiles] keyEnumerator];
        }
            
        while ((value = [enumerator nextObject]) && index>0) 
            index--;
        
        return value;
    }
    else {
        return [profileCategories objectAtIndex:index];
    }
}

- (BOOL)outlineView:(NSOutlineView *)ov isItemExpandable:(id)item
{
    //NSLog(@"%s: %@", __PRETTY_FUNCTION__, item);
    return [item isKindOfClass:[NSNumber class]];
}

- (int)outlineView:(NSOutlineView *)ov numberOfChildrenOfItem:(id)item
{
    //NSLog(@"%s: ov = 0x%x; item = 0x%x; numChildren: %d", __PRETTY_FUNCTION__, ov, item);

    if (item) {
        switch ([item intValue]) {
            case KEYBOARD_PROFILE_TAB:
                return [[[iTermKeyBindingMgr singleInstance] profiles] count];
            case TERMINAL_PROFILE_TAB:
                return [[[iTermTerminalProfileMgr singleInstance] profiles] count];
        }
        return [[[iTermDisplayProfileMgr singleInstance] profiles] count];
    }
    else
        return 3;
}

- (id)outlineView:(NSOutlineView *)ov objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    //NSLog(@"%s: outlineView = 0x%x; item = %@; column= %@", __PRETTY_FUNCTION__, ov, item, [tableColumn identifier]);
	
    if ([item isKindOfClass:[NSNumber class]]) {
        switch ([item intValue]) {
            case KEYBOARD_PROFILE_TAB:
                return @"Keyboard Profiles";
            case TERMINAL_PROFILE_TAB:
                return @"Terminal Profiles";
        }
        return @"Display Profiles";
    }
    
    return item;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView shouldEditTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    return NO;
}

- (void)selectProfile:(NSString *)profile withInCategory: (int) category
{
    int i;
	
    
    i = [profileOutline rowForItem: [profileCategories objectAtIndex: category]]+1;
    for (;i<[profileOutline numberOfRows] && ![[profileOutline itemAtRow:i] isKindOfClass:[NSNumber class]];i++)
        if ([[profileOutline itemAtRow:i] isEqualToString: profile]) {
            [profileOutline selectRow:i byExtendingSelection:NO];
            [self outlineViewSelectionDidChange: nil];
            break;
        }
}

@end

@implementation iTermProfileWindowController (Private)

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
																profile: selectedProfile];
			}
		}
		else
		{
			[[iTermKeyBindingMgr singleInstance] addEntryForKey: [kbEntryKey indexOfSelectedItem] 
													  modifiers: modifiers 
														 action: [kbEntryAction indexOfSelectedItem] 
														   text: [kbEntryText stringValue]
														profile: selectedProfile];			
		}
		[self kbProfileChangedTo: selectedProfile];
	}
	
	[addKBEntry close];
}

- (void)_duplicateProfileSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	id profileMgr;
	
	if(categoryChosen == KEYBOARD_PROFILE_TAB)
	{
		profileMgr = [iTermKeyBindingMgr singleInstance];
	}
	else if(categoryChosen == TERMINAL_PROFILE_TAB)
	{
		profileMgr = [iTermTerminalProfileMgr singleInstance];
	}
	else if(categoryChosen == DISPLAY_PROFILE_TAB)
	{
		profileMgr = [iTermDisplayProfileMgr singleInstance];
	}
	else
		return;
	
	if(returnCode == NSOKButton)
	{
        [profileMgr addProfileWithName: [profileName stringValue] 
                           copyProfile: selectedProfile];
		[profileOutline reloadData];
        [self selectProfile:[profileName stringValue]  withInCategory: categoryChosen];
	}
	
	[addProfile close];
}

- (void)_addProfileSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	id profileMgr;
	
	if(categoryChosen == KEYBOARD_PROFILE_TAB)
	{
		profileMgr = [iTermKeyBindingMgr singleInstance];
	}
	else if(categoryChosen == TERMINAL_PROFILE_TAB)
	{
		profileMgr = [iTermTerminalProfileMgr singleInstance];
	}
	else if(categoryChosen == DISPLAY_PROFILE_TAB)
	{
		profileMgr = [iTermDisplayProfileMgr singleInstance];
	}
	else
		return;
	
	if(returnCode == NSOKButton)
	{
        [profileMgr addProfileWithName: [profileName stringValue] 
                           copyProfile: [profileMgr defaultProfileName]];
		[profileOutline reloadData];
        [self selectProfile:[profileName stringValue]  withInCategory: categoryChosen];
	}
	
	[addProfile close];
}

- (void)_deleteProfileSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo
{
	int selectedTabViewItem;
	id profileMgr;
	
	selectedTabViewItem  = [profileTabView indexOfTabViewItem: [profileTabView selectedTabViewItem]];
	
	if(selectedTabViewItem == KEYBOARD_PROFILE_TAB)
	{
		profileMgr = [iTermKeyBindingMgr singleInstance];
	}
	else if(selectedTabViewItem == TERMINAL_PROFILE_TAB)
	{
		profileMgr = [iTermTerminalProfileMgr singleInstance];
	}
	else if(selectedTabViewItem == DISPLAY_PROFILE_TAB)
	{
		profileMgr = [iTermDisplayProfileMgr singleInstance];
	}
	else
		return;
	
	if(returnCode == NSOKButton)
	{
		
		[profileMgr deleteProfileWithName: selectedProfile];
		
	    [profileOutline reloadData];
        [profileOutline deselectAll: nil];
    }
	
	[deleteProfile close];
}

- (void) _updateFontsDisplay
{
	float horizontalSpacing, verticalSpacing;
	
	// load the fonts
	NSString *fontName;
	NSFont *font;
	
	font = [[iTermDisplayProfileMgr singleInstance] windowFontForProfile: selectedProfile];
	if(font != nil)
	{
		fontName = [NSString stringWithFormat: @"%@ %g", [font fontName], [font pointSize]];
		[displayFontTextField setStringValue: fontName];
		[displayFontTextField setFont: font];
		[displayFontTextField setTextColor: [displayFGColor color]];
		[displayFontTextField setBackgroundColor: [displayBGColor color]];
	}
	else
	{
		fontName = @"Unknown Font";
		[displayFontTextField setStringValue: fontName];
	}
	font = [[iTermDisplayProfileMgr singleInstance] windowNAFontForProfile: selectedProfile];
	if(font != nil)
	{
		fontName = [NSString stringWithFormat: @"%@ %g", [font fontName], [font pointSize]];
		[displayNAFontTextField setStringValue: fontName];
		[displayNAFontTextField setFont: font];
		[displayNAFontTextField setTextColor: [displayFGColor color]];
		[displayNAFontTextField setBackgroundColor: [displayBGColor color]];
	}
	else
	{
		fontName = @"Unknown NA Font";
		[displayNAFontTextField setStringValue: fontName];
	}
	
	horizontalSpacing = [[iTermDisplayProfileMgr singleInstance] windowHorizontalCharSpacingForProfile: selectedProfile];
	verticalSpacing = [[iTermDisplayProfileMgr singleInstance] windowVerticalCharSpacingForProfile: selectedProfile];

	[displayFontSpacingWidth setFloatValue: horizontalSpacing];
	[displayFontSpacingHeight setFloatValue: verticalSpacing];
	
}

- (void) _chooseBackgroundImageForProfile: (NSString *) theProfile
{
    NSOpenPanel *panel;
    int sts;
    NSString *filename = nil;
		
    panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection: NO];
			
    sts = [panel runModalForDirectory: NSHomeDirectory() file:@"" types: [NSImage imageFileTypes]];
    if (sts == NSOKButton) {
		if([[panel filenames] count] > 0)
			filename = [[panel filenames] objectAtIndex: 0];
		
		if([filename length] > 0)
		{
			NSImage *anImage = [[NSImage alloc] initWithContentsOfFile: filename];
			if(anImage != nil)
			{
				[displayBackgroundImage setImage: anImage];
				[anImage release];
				[[iTermDisplayProfileMgr singleInstance] setBackgroundImage: filename forProfile: theProfile];
			}
			else
				[displayUseBackgroundImage setState: NSOffState];
		}
		else
			[displayUseBackgroundImage setState: NSOffState];
    }
    else
    {
		[displayUseBackgroundImage setState: NSOffState];
    }
	
}

@end

