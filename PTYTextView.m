// -*- mode:objc -*-
// $Id: PTYTextView.m,v 1.124 2004-02-20 00:01:14 ujwal Exp $
/*
 **  PTYTextView.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Sathyam
 **	     Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: NSTextView subclass. The view object for the VT100 screen.
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

#define DEBUG_ALLOC           0
#define DEBUG_METHOD_TRACE    0
#define GREED_KEYDOWN         1

#import <iTerm/iTerm.h>
#import <iTerm/PTYTextView.h>
#import <iTerm/PTYSession.h>
#import <iTerm/VT100Screen.h>
#import <iTerm/FindPanelWindowController.h>
#import <iTerm/PreferencePanel.h>
#import <iTerm/PTYScrollView.h>

@implementation PTYTextView


- (id)initWithFrame: (NSRect) aRect
{
#if DEBUG_ALLOC
    NSLog(@"%s 0x%x", __PRETTY_FUNCTION__, self);
#endif
    	
    self = [super initWithFrame: aRect];
    dataSource=_delegate=markedTextAttributes=NULL;
    
    [self setMarkedTextAttributes:
        [NSDictionary dictionaryWithObjectsAndKeys:
            [NSColor yellowColor], NSBackgroundColorAttributeName,
            [NSColor blackColor], NSForegroundColorAttributeName,
            font, NSFontAttributeName,
            [NSNumber numberWithInt:2],NSUnderlineStyleAttributeName,
            NULL]];
    deadkey = NO;
	CURSOR=YES;
	lastFindX = startX = -1;
    markedText=nil;
	[[self window] useOptimizedDrawing:YES];
    
	// register for some notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(frameChanged:)
                                                 name:NSWindowDidResizeNotification
                                               object:nil];
	
	// register for drag and drop
	[self registerForDraggedTypes: [NSArray arrayWithObjects:
        NSFilenamesPboardType,
        NSStringPboardType,
        nil]];
	
	// init the cache
	memset(charImages, 0, CACHESIZE*sizeof(CharCache));	
    charWidth = 12;
		
	
    return (self);
}

- (void) dealloc
{
#if DEBUG_ALLOC
    NSLog(@"PTYTextView: -dealloc 0x%x", self);
#endif
	int i;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];    
    for(i=0;i<16;i++) {
        [colorTable[i] release];
    }
    [defaultFGColor release];
    [defaultBGColor release];
    [defaultBoldColor release];
    [selectionColor release];
	
    [dataSource release];
    [_delegate release];
    [font release];
	[nafont release];
    [markedTextAttributes release];
		
    [self resetCharCache];
    [super dealloc];
}

- (BOOL)shouldDrawInsertionPoint
{
#if 0 // DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView shouldDrawInsertionPoint]",
          __FILE__, __LINE__);
#endif
    return NO;
}

- (BOOL)isFlipped
{
    return YES;
}

- (BOOL)isOpaque
{
    return YES;
}


- (BOOL) antiAlias
{
    return (antiAlias);
}

- (void) setAntiAlias: (BOOL) antiAliasFlag
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView setAntiAlias: %d]",
          __FILE__, __LINE__, antiAliasFlag);
#endif
    antiAlias = antiAliasFlag;
}

- (NSDictionary*) markedTextAttributes
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView selectedTextAttributes]",
          __FILE__, __LINE__);
#endif
    return markedTextAttributes;
}

- (void) setMarkedTextAttributes: (NSDictionary *) attr
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView setSelectedTextAttributes:%@]",
          __FILE__, __LINE__,attr);
#endif
    [markedTextAttributes release];
    [attr retain];
    markedTextAttributes=attr;
}

- (void) setFGColor:(NSColor*)color
{
    [defaultFGColor release];
    [color retain];
    defaultFGColor=color;
	[self setNeedsDisplay: YES];
	// reset our default character attributes    
}

- (void) setBGColor:(NSColor*)color
{
    [defaultBGColor release];
    [color retain];
    defaultBGColor=color;
	//    bg = [bg colorWithAlphaComponent: [[SESSION backgroundColor] alphaComponent]];
	//    fg = [fg colorWithAlphaComponent: [[SESSION foregroundColor] alphaComponent]];
	[self setNeedsDisplay: YES];
}

- (void) setBoldColor: (NSColor*)color
{
    [defaultBoldColor release];
    [color retain];
    defaultBoldColor=color;
	[self setNeedsDisplay: YES];
}

- (NSColor *) defaultFGColor
{
    return defaultFGColor;
}

- (NSColor *) defaultBGColor
{
	return defaultBGColor;
}

- (NSColor *) defaultBoldColor
{
    return defaultBoldColor;
}

- (void) setColorTable:(int) index highLight:(BOOL)hili color:(NSColor *) c
{
	int idx=(hili?1:0)*8+index;
	
    [colorTable[idx] release];
    [c retain];
    colorTable[idx]=c;
	[self setNeedsDisplay: YES];
}

- (NSColor *) colorForCode:(int) index 
{
    NSColor *color;
	int reversed;
	
	reversed = [[dataSource terminal] screenMode];
	
	if (index&DEFAULT_FG_COLOR_CODE)
    {
		if (index&1) // background color?
		{
			color=(reversed?defaultFGColor:defaultBGColor);
		}
		else if(index&BOLD_MASK)
		{
			color = [self defaultBoldColor];
		}
		else
		{
			color=(reversed?defaultBGColor:defaultFGColor);
		}
    }
    else
    {
        color=colorTable[index&15];
    }
	
    return color;
    
}

- (NSColor *) selectionColor
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView selectionColor]",
          __FILE__, __LINE__);
#endif
    
    return selectionColor;
}

- (void) setSelectionColor: (NSColor *) aColor
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView setSelectionColor:%@]",
          __FILE__, __LINE__,aColor);
#endif
    
    [selectionColor release];
    [aColor retain];
    selectionColor=aColor;
	[self setNeedsDisplay: YES];
}

- (NSFont *)font
{
    return font;
}

- (NSFont *)nafont
{
    return nafont;
}

- (void) setFont:(NSFont*)aFont nafont:(NSFont *)naFont;
{    
    [font release];
    [aFont retain];
    font=aFont;
    [nafont release];
    [naFont retain];
    nafont=naFont;
	[self setNeedsDisplay: YES];
    [self setMarkedTextAttributes:
        [NSDictionary dictionaryWithObjectsAndKeys:
            [NSColor yellowColor], NSBackgroundColorAttributeName,
            [NSColor blackColor], NSForegroundColorAttributeName,
            font, NSFontAttributeName,
            [NSNumber numberWithInt:2],NSUnderlineStyleAttributeName,
            NULL]];
	[self resetCharCache];
}

- (void) resetCharCache
{
	int loop;
	for (loop=0;loop<CACHESIZE;loop++)
    {
		[charImages[loop].image release];
		charImages[loop].image=nil;
    }
}

- (id) dataSource
{
    return (dataSource);
}

- (void) setDataSource: (id) aDataSource
{
    [dataSource release];
    [aDataSource retain];
    dataSource = aDataSource;
}

- (id) delegate
{
    return _delegate;
}

- (void) setDelegate: (id) aDelegate
{
    [_delegate release];
    [aDelegate retain];
    _delegate = aDelegate;
}    

- (float) lineHeight
{
    return (lineHeight);
}

- (void) setLineHeight: (float) aLineHeight
{
    lineHeight = aLineHeight;
}

- (float) lineWidth
{
    return (lineWidth);
}

- (void) setLineWidth: (float) aLineWidth
{
    lineWidth = aLineWidth;
}

- (float) charWidth
{
	return (charWidth);
}

- (void) setCharWidth: (float) width
{
	charWidth = width;
}

- (void) setForceUpdate: (BOOL) flag
{
	forceUpdate = flag;
}


// We override this method since both refresh and window resize can conflict resulting in this happening twice
// So we do not allow the size to be set larger than what the data source can fill
- (void) setFrameSize: (NSSize) aSize
{
	//NSLog(@"%s (0x%x): setFrameSize to (%f,%f)", __PRETTY_FUNCTION__, self, aSize.width, aSize.height);

	NSSize anotherSize = aSize;
	
	anotherSize.height = [dataSource numberOfLines] * lineHeight;
	
	[super setFrameSize: anotherSize];
}

- (void) refresh
{
	//NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);

    NSSize aSize;
	int height;
    
    if(dataSource != nil)
    {
        numberOfLines = [dataSource numberOfLines];
        aSize = [self frame].size;
        height = numberOfLines * lineHeight;
        if(height != [self frame].size.height)
        {
            NSRect aFrame;
            
			//NSLog(@"%s: 0x%x; new number of lines = %d; resizing height from %f to %d", 
			//	  __PRETTY_FUNCTION__, self, numberOfLines, [self frame].size.height, height);
            aFrame = [self frame];
            aFrame.size.height = height;
            [self setFrame: aFrame];
			if (![(PTYScroller *)([[self enclosingScrollView] verticalScroller]) userScroll]) [self scrollEnd];
        }
    }
	
	[self setNeedsDisplay: YES];
	
}


- (NSRect)adjustScroll:(NSRect)proposedVisibleRect
{
	forceUpdate = YES;
	proposedVisibleRect.origin.y=(int)(proposedVisibleRect.origin.y/lineHeight+0.5)*lineHeight;
	return proposedVisibleRect;
}

-(void) scrollLineUp: (id) sender
{
    NSRect scrollRect;
    
    scrollRect= [self visibleRect];
    scrollRect.origin.y-=[[self enclosingScrollView] verticalLineScroll];
	//forceUpdate = YES;
	//[self setNeedsDisplay: YES];
    //NSLog(@"%f/%f",[[self enclosingScrollView] verticalLineScroll],[[self enclosingScrollView] verticalPageScroll]);
    [self scrollRectToVisible: scrollRect];
}

-(void) scrollLineDown: (id) sender
{
    NSRect scrollRect;
    
    scrollRect= [self visibleRect];
    scrollRect.origin.y+=[[self enclosingScrollView] verticalLineScroll];
	//forceUpdate = YES;
    [self scrollRectToVisible: scrollRect];
}

-(void) scrollPageUp: (id) sender
{
    NSRect scrollRect;
    
    scrollRect= [self visibleRect];
    scrollRect.origin.y-=[[self enclosingScrollView] verticalPageScroll];
	//forceUpdate = YES;
    [self scrollRectToVisible: scrollRect];
}

-(void) scrollPageDown: (id) sender
{
    NSRect scrollRect;
    
    scrollRect= [self visibleRect];
    scrollRect.origin.y+=[[self enclosingScrollView] verticalPageScroll];
	//forceUpdate = YES;
    [self scrollRectToVisible: scrollRect];
}

-(void) scrollHome
{
    NSRect scrollRect;
    
    scrollRect= [self visibleRect];
    scrollRect.origin.y = 0;
	//forceUpdate = YES;
    [self scrollRectToVisible: scrollRect];
}

- (void)scrollEnd
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView scrollEnd]", __FILE__, __LINE__ );
#endif
    
    if (numberOfLines > 0)
    {
        NSRect aFrame;
		aFrame.origin.x = 0;
		aFrame.origin.y = (numberOfLines - 1) * lineHeight;
		aFrame.size.width = [self frame].size.width;
		aFrame.size.height = lineHeight;
		//forceUpdate = YES;
		[self scrollRectToVisible: aFrame];
    }
}

-(void) hideCursor
{
    CURSOR=NO;
}

-(void) showCursor
{
    CURSOR=YES;
}

- (void)renderChar:(NSImage *)image withChar:(unichar) carac withColor:(NSColor*)color withFont:(NSFont*)aFont bold:(int)bold
{
	NSAttributedString  *crap;
	NSDictionary *attrib;
	
	aFont=bold?[[NSFontManager sharedFontManager] convertFont: aFont toHaveTrait: NSBoldFontMask]:aFont;
	attrib=[[NSDictionary dictionaryWithObjectsAndKeys:
        aFont, NSFontAttributeName,
        color, NSForegroundColorAttributeName,
        nil] retain];
	
	
	crap = [[NSAttributedString alloc]initWithString:[NSString stringWithCharacters:&carac length:1]
										  attributes:attrib];
	[image lockFocus];
	[[NSGraphicsContext currentContext] setShouldAntialias:antiAlias];
	[crap drawAtPoint:NSMakePoint(0,0)];
	[image unlockFocus];
} // renderChar

#define  CELLSIZE (CACHESIZE/256)
- (NSImage *) getCharImage:(unichar) code color:(int)fg
{
	int i = code % 256 * CELLSIZE + code/256 % CELLSIZE;
	int j;
	NSImage *image;
	int width;
	int c;
	
	c= fg&(BOLD_MASK|31);
	if (!code) return nil;
	width=ISDOUBLEWIDTHCHARACTER(code)?2:1;
	for(j=0;(charImages[i].code!=code || charImages[i].color!=c) && charImages[i].image && j<CELLSIZE; i++,j++);
	if (!charImages[i].image) {
		//  NSLog(@"add into cache");
		image=charImages[i].image=[[[NSImage alloc]initWithSize:NSMakeSize(charWidth*width, lineHeight)] retain];
		charImages[i].code=code;
		charImages[i].color=fg;
		charImages[i].count=1;
		[self renderChar: image 
				withChar: code
			   withColor: [self colorForCode:fg] 
				withFont: ISDOUBLEWIDTHCHARACTER(c)?nafont:font
					bold: fg&BOLD_MASK];
		
		return image;
	}
	else if (j>=CELLSIZE) {
		//		NSLog(@"new char, but cache full");
		c=1;
		for(j=2; j<=CELLSIZE; j++) {	//find a least used one, and replace it with new char
			if (charImages[i-j].count<charImages[i-c].count) c=j;
		}
		image=charImages[c].image=[[[NSImage alloc]initWithSize:NSMakeSize(charWidth*width, lineHeight)] autorelease];
		charImages[c].code=code;
		charImages[c].color=fg;
		for(j=1; j<=CELLSIZE; j++) {	//reset the cache
			charImages[i-j].count-=charImages[i-c].count;
		}
		charImages[i].count=1;

		[self renderChar: image 
				withChar: code
			   withColor: [self colorForCode:fg] 
				withFont: ISDOUBLEWIDTHCHARACTER(c)?nafont:font
					bold: fg&BOLD_MASK];
		return image;
	}
	else {
		//		NSLog(@"already in cache");
		charImages[i].count++;
		/*compactflag++;
		if (compactflag>CACHESIZE*4) {
			compactflag=0;
			//[self compactCache];
		}*/
		return charImages[i].image;
	}
	
}

