// -*- mode:objc -*-
// $Id: PTYTask.m,v 1.52 2008-10-24 05:25:00 yfabian Exp $
//
/*
 **  PTYTask.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Setlur
 **	     Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Implements the interface to the pty session.
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

// Debug option
#define DEBUG_THREAD          0
#define DEBUG_ALLOC           0
#define DEBUG_METHOD_TRACE    0

#import <stdio.h>
#import <stdlib.h>
#import <unistd.h>
#import <util.h>
#import <sys/ioctl.h>
#import <sys/types.h>
#import <sys/wait.h>
#import <sys/time.h>

#import <iTerm/PTYTask.h>
#import <iTerm/PreferencePanel.h>


static char readbuf[4096];

@implementation PTYTask

#define CTRLKEY(c)   ((c)-'A'+1)

static void setup_tty_param(struct termios *term,
							struct winsize *win,
							int width,
							int height)
{
    memset(term, 0, sizeof(struct termios));
    memset(win, 0, sizeof(struct winsize));
	
    term->c_iflag = ICRNL | IXON | IXANY | IMAXBEL | BRKINT;
    term->c_oflag = OPOST | ONLCR;
    term->c_cflag = CREAD | CS8 | HUPCL;
    term->c_lflag = ICANON | ISIG | IEXTEN | ECHO | ECHOE | ECHOK | ECHOKE | ECHOCTL;
	
    term->c_cc[VEOF]      = CTRLKEY('D');
    term->c_cc[VEOL]      = -1;
    term->c_cc[VEOL2]     = -1;
    term->c_cc[VERASE]    = 0x7f;	// DEL
    term->c_cc[VWERASE]   = CTRLKEY('W');
    term->c_cc[VKILL]     = CTRLKEY('U');
    term->c_cc[VREPRINT]  = CTRLKEY('R');
    term->c_cc[VINTR]     = CTRLKEY('C');
    term->c_cc[VQUIT]     = 0x1c;	// Control+backslash
    term->c_cc[VSUSP]     = CTRLKEY('Z');
    term->c_cc[VDSUSP]    = CTRLKEY('Y');
    term->c_cc[VSTART]    = CTRLKEY('Q');
    term->c_cc[VSTOP]     = CTRLKEY('S');
    term->c_cc[VLNEXT]    = -1;
    term->c_cc[VDISCARD]  = -1;
    term->c_cc[VMIN]      = 1;
    term->c_cc[VTIME]     = 0;
    term->c_cc[VSTATUS]   = -1;
	
    term->c_ispeed = B38400;
    term->c_ospeed = B38400;
	
    win->ws_row = height;
    win->ws_col = width;
    win->ws_xpixel = 0;
    win->ws_ypixel = 0;
}

static int writep(int fds, char *buf, size_t len)
{
    int wrtlen = len;
    int result = 0;
    int sts = 0;
    char *tmpPtr = buf;
    int chunk;
    struct timeval tv;
    fd_set wfds,efds;
	
    while (wrtlen > 0) {
		
		FD_ZERO(&wfds);
		FD_ZERO(&efds);
		FD_SET(fds, &wfds);
		FD_SET(fds, &efds);	
		
		tv.tv_sec = 0;
		tv.tv_usec = 100000;
		
		sts = select(fds + 1, NULL, &wfds, &efds, &tv);
		
		if (sts == 0) {
			NSLog(@"Write timeout!");
			break;
		}	
		
		if(wrtlen > 1024)
			chunk = 1024;
		else
			chunk = wrtlen;
		sts = write(fds, tmpPtr, wrtlen);
		if (sts <= 0)
			break;
		
		wrtlen -= sts;
		tmpPtr += sts;
		
    }
    if (sts <= 0)
		result = sts;
    else
		result = len;
	
    return result;
}

- (id)init
{
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
    if ([super init] == nil)
		return nil;
	
    PID = (pid_t)-1;
    STATUS = 0;
    DELEGATEOBJECT = nil;
    FILDES = -1;
    TTY = nil;
    LOG_PATH = nil;
    LOG_HANDLE = nil;
    hasOutput = NO;
    updateTimer = writeTimer =nil;
	inputBuffer = NULL;
	inputBufferLen = 0;
    
    return self;
}

- (void)dealloc
{
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x", __PRETTY_FUNCTION__, self);
#endif
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    
 	if (updateTimer) {
		[updateTimer invalidate]; [updateTimer release]; updateTimer = nil;
	}
	if (writeTimer) {
		[writeTimer invalidate]; [writeTimer release]; writeTimer = nil;
	}
	
    
    if (PID > 0)
		kill(PID, SIGKILL);
    
	if (FILDES >= 0)
		close(FILDES);
	
	if (inputBuffer) free(inputBuffer);

	[dataHandle release];
    [TTY release];
    [PATH release];
    [super dealloc];
#if DEBUG_ALLOC
    NSLog(@"%s: 0x%x, done", __PRETTY_FUNCTION__, self);
#endif
}

- (void)launchWithPath:(NSString *)progpath
			 arguments:(NSArray *)args
		   environment:(NSDictionary *)env
				 width:(int)width
				height:(int)height
{
    struct termios term;
    struct winsize win;
    char ttyname[PATH_MAX];
    int sts;
    int one = 1;
	
    PATH = [progpath copy];
	
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[launchWithPath:%@ arguments:%@ environment:%@ width:%d height:%d", __FILE__, __LINE__, progpath, args, env, width, height);
#endif    
    setup_tty_param(&term, &win, width, height);
    PID = forkpty(&FILDES, ttyname, &term, &win);
    if (PID == (pid_t)0) {
		const char *path = [[progpath stringByStandardizingPath] cString];
		int max = args == nil ? 0: [args count];
		const char *argv[max + 2];
		
		argv[0] = path;
		if (args != nil) {
            int i;
			for (i = 0; i < max; ++i)
				argv[i + 1] = [[args objectAtIndex:i] cString];
		}
		argv[max + 1] = NULL;
		
		if (env != nil ) {
			NSArray *keys = [env allKeys];
			int i, max = [keys count];
			for (i = 0; i < max; ++i) {
				NSString *key, *value;
				key = [keys objectAtIndex:i];
				value = [env objectForKey:key];
				if (key != nil && value != nil) 
					setenv([key cString], [value cString], 1);
			}
		}
        chdir([[[env objectForKey:@"PWD"] stringByExpandingTildeInPath] cString]);
		sts = execvp(path, (char * const *) argv);
		
		/*
		 exec error
		 */
		fprintf(stdout, "## exec failed ##\n");
		fprintf(stdout, "%s %s\n", path, strerror(errno));
		
		sleep(1);
		_exit(-1);
    }
    else if (PID < (pid_t)0) {
		NSLog(@"%@ %s", progpath, strerror(errno));
		NSRunCriticalAlertPanel(NSLocalizedStringFromTableInBundle(@"Unable to Fork!",@"iTerm", [NSBundle bundleForClass: [self class]], @"Fork Error"),
						NSLocalizedStringFromTableInBundle(@"iTerm cannot launch the program for this session.",@"iTerm", [NSBundle bundleForClass: [self class]], @"Fork Error"),
						NSLocalizedStringFromTableInBundle(@"Close Session",@"iTerm", [NSBundle bundleForClass: [self class]], @"Fork Error"),
						nil,nil);
		[[DELEGATEOBJECT parent] closeSession:DELEGATEOBJECT];
		return;
    }
	
    sts = ioctl(FILDES, TIOCPKT, &one);
    NSParameterAssert(sts >= 0);
	
    TTY = [[NSString stringWithCString:ttyname] retain];
    NSParameterAssert(TTY != nil);
	
	fcntl(FILDES,F_SETFL,O_NONBLOCK);
	dataHandle = [[NSFileHandle alloc] 
                       initWithFileDescriptor:FILDES];
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(processRead)
               name:NSFileHandleDataAvailableNotification
             object:nil];
    [dataHandle waitForDataInBackgroundAndNotify];
}