- (void) drawCharacter:(unichar)c fgColor:(int)fg AtX:(int)X Y:(int)Y
{
	NSImage *image;
	
	if (c) {
		//NSLog(@"%c(%d)",c,c);
		image=[self getCharImage:c 
						   color:fg];
		[image compositeToPoint:NSMakePoint(X,Y) operation:NSCompositeSourceOver];
	}
}	

- (void)drawRect:(NSRect)rect
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(0x%x):-[PTYTextView drawRect:(%f,%f,%f,%f) frameRect: (%f,%f,%f,%f)]",
          __PRETTY_FUNCTION__, self,
          rect.origin.x, rect.origin.y, rect.size.width, rect.size.height,
		  [self frame].origin.x, [self frame].origin.y, [self frame].size.width, [self frame].size.height);
#endif
		
    int numLines, i, j, t, lineOffset, WIDTH;
	int startScreenLineIndex,line, lineIndex;
    unichar *buf;
	NSRect bgRect;
	NSColor *aColor;
	char  *fg, *bg, *dirty;
	BOOL need_draw;
	int bgstart, ulstart;
    float curX, curY;
	char bgcode, sel, fgcode;
	int y1,y2,x1,x2;
	static int pre_x1, pre_x2, pre_y1, pre_y2;
	
    if(lineHeight <= 0 || lineWidth <= 0)
        return;
    
	WIDTH=[dataSource width];

	// Starting from which line?
	lineOffset = rect.origin.y/lineHeight;
    
	// How many lines do we need to draw?
	numLines = rect.size.height/lineHeight;

	// Which line is our screen start?
	startScreenLineIndex=[dataSource numberOfLines] - [dataSource height];
    //NSLog(@"%f+%f->%d+%d", rect.origin.y,rect.size.height,lineOffset,numLines);
	
	// Check if somethng is selected on screen
	if (startX!=-1) { 
		// let x1/y1 always be the beginning of the selection
		if (startY>endY||(startY==endY&&startX>endX)) {y1=endY; x1=endX; y2=startY; x2=startX;}
		else {y1=startY; x1=startX; y2=endY; x2=endX;}
		
		// if selection has changed from last, we redraw everything
		if ((pre_x1!=x1||pre_y1!=y1||pre_y2!=y2||pre_x2!=x2) && 
			((y1>=lineOffset && y1<=lineOffset+numLines) || (y2>=lineOffset && y2<=lineOffset+numLines))) {
			forceUpdate=YES; //force redraw everything
		}
	}
	else x1=-1;
	
	// [self adjustScroll] should've made sure we are at an integer multiple of a line
	curY=rect.origin.y +lineHeight;
	
    for(i = 0; i < numLines; i++)
    {
		curX=0;
        line = i + lineOffset;
		
		if(line >= [dataSource numberOfLines])
		{
			NSLog(@"%s (0x%x): illegal line index %d >= %d", __PRETTY_FUNCTION__, self, line, [dataSource numberOfLines]);
			break;
		}
		
		// Check if we are drawing a line in buffer
		if (line<startScreenLineIndex) {
			lineIndex=startScreenLineIndex-line;
			lineIndex=[dataSource lastBufferLineIndex]-lineIndex;
			if (lineIndex<0) lineIndex+=[dataSource scrollbackLines];
			buf=[dataSource bufferLines]+lineIndex*WIDTH;
			fg=[dataSource bufferFGColor]+lineIndex*WIDTH;
			bg=[dataSource bufferBGColor]+lineIndex*WIDTH;
		}
		else { // not in buffer
			lineIndex=line-startScreenLineIndex;
			buf=[dataSource screenLines]+lineIndex*WIDTH;
			fg=[dataSource screenFGColor]+lineIndex*WIDTH;
			bg=[dataSource screenBGColor]+lineIndex*WIDTH;
			dirty=[dataSource dirty]+lineIndex*WIDTH;
		}	
		
		//draw background and underline here
		bgstart=ulstart=-1;
		for(j=0;j<WIDTH;j++) {
			if (buf[j]==0xffff) continue;
			// Check if we need to redraw next char
			need_draw = line < startScreenLineIndex || forceUpdate || dirty[j] || (fg[j]&BLINK_MASK);
			// find out if the current char is being selected
			sel=(x1!=-1&&((line>y1&&line<y2)||(line==y1&&y1==y2&&j>=x1&&j<x2)||(line==y1&&y1!=y2&&j>=x1)||(line==y2&&y1!=y2&&j<x2)))?-1:bg[j];
			
			// if we don't have to update next char, finish pending jobs
			if (!need_draw){
				if (bgstart>=0) {
					aColor = (bgcode>=0)? [self colorForCode:bgcode] : selectionColor; 
					[aColor set];
					
					bgRect = NSMakeRect(curX+bgstart*charWidth,curY-lineHeight,(j-bgstart)*charWidth,lineHeight);
					NSRectFill(bgRect);
					
					// if we have a background image and we are using the background image, redraw image
					if([(PTYScrollView *)[self enclosingScrollView] backgroundImage] != nil && [aColor isEqual: defaultBGColor])
					{
						[(PTYScrollView *)[self enclosingScrollView] drawBackgroundImageRect: bgRect];
					}
				}						
				if (ulstart>=0) {
					[[self colorForCode:fgcode] set];
					NSRectFill(NSMakeRect(curX+ulstart*charWidth,curY-2,(j-ulstart)*charWidth,1));
				}
				bgstart=ulstart=-1;
			}
			else {
				if (bgstart<0) { bgstart=j; bgcode=sel; }
				else if (sel!=bgcode) {
					aColor = (bgcode>=0)? [self colorForCode:bgcode] : selectionColor; 
					[aColor set];
					
					bgRect = NSMakeRect(curX+bgstart*charWidth,curY-lineHeight,(j-bgstart)*charWidth,lineHeight);
					NSRectFill(bgRect);
					
					// if we have a background image and we are using the background image, redraw image
					if([(PTYScrollView *)[self enclosingScrollView] backgroundImage] != nil && [aColor isEqual: defaultBGColor])
					{
						[(PTYScrollView *)[self enclosingScrollView] drawBackgroundImageRect: bgRect];
					}
					bgcode=sel;
					bgstart=j;
				}
				if (ulstart<0 && fg[j]&UNDER_MASK && buf[j]) { ulstart=j; fgcode=fg[j]; }
				else if (ulstart>=0 && (fg[j]!=fgcode || !buf[j])) {
					[[self colorForCode:fgcode] set];
					NSRectFill(NSMakeRect(curX+ulstart*charWidth,curY-2,(j-ulstart)*charWidth,1));
					fgcode=fg[j];
					ulstart=(fg[j]&UNDER_MASK && buf[j])?j:-1;
				}
			}
		}
		if (bgstart>=0) {
			aColor = (bgcode>=0)? [self colorForCode:bgcode] : selectionColor; 
			[aColor set];
			
			bgRect = NSMakeRect(curX+bgstart*charWidth,curY-lineHeight,(j-bgstart)*charWidth,lineHeight);
			NSRectFill(bgRect);
		}
		// if we have a background image and we are using the background image, redraw image
		if([(PTYScrollView *)[self enclosingScrollView] backgroundImage] != nil && [aColor isEqual: defaultBGColor])
		{
			[(PTYScrollView *)[self enclosingScrollView] drawBackgroundImageRect: bgRect];
		}
		
		if (ulstart>=0) {
			[[self colorForCode:fgcode] set];
			NSRectFill(NSMakeRect(curX+ulstart*charWidth,curY-2,(j-ulstart)*charWidth,1));
		}
		
		//draw all char
		for(j=0;j<WIDTH;j++) {
			need_draw = (buf[j] && buf[j]!=0xffff) && (line < startScreenLineIndex || forceUpdate || dirty[j] || (fg[j]&BLINK_MASK));
			if (need_draw) { 	
				[self drawCharacter:buf[j] fgColor:fg[j] AtX:curX Y:curY];
				if (fg[j]&BLINK_MASK) { //if blink is set, switch the fg/bg color
					t=fg[j]&0x1f;
					fg[j]=(fg[j]&0xe0)+bg[j];
					bg[j]=t;
				}
				else if(line>=startScreenLineIndex) 
					dirty[j]=0;
			}
			curX+=charWidth;
		}
		//if (line>=startScreenLineIndex) memset(dirty,0,WIDTH);
		curY+=lineHeight;
	}
	
	x1=[dataSource cursorX]-1;
	y1=[dataSource cursorY]-1;
	//draw cursor
	if (CURSOR) {
		i = y1*[dataSource width]+x1;
		[[NSColor grayColor] set];
		NSRectFill(NSMakeRect(x1*charWidth,
							  (y1+[dataSource numberOfLines]-[dataSource height])*lineHeight,
							  charWidth,lineHeight));
		// draw any character on cursor if we need to
		unichar aChar = [dataSource screenLines][i];
		if(aChar && aChar!=0xffff)
		{
			[self drawCharacter: aChar 
						fgColor:[dataSource screenFGColor][i] 
							AtX:x1*charWidth 
							  Y:(y1+[dataSource numberOfLines]-[dataSource height]+1)*lineHeight];
		}
		[dataSource dirty][i] = 1; //cursor loc is dirty
		
	}
	
	// draw any text for NSTextInput
	if([self hasMarkedText]) {
		int len;
		
		len=[markedText length];
		if (len>[dataSource width]-x1) len=[dataSource width]-x1;
		[markedText drawInRect:NSMakeRect(x1*charWidth,
										  (y1+[dataSource numberOfLines]-[dataSource height])*lineHeight,
										  (WIDTH-x1)*charWidth,lineHeight)];
		memset([dataSource dirty]+y1*[dataSource width]+x1, 1,len*2); //len*2 is an over-estimation, but safe
	}
	

	forceUpdate=NO;
}

- (void)keyDown:(NSEvent *)event
{
    NSInputManager *imana = [NSInputManager currentInputManager];
    BOOL IMEnable = [imana wantsToInterpretAllKeystrokes];
    BOOL put;
    id delegate = [self delegate];
    
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView keyDown:%@]",
          __FILE__, __LINE__, event );
#endif
    
    // Hide the cursor
    [NSCursor setHiddenUntilMouseMoves: YES];    
    
    // Check for dead keys
    if (deadkey) {
        [self interpretKeyEvents:[NSArray arrayWithObject:event]];
        deadkey=[self hasMarkedText];
        return;
    }
    else if ([[event characters] length]<1) {
        deadkey=YES;
        [self interpretKeyEvents:[NSArray arrayWithObject:event]];
        return;
    }
    
    if (IMEnable) {
        BOOL prev = [self hasMarkedText];
        IM_INPUT_INSERT = NO;
        [self interpretKeyEvents:[NSArray arrayWithObject:event]];
        
#if GREED_KEYDOWN
        if (prev == NO &&
            IM_INPUT_INSERT == NO &&
            [self hasMarkedText] == NO)
        {
            put = YES;
        }
        else
            put = NO;
#else
        put = NO;
#endif
    }
    else
        put = YES;
    
    if (put == YES) {
        if ([delegate respondsToSelector:@selector(keyDown:)])
            [delegate keyDown:event];
        else
            [super keyDown:event];
    }
}