- (void)processRead
{
    int sts;
	fd_set rfds,efds;
	struct timeval timeout={0,0};
	
#if DEBUG_THREAD
    NSLog(@"%s(%d):+[PTYTask _processReadThread:%@] start",
		  __FILE__, __LINE__, [boss description]);
#endif
	
    
	FD_ZERO(&rfds);
	FD_ZERO(&efds);
	
	// check if the session has been terminated
	if (FILDES==-1) {
		[self brokenPipe];
		return;
	}
	
	FD_SET(FILDES, &rfds);
	FD_SET(FILDES, &efds);
	
	sts = select(FILDES + 1, &rfds, NULL, &efds, &timeout);
	
	if (sts < 0) {
		[self brokenPipe];
		return;
	}
	else if (FD_ISSET(FILDES, &efds)) {
		sts = read(FILDES, readbuf, 1);
#if 0 // debug
		fprintf(stderr, "read except:%d byte ", sts);
		if (readbuf[0] & TIOCPKT_FLUSHREAD)
			fprintf(stderr, "TIOCPKT_FLUSHREAD ");
		if (readbuf[0] & TIOCPKT_FLUSHWRITE)
			fprintf(stderr, "TIOCPKT_FLUSHWRITE ");
		if (readbuf[0] & TIOCPKT_STOP)
			fprintf(stderr, "TIOCPKT_STOP ");
		if (readbuf[0] & TIOCPKT_START)
			fprintf(stderr, "TIOCPKT_START ");
		if (readbuf[0] & TIOCPKT_DOSTOP)
			fprintf(stderr, "TIOCPKT_DOSTOP ");
		if (readbuf[0] & TIOCPKT_NOSTOP)
			fprintf(stderr, "TIOCPKT_NOSTOP ");
		fprintf(stderr, "\n");
#endif
		if (sts == 0) {
			[self brokenPipe];
			return;
		}
	}
	else if (FD_ISSET(FILDES, &rfds)) {
		struct timeval t;
		double t1;
		int sum=0;
		gettimeofday(&t, NULL);
		t1=t.tv_sec+t.tv_usec*0.000001+(0.001+0.001 * [[PreferencePanel sharedInstance] refreshRate]);
		timeout.tv_usec=5;
		do {
			sts = read(FILDES, readbuf, sizeof(readbuf));
			sum+=sts;
			if (sts > 1) {
				hasOutput = YES;
				[self readTask:readbuf+1 length:sts-1];
				gettimeofday(&t, NULL);
				if (t.tv_sec+t.tv_usec*0.000001>t1) break;
				FD_ZERO(&rfds);
				FD_ZERO(&efds);
				FD_SET(FILDES, &rfds);
				FD_SET(FILDES, &efds);
				sts = select(FILDES + 1, &rfds, NULL, &efds, &timeout);
				if (FD_ISSET(FILDES, &efds)) {
					sts = read(FILDES, readbuf, 1);
					if (sts == 0) {
						[self brokenPipe];
						return;
					}
					else break;
				}
			}
			else break;
		} while (FD_ISSET(FILDES, &rfds));
		//NSLog(@"read: %d bytes", sum);
	}
    [dataHandle waitForDataInBackgroundAndNotify];
    if (!updateTimer) {
        updateTimer = [[NSTimer scheduledTimerWithTimeInterval:(0.001+0.001 * [[PreferencePanel sharedInstance] refreshRate])
                                                      target:self
                                                    selector:@selector(updateDisplay)
                                                    userInfo:nil
                                                     repeats:NO] retain];
    }
}

- (void)processWrite
{
	int len=1024;
	int sts;
	fd_set wfds;
	struct timeval t, tv = {0, 1000};
	void *temp;
	double t1;
	BOOL written=NO;
    
	if (inputBuffer) {
		
		gettimeofday(&t, NULL);
		t1=t.tv_sec+t.tv_usec*0.000001+0.01;
		
		temp=inputBuffer;
		do {
			FD_ZERO(&wfds);
			FD_SET(FILDES, &wfds);
			sts = select(FILDES + 1, NULL, &wfds, NULL, &tv);
			if (sts>0) {
				if (inputBufferLen<len) len = inputBufferLen;
				sts = write(FILDES, (char *)temp, len);
				if (sts > 0 ) {
					inputBufferLen -= sts;
					temp+=sts;
					written = YES;
				}
			}
			gettimeofday(&t, NULL);
			if (t.tv_sec+t.tv_usec*0.000001>t1) break;
		} while (inputBufferLen>0);
		
		if (inputBufferLen>0) {
			if (written) {
				void *temp2 = malloc(inputBufferLen);
				memcpy(temp2, temp, inputBufferLen);
				free(inputBuffer);
				inputBuffer=temp2;
			}
			[writeTimer autorelease];
			writeTimer = [[NSTimer scheduledTimerWithTimeInterval:0.01
														   target:self
														 selector:@selector(processWrite)
														 userInfo:nil
														  repeats:NO] retain];
		}
		else {
			free(inputBuffer);
			inputBuffer=NULL;
			inputBufferLen=0;
			[writeTimer autorelease];
			writeTimer = nil;
		}
	}
	else {
		[writeTimer autorelease];
		writeTimer = nil;
	}
}

- (BOOL) hasOutput
{
    return (hasOutput);
}

- (void) setHasOutput: (BOOL) flag
{
    hasOutput = flag;
    if([self firstOutput] == NO)
		[self setFirstOutput: flag];
}

- (BOOL) firstOutput
{
    return (firstOutput);
}