- (void) otherMouseDown: (NSEvent *) event
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s: %@]", __PRETTY_FUNCTION__, sender );
#endif
    
    if ([[self selectedText] length] > 0 && [_delegate respondsToSelector:@selector(pasteString:)])
        [_delegate pasteString:[self selectedText]];
	
}

- (void)mouseDown:(NSEvent *)event
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView mouseDown:%@]",
          __FILE__, __LINE__, event );
#endif
    
    NSPoint locationInWindow, locationInTextView;
    int x, y;
    
    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];
    
    x = locationInTextView.x/charWidth;
    y = locationInTextView.y/lineHeight;
    if (x>=[dataSource width]) x=[dataSource width];
    endX=startX=x;
    endY=startY=y;
	    
    if([_delegate respondsToSelector: @selector(willHandleEvent:)] && [_delegate willHandleEvent: event])
        [_delegate handleEvent: event];
	[self setNeedsDisplay: YES];
}

- (void)mouseUp:(NSEvent *)event
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView mouseUp:%@]",
          __FILE__, __LINE__, event );
#endif
    NSPoint locationInWindow, locationInTextView;
    int x, y;
    
    locationInWindow = [event locationInWindow];
    locationInTextView = [self convertPoint: locationInWindow fromView: nil];
    
    x = locationInTextView.x/charWidth;
    if (x>=[dataSource width]) x=[dataSource width];
    if (x<0) x=0;
    y = locationInTextView.y/lineHeight;
    if (y<0) y=0;
    if (y>=[dataSource numberOfLines]) y=numberOfLines-1;
    endX=x;
    endY=y;
    if (startY>endY||(startY==endY&&startX>endX)) {
        y=startY; startY=endY; endY=y;
        y=startX; startX=endX; endX=y;
    }
    else if (startY==endY&&startX==endX) startX=-1;
	
	// Handle double and triple click
	if([event clickCount] == 2)
	{
		// double-click; select word
	}
	else if ([event clickCount] >= 3)
	{
		// triple-click; select line
		startX = 0;
		endX = [dataSource width];
		startY = endY = y;
	}
	
    
    if (startX!=-1&&_delegate) {
        if([[PreferencePanel sharedInstance] copySelection])
            [self copy: self];
    }
	[self setNeedsDisplay: YES];
}