- (void) setFirstOutput: (BOOL) flag
{
    firstOutput = flag;
}


- (void)setDelegate:(id)object
{
    DELEGATEOBJECT = object;
}

- (id)delegate
{
    return DELEGATEOBJECT;
}

- (void) doIdleTasks
{
    if ([DELEGATEOBJECT respondsToSelector:@selector(doIdleTasks)]) {
		[DELEGATEOBJECT doIdleTasks];
    }
}


- (void)readTask:(char *)buf length:(int)length
{
	NSData *data;
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTask readTask:%@]", __FILE__, __LINE__, data);
#endif
	if([self logging])
	{
		data = [[NSData alloc] initWithBytes: buf length: length];
		[LOG_HANDLE writeData:data];
		[data release];
	}
	
	// forward the data to our delegate
	[DELEGATEOBJECT readTask:buf length:length];
}

- (void)writeTask:(NSData *)data
{
    const void *datap = [data bytes];
    size_t len = [data length];
     
#if DEBUG_METHOD_TRACE
    NSLog(@"%s(%d):-[PTYTask writeTask:%@]", __FILE__, __LINE__, data);
#endif
	
    if(FILDES >= 0) {
		if (inputBuffer || len > 1024) {
			void *temp;
			temp = realloc(inputBuffer, inputBufferLen+len); 
			if (temp) {
				inputBuffer = temp;
				memcpy(inputBuffer+inputBufferLen, datap, len);
				inputBufferLen += len;
			}
			if (!writeTimer) {
				writeTimer = [[NSTimer scheduledTimerWithTimeInterval:0.001
																target:self
															  selector:@selector(processWrite)
															  userInfo:nil
															   repeats:NO] retain];
			}
		}
		else {
			int sts = writep(FILDES, (char *)datap, len);
			if (sts < 0 ) {
				NSLog(@"%s(%d): writep() %s", __FILE__, __LINE__, strerror(errno));
			}
		}
    }
}

- (void)brokenPipe
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    if ([DELEGATEOBJECT respondsToSelector:@selector(brokenPipe)]) {
        [DELEGATEOBJECT brokenPipe];
    }
}

- (void)sendSignal:(int)signo
{
    if (PID >= 0)
		kill(PID, signo);
}

- (void)setWidth:(int)width height:(int)height
{
    struct winsize winsize;
	
    if(FILDES == -1)
		return;
	
    ioctl(FILDES, TIOCGWINSZ, &winsize);
	if (winsize.ws_col != width || winsize.ws_row != height) {
		winsize.ws_col = width;
		winsize.ws_row = height;
		ioctl(FILDES, TIOCSWINSZ, &winsize);
	}
}

- (pid_t)pid
{
    return PID;
}

- (int)wait
{
    if (PID >= 0) 
		waitpid(PID, &STATUS, 0);
	
    return STATUS;
}

- (void)stop
{
    [self sendSignal:SIGKILL];
	usleep(10000);
	if(FILDES >= 0)
		close(FILDES);
    FILDES = -1;
    
    [self wait];
}

- (int)status
{
    return STATUS;
}

- (NSString *)tty
{
    return TTY;
}

- (NSString *)path
{
    return PATH;
}

- (BOOL)loggingStartWithPath:(NSString *)path
{
    [LOG_PATH autorelease];
    LOG_PATH = [[path stringByStandardizingPath ] copy];
	
    [LOG_HANDLE autorelease];
    LOG_HANDLE = [NSFileHandle fileHandleForWritingAtPath:LOG_PATH];
    if (LOG_HANDLE == nil) {
		NSFileManager *fm = [NSFileManager defaultManager];
		[fm createFileAtPath:LOG_PATH
					contents:nil
				  attributes:nil];
		LOG_HANDLE = [NSFileHandle fileHandleForWritingAtPath:LOG_PATH];
    }
    [LOG_HANDLE retain];
    [LOG_HANDLE seekToEndOfFile];
	
    return LOG_HANDLE == nil ? NO:YES;
}

- (void)loggingStop
{
    [LOG_HANDLE closeFile];
	
    [LOG_PATH autorelease];
    [LOG_HANDLE autorelease];
    LOG_PATH = nil;
    LOG_HANDLE = nil;
}

- (BOOL)logging
{
    return LOG_HANDLE == nil ? NO : YES;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"PTYTask(pid %d, fildes %d)", PID, FILDES];
}

@end

@implementation PTYTask (Private)

- (void) updateDisplay
{   
    [DELEGATEOBJECT updateDisplay];
    [updateTimer release];
    updateTimer = nil;
}

@end