- (void)mouseDragged:(NSEvent *)event
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView mouseDragged:%@]",
          __FILE__, __LINE__, event );
#endif
    NSPoint locationInWindow = [event locationInWindow];
    NSPoint locationInTextView = [self convertPoint: locationInWindow fromView: nil];
    NSRect  rectInTextView = [self visibleRect];
    int x, y;
    
    /*   NSLog(@"(%f,%f)->(%f,%f)->(%f,%f)",locationInWindow.x,locationInWindow.y,
        locationInTextView.x,locationInTextView.y,
        locationInScrollView.x,locationInScrollView.y); */
    if (locationInTextView.y<rectInTextView.origin.y) {
        rectInTextView.origin.y=locationInTextView.y;
        [self scrollRectToVisible: rectInTextView];
    }
    else if (locationInTextView.y>rectInTextView.origin.y+rectInTextView.size.height) {
        rectInTextView.origin.y+=locationInTextView.y-rectInTextView.origin.y-rectInTextView.size.height;
        [self scrollRectToVisible: rectInTextView];
    }
    
    x = locationInTextView.x/charWidth;
    if (x>=[dataSource width]) x=[dataSource width];
    if (x<0) x=0;
    y = locationInTextView.y/lineHeight;
    if (y<0) y=0;
    if (y>=[dataSource numberOfLines]) y=numberOfLines-1;
    endX=x;
    endY=y;
	[self setNeedsDisplay: YES];
    //    NSLog(@"(%d,%d)-(%d,%d)",startX,startY,endX,endY);
}

- (NSString *) contentFromX:(int)startx Y:(int)starty ToX:(int)endx Y:(int)endy
{
	unichar *temp;
	int j, line, scline;
	int width, y, x1, x2;
	NSString *str;
	unichar *buf;
	
	width = [dataSource width];
	scline = [dataSource numberOfLines]-[dataSource height];
	temp = (unichar *) malloc(((endy-starty)*(width+1)+(endx-startx))*sizeof(unichar));
	j=0;
	for (y=starty;y<=endy;y++) {
		if (y<scline) {
			line=[dataSource lastBufferLineIndex]-scline+y;
			if (line<0) line+=[dataSource scrollbackLines];
			buf=[dataSource bufferLines]+line*width;
		} else {
			line=y-scline;
			buf=[dataSource screenLines]+line*width;
		}
		x1=0; x2=width;
		if (y==starty) x1=startx;
		if (y==endy) x2=endx;
		for(;x1<x2;x1++,j++) {
			if (buf[x1]!=0xffff) {
				temp[j]=buf[x1]?buf[x1]:' ';
			}
		}			
	    if (x1>=width) {
			while (j>x1&&temp[j-1]==' ') j--; // trim the trailing blanks
			temp[j++]='\n';
		}
	}
	
	str=[NSString stringWithCharacters:temp length:j];
	free(temp);
	
	return str;
}

- (NSString *) selectedText
{
	
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView copy:%@]", __FILE__, __LINE__, sender );
#endif
    
    if (startX<0) 
        return nil;
	
	return [self contentFromX:startX Y:startY ToX:endX Y:endY];
}

- (NSString *) content
{
	
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView copy:%@]", __FILE__, __LINE__, sender );
#endif
    	
	return [self contentFromX:0 Y:0 ToX:[dataSource width] Y:[dataSource numberOfLines]-1];
}

- (void) copy: (id) sender
{
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];
    NSString *copyString;
    
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView copy:%@]", __FILE__, __LINE__, sender );
#endif
    
    copyString=[self selectedText];
    
    if (copyString && [copyString length]>0) {
        [pboard declareTypes: [NSArray arrayWithObject: NSStringPboardType] owner: self];
        [pboard setString: copyString forType: NSStringPboardType];
    }
}

- (void)paste:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView paste:%@]", __FILE__, __LINE__, sender );
#endif
    
    if ([_delegate respondsToSelector:@selector(paste:)])
        [_delegate paste:sender];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView validateMenuItem:%@; supermenu = %@]", __FILE__, __LINE__, item, [[item menu] supermenu] );
#endif
    
    if ([item action] == @selector(paste:))
    {
        NSPasteboard *pboard = [NSPasteboard generalPasteboard];
        
        // Check if there is a string type on the pasteboard
        return ([pboard stringForType:NSStringPboardType] != nil);
    }
    else if ([item action ] == @selector(cut:))
        return NO;
    else if ([item action]==@selector(saveDocumentAs:))
    {
        // We always validate the "Save" command
        return (YES);
    }
    else if ([item action]==@selector(mail:) ||
             [item action]==@selector(browse:) ||
             [item action]==@selector(copy:))
    {
        //        NSLog(@"selected range:%d",[self selectedRange].length);
        return (startX>=0);
    }
    else
        return NO;
}

- (void)changeFont:(id)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView changeFont:%@]", __FILE__, __LINE__, sender );
#endif
    
    [super changeFont:sender];
}

- (NSMenu *)menuForEvent:(NSEvent *)theEvent
{
    NSMenu *cMenu;
    
    // Allocate a menu
    cMenu = [[NSMenu alloc] initWithTitle:@"Contextual Menu"];
    
    // Menu items for acting on text selections
    [cMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"-> Browser",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(browse:) keyEquivalent:@""];
    [cMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"-> Mail",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(mail:) keyEquivalent:@""];
    
    // Separator
    [cMenu addItem:[NSMenuItem separatorItem]];
    
    // Copy,  paste, and save
    [cMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Copy",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(copy:) keyEquivalent:@""];
    [cMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Paste",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(paste:) keyEquivalent:@""];
    [cMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Save",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(saveDocumentAs:) keyEquivalent:@""];
    
    // Separator
    [cMenu addItem:[NSMenuItem separatorItem]];
    
    // Select all
    [cMenu addItemWithTitle:NSLocalizedStringFromTableInBundle(@"Select All",@"iTerm", [NSBundle bundleForClass: [self class]], @"Context menu")
                     action:@selector(selectAll:) keyEquivalent:@""];
    
    
    // Ask the delegae if there is anything to be added
    if ([[self delegate] respondsToSelector:@selector(menuForEvent: menu:)])
        [[self delegate] menuForEvent:theEvent menu: cMenu];
    
    return [cMenu autorelease];
}

- (void) mail:(id)sender
{
    NSString *s=[self selectedText];
    NSURL *url;
    
    if (s && ([s length] > 0))
    {
        if (![s hasPrefix:@"mailto:"])
            url = [NSURL URLWithString:[@"mailto:" stringByAppendingString:s]];
        else
            url = [NSURL URLWithString:s];
        
        [[NSWorkspace sharedWorkspace] openURL:url];
    }
}

- (void) browse:(id)sender
{
    NSString *s=[self selectedText];
    NSURL *url;
    
    // Check for common types of URLs
    if ([s hasPrefix:@"file://"])
        url = [NSURL URLWithString:s];
    else if ([s hasPrefix:@"ftp"])
    {
        if (![s hasPrefix:@"ftp://"])
            url = [NSURL URLWithString:[@"ftp://" stringByAppendingString:s]];
        else
            url = [NSURL URLWithString:s];
    }
    else if (![s hasPrefix:@"http"])
        url = [NSURL URLWithString:[@"http://" stringByAppendingString:s]];
    else
        url = [NSURL URLWithString:s];
    
    [[NSWorkspace sharedWorkspace] openURL:url];
}

//
// Drag and Drop methods for our text view
//

//
// Called when our drop area is entered
//
- (unsigned int) draggingEntered:(id <NSDraggingInfo>)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView draggingEntered:%@]", __FILE__, __LINE__, sender );
#endif
    
    // Always say YES; handle failure later.
    bExtendedDragNDrop = YES;
    
    return bExtendedDragNDrop;
}

//
// Called when the dragged object is moved within our drop area
//
- (unsigned int) draggingUpdated:(id <NSDraggingInfo>)sender
{
    unsigned int iResult;
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView draggingUpdated:%@]", __FILE__, __LINE__, sender );
#endif
    
    // Let's see if our parent NSTextView knows what to do
    iResult = [super draggingUpdated: sender];
    
    // If parent class does not know how to deal with this drag type, check if we do.
    if (iResult == NSDragOperationNone) // Parent NSTextView does not support this drag type.
        return [self _checkForSupportedDragTypes: sender];
    
    return iResult;
}

//
// Called when the dragged object leaves our drop area
//
- (void) draggingExited:(id <NSDraggingInfo>)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView draggingExited:%@]", __FILE__, __LINE__, sender );
#endif
    
    // We don't do anything special, so let the parent NSTextView handle this.
    [super draggingExited: sender];
    
    // Reset our handler flag
    bExtendedDragNDrop = NO;
}

//
// Called when the dragged item is about to be released in our drop area.
//
- (BOOL) prepareForDragOperation:(id <NSDraggingInfo>)sender
{
    BOOL bResult;
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView prepareForDragOperation:%@]", __FILE__, __LINE__, sender );
#endif
    
    // Check if parent NSTextView knows how to handle this.
    bResult = [super prepareForDragOperation: sender];
    
    // If parent class does not know how to deal with this drag type, check if we do.
    if ( bResult != YES && [self _checkForSupportedDragTypes: sender] != NSDragOperationNone )
        bResult = YES;
    
    return bResult;
}

//
// Called when the dragged item is released in our drop area.
//
- (BOOL) performDragOperation:(id <NSDraggingInfo>)sender
{
    unsigned int dragOperation;
    BOOL bResult = NO;
    PTYSession *delegate = [self delegate];
    
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView performDragOperation:%@]", __FILE__, __LINE__, sender );
#endif
    
    // If parent class does not know how to deal with this drag type, check if we do.
    if (bExtendedDragNDrop)
    {
        NSPasteboard *pb = [sender draggingPasteboard];
        NSArray *propertyList;
        NSString *aString;
        int i;
        
        dragOperation = [self _checkForSupportedDragTypes: sender];
        
        switch (dragOperation)
        {
            case NSDragOperationCopy:
                // Check for simple strings first
                aString = [pb stringForType:NSStringPboardType];
                if (aString != nil)
                {
                    if ([delegate respondsToSelector:@selector(pasteString:)])
                        [delegate pasteString: aString];
                }
                    
                    // Check for file names
                    propertyList = [pb propertyListForType: NSFilenamesPboardType];
                for(i = 0; i < [propertyList count]; i++)
                {
                    
                    // Ignore text clippings
                    NSString *filename = (NSString*)[propertyList objectAtIndex: i]; // this contains the POSIX path to a file
                    NSDictionary *filenamesAttributes = [[NSFileManager defaultManager] fileAttributesAtPath:filename traverseLink:YES];
                    if (([filenamesAttributes fileHFSTypeCode] == 'clpt' &&
                         [filenamesAttributes fileHFSCreatorCode] == 'MACS') ||
                        [[filename pathExtension] isEqualToString:@"textClipping"] == YES)
                    {
                        continue;
                    }
                    
                    // Just paste the file names into the shell after escaping special characters.
                    if ([delegate respondsToSelector:@selector(pasteString:)])
                    {
                        NSMutableString *aMutableString;
                        
                        aMutableString = [[NSMutableString alloc] initWithString: (NSString*)[propertyList objectAtIndex: i]];
                        // get rid of special characters
                        [aMutableString replaceOccurrencesOfString: @"\\" withString: @"\\\\" options: 0 range: NSMakeRange(0, [aMutableString length])];
                        [aMutableString replaceOccurrencesOfString: @" " withString: @"\\ " options: 0 range: NSMakeRange(0, [aMutableString length])];
                        [aMutableString replaceOccurrencesOfString: @"(" withString: @"\\(" options: 0 range: NSMakeRange(0, [aMutableString length])];
                        [aMutableString replaceOccurrencesOfString: @")" withString: @"\\)" options: 0 range: NSMakeRange(0, [aMutableString length])];
                        [aMutableString replaceOccurrencesOfString: @"\"" withString: @"\\\"" options: 0 range: NSMakeRange(0, [aMutableString length])];
    [aMutableString replaceOccurrencesOfString: @"&" withString: @"\\&" options: 0 range: NSMakeRange(0, [aMutableString length])];
    [aMutableString replaceOccurrencesOfString: @"'" withString: @"\\'" options: 0 range: NSMakeRange(0, [aMutableString length])];

    [delegate pasteString: aMutableString];
    [delegate pasteString: @" "];
    [aMutableString release];
                    }

                }
    bResult = YES;
    break;				
        }

    }

    return bResult;
}

//
//
//
- (void) concludeDragOperation:(id <NSDraggingInfo>)sender
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView concludeDragOperation:%@]", __FILE__, __LINE__, sender );
#endif
    
    // If we did no handle the drag'n'drop, ask our parent to clean up
    // I really wish the concludeDragOperation would have a useful exit value.
    if (!bExtendedDragNDrop)
        [super concludeDragOperation: sender];
    
    bExtendedDragNDrop = NO;
}

- (void)resetCursorRects
{
    static NSCursor *cursor=nil;
	//    NSLog(@"Setting mouse here");
    if (!cursor) cursor=[[[NSCursor alloc] initWithImage:[[NSCursor arrowCursor] image] hotSpot:NSMakePoint(0,0)] retain];
    [self addCursorRect:[self bounds] cursor:cursor];
    [cursor setOnMouseEntered:YES];
}

// Save method
- (void) saveDocumentAs: (id) sender
{
	
    NSData *aData;
    NSSavePanel *aSavePanel;
    NSString *aString;
    
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView saveDocumentAs:%@]", __FILE__, __LINE__, sender );
#endif
    
    // We get our content of the textview or selection, if any
	aString = (startX<0) ? [self content] : [self selectedText];
    aData = [aString
            dataUsingEncoding: NSASCIIStringEncoding
         allowLossyConversion: YES];
    // retain here so that is does not go away...
    [aData retain];
    
    // initialize a save panel
    aSavePanel = [NSSavePanel savePanel];
    [aSavePanel setAccessoryView: nil];
    [aSavePanel setRequiredFileType: @""];
    
    // Run the save panel as a sheet
    [aSavePanel beginSheetForDirectory: @""
                                  file: @"Unknown"
                        modalForWindow: [self window]
                         modalDelegate: self
                        didEndSelector: @selector(_savePanelDidEnd: returnCode: contextInfo:)
                           contextInfo: aData];
}

- (void) print:(id)sender
{
    NSLog(@"print...");
}

/// NSTextInput stuff
- (void)doCommandBySelector:(SEL)aSelector
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView doCommandBySelector:...]",
          __FILE__, __LINE__);
#endif
    
#if GREED_KEYDOWN == 0
    id delegate = [self delegate];
    
    if ([delegate respondsToSelector:aSelector]) {
        [delegate performSelector:aSelector withObject:nil];
    }
#endif
}

- (void)insertText:(id)aString
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView insertText:%@]",
          __FILE__, __LINE__, aString);
#endif
    IM_INPUT_INSERT = YES;
    
    if ([self hasMarkedText]) {
        IM_INPUT_MARKEDRANGE = NSMakeRange(0, 0);
        [markedText release];
    }
    
    if ([_delegate respondsToSelector:@selector(insertText:)])
        [_delegate insertText:aString];
    else
        [super insertText:aString];
}

- (void)setMarkedText:(id)aString selectedRange:(NSRange)selRange
{
    
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView setMarkedText:%@ selectedRange:(%d,%d)]",
          __FILE__, __LINE__, aString, selRange.location, selRange.length);
#endif
    if ([aString isKindOfClass:[NSAttributedString class]]) {
        markedText=[[NSAttributedString alloc] initWithString:[aString string] attributes:[self markedTextAttributes]];
    }
    else {
        markedText=[[NSAttributedString alloc] initWithString:aString attributes:[self markedTextAttributes]];
    }
	IM_INPUT_MARKEDRANGE = NSMakeRange(0,[markedText length]);
    IM_INPUT_SELRANGE = selRange;
	[self setNeedsDisplay: YES];
}

- (void)unmarkText
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView unmarkText]", __FILE__, __LINE__ );
#endif
    IM_INPUT_MARKEDRANGE = NSMakeRange(0, 0);
}

- (BOOL)hasMarkedText
{
    BOOL result;
    
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView hasMarkedText]", __FILE__, __LINE__ );
#endif
    if (IM_INPUT_MARKEDRANGE.length > 0)
        result = YES;
    else
        result = NO;
    
    return result;
}

- (NSRange)markedRange
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView markedRange]", __FILE__, __LINE__);
#endif
    
    //return IM_INPUT_MARKEDRANGE;
    if (IM_INPUT_MARKEDRANGE.length > 0) {
        return NSMakeRange([dataSource cursorX]-1, IM_INPUT_MARKEDRANGE.length);
    }
    else
        return NSMakeRange([dataSource cursorX]-1, 0);
}

- (NSRange)selectedRange
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView selectedRange]", __FILE__, __LINE__);
#endif
    return NSMakeRange(NSNotFound, 0);
}

- (NSArray *)validAttributesForMarkedText
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView validAttributesForMarkedText]", __FILE__, __LINE__);
#endif
    return [NSArray arrayWithObjects:NSForegroundColorAttributeName,
        NSBackgroundColorAttributeName,
        NSUnderlineStyleAttributeName,
		NSFontAttributeName,
        nil];
}

- (NSAttributedString *)attributedSubstringFromRange:(NSRange)theRange
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView attributedSubstringFromRange:(%d,%d)]", __FILE__, __LINE__, theRange.location, theRange.length);
#endif
	
    return [markedText attributedSubstringFromRange:NSMakeRange(0,theRange.length)];
}

- (unsigned int)characterIndexForPoint:(NSPoint)thePoint
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView characterIndexForPoint:(%f,%f)]", __FILE__, __LINE__, thePoint.x, thePoint.y);
#endif
    
    return thePoint.x/charWidth;
}

- (long)conversationIdentifier
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView conversationIdentifier]", __FILE__, __LINE__);
#endif
    return [self hash]; //not sure about this
}

- (NSRect)firstRectForCharacterRange:(NSRange)theRange
{
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTextView firstRectForCharacterRange:(%d,%d)]", __FILE__, __LINE__, theRange.location, theRange.length);
#endif
    int y=[dataSource cursorY]-1;
    int x=[dataSource cursorX]-1;
    
    NSRect rect=NSMakeRect(x*charWidth,(y+[dataSource numberOfLines] - [dataSource height]+1)*lineHeight,charWidth*theRange.length,lineHeight);
    //NSLog(@"(%f,%f)",rect.origin.x,rect.origin.y);
    rect.origin=[[self window] convertBaseToScreen:[self convertPoint:rect.origin toView:nil]];
    //NSLog(@"(%f,%f)",rect.origin.x,rect.origin.y);
    
    return rect;
}

- (void)frameChanged:(NSNotification*)notification
{
	//NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
	//NSLogRect([self frame]);
    //if([notification object] == [self window] && [[self delegate] respondsToSelector: @selector(textViewResized:)])
    //    [[self delegate] textViewResized: self];
	//[self refresh];
}

- (void) findString: (NSString *) aString forwardDirection: (BOOL) direction ignoringCase: (BOOL) caseCheck
{
/*	int j, line, scline;
	int startx, starty, endx, endy;
	int width, y, x1, x2;
	int fx, fy, tx, tp;
	unichar *buf;
		
	if ([aString length] <= 0)
	{
		NSBeep();
		return;
	}

	width = [dataSource width];
	scline = [dataSource numberOfLines]-[dataSource height];
	if (lastFindX==-1) {				
		startx=0;
		starty=0;
		endx=[dataSource width];
		endy=[dataSource numberOfLines]-1;
	}
	else if (direction) {
		startx=lastFindX+1;
		starty=lastFindY;
		endx=[dataSource width];
		endy=[dataSource numberOfLines]-1;
	}
	else {
		startx=0;
		starty=0;
		endx=lastFindX-1;
		endY=lastFindY;
	}
	
	fx=-1;
	for (y=starty;y<=endy;y++) {
		if (y<scline) {
			line=[dataSource lastBufferLineIndex]-scline+y;
			if (line<0) line+=[dataSource scrollbackLines];
			buf=[dataSource bufferLines]+line*width;
		} else {
			line=y-scline;
			buf=[dataSource screenLines]+line*width;
		}
		x1=0; x2=width;
		if (y==starty) x1=startx;
		if (y==endy) x2=endx;
		for(;x1<x2;x1++) {
			if (buf[x1]!=0xffff) {
				if (buf[x1]==[aString characterAtIndex:j]) {
					j++;
					NSLog(@"%d",j);
					if (fx==-1) { fx=x1; fy=y; }
					startx=x1+1;
					starty=y;
					if (startx>=width) { startx=0; starty++; }
					if (j>=[aString length]) break;
				}
				else {
					if (j) {
						j=0;
						y=starty--;
					}
					fx=-1;
				}
			}
		}		
		if (j>=[aString length]) { // Found!
			startX=lastFindX=fx;
			startY=lastFindY=fy;
			endX=x1;
			endY=y;
			return;
		}
	}
	lastFindX = -1;
	NSBeep(); */
}
@end

//
// private methods
//
@implementation PTYTextView (Private)

- (unsigned int) _checkForSupportedDragTypes:(id <NSDraggingInfo>) sender
{
    NSString *sourceType;
    BOOL iResult;
    
    iResult = NSDragOperationNone;
    
    // We support the FileName drag type for attching files
    sourceType = [[sender draggingPasteboard] availableTypeFromArray: [NSArray arrayWithObjects:
        NSFilenamesPboardType,
        NSStringPboardType,
        nil]];
    
    if (sourceType)
        iResult = NSDragOperationCopy;
    
    return iResult;
}

- (void) _savePanelDidEnd: (NSSavePanel *) theSavePanel
               returnCode: (int) theReturnCode
              contextInfo: (void *) theContextInfo
{
    // If successful, save file under designated name
    if (theReturnCode == NSOKButton)
    {
        if ( ![(NSData *)theContextInfo writeToFile: [theSavePanel filename] atomically: YES] )
            NSBeep();
    }
    // release our hold on the data
    [(NSData *)theContextInfo release];
}

@end
