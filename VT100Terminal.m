// -*- mode:objc -*-
// $Id: VT100Terminal.m,v 1.65 2003-05-13 18:23:09 ujwal Exp $
//
/*
 **  VT100Terminal.m
 **
 **  Copyright (c) 2002, 2003
 **
 **  Author: Fabian, Ujwal S. Sathyam
 **	     Initial code by Kiichi Kusama
 **
 **  Project: iTerm
 **
 **  Description: Implements the model class VT100 terminal.
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

#import "VT100Terminal.h"
#import "VT100Screen.h"
#import "NSStringITerm.h"

#define DEBUG_ALLOC	0

/*
  Traditional Chinese (Big5)
    1st   0xa1-0xfe
    2nd   0x40-0x7e || 0xa1-0xfe

  Simplifed Chinese (EUC_CN)
    1st   0x81-0xfe
    2nd   0x40-0x7e || 0x80-0xfe
*/

#define UNKNOWN		('#')

static NSString *NSBlinkAttributeName=@"NSBlinkAttributeName";

@implementation VT100Terminal

#define iscontrol(c)  ((c) <= 0x1f) 

#define iseuccn(c)   ((c) >= 0x81 && (c) <= 0xfe)
#define isbig5(c)    ((c) >= 0xa1 && (c) <= 0xfe)
#define issjiskanji(c)  (((c) >= 0x81 && (c) <= 0x9f) ||  \
                         ((c) >= 0xe0 && (c) <= 0xef))
#define iseuckr(c)   ((c) >= 0xa1 && (c) <= 0xfe)

#define isGBEncoding(e) 	((e)==0x80000019||(e)==0x80000421|| \
                                 (e)==0x80000631||(e)==0x80000632|| \
                                 (e)==0x80000930)
#define isBig5Encoding(e) 	((e)==0x80000002||(e)==0x80000423|| \
                                 (e)==0x80000931||(e)==0x80000a03|| \
                                 (e)==0x80000a06)
#define isJPEncoding(e) 	((e)==0x80000001||(e)==0x8||(e)==0x15)
#define isSJISEncoding(e)	((e)==0x80000628||(e)==0x80000a01)
#define isKREncoding(e)		((e)==0x80000422||(e)==0x80000003|| \
                                 (e)==0x80000840||(e)==0x80000940)
#define ESC  0x1b
#define DEL  0x7f

#define CURSOR_SET_DOWN      "\033OB"
#define CURSOR_SET_UP        "\033OA"
#define CURSOR_SET_RIGHT     "\033OC"
#define CURSOR_SET_LEFT      "\033OD"
#define CURSOR_RESET_DOWN    "\033[B"
#define CURSOR_RESET_UP      "\033[A"
#define CURSOR_RESET_RIGHT   "\033[C"
#define CURSOR_RESET_LEFT    "\033[D"
#define CURSOR_MOD_DOWN      "\033[%dB"
#define CURSOR_MOD_UP        "\033[%dA"
#define CURSOR_MOD_RIGHT     "\033[%dC"
#define CURSOR_MOD_LEFT      "\033[%dD"

#define KEY_INSERT           "\033[2~"
#define KEY_PAGE_UP          "\033[5~"
#define KEY_PAGE_DOWN        "\033[6~"
#define KEY_HOME             "\033[1~"
#define KEY_END              "\033[4~"
#define KEY_DEL		     "\033[3~"
#define KEY_BACKSPACE	     "\010"

#define KEY_PF1		     "\033OP"
#define KEY_PF2		     "\033OQ"
#define KEY_PF3	             "\033OR"
#define KEY_PF4		     "\033OS"

#define ALT_KP_0		"\033Op"
#define ALT_KP_1		"\033Oq"
#define ALT_KP_2		"\033Or"
#define ALT_KP_3		"\033Os"
#define ALT_KP_4		"\033Ot"
#define ALT_KP_5		"\033Ou"
#define ALT_KP_6		"\033Ov"
#define ALT_KP_7		"\033Ow"
#define ALT_KP_8		"\033Ox"
#define ALT_KP_9		"\033Oy"
#define ALT_KP_MINUS		"\033Om"
#define ALT_KP_PLUS		"\033Ol"
#define ALT_KP_PERIOD		"\033On"
#define ALT_KP_ENTER		"\033OM"



#define KEY_FUNCTION_FORMAT  "\033[%d~"

#define REPORT_POSITION      "\033[%d;%dR"
#define REPORT_STATUS        "\033[0n"
#define REPORT_WHATAREYOU    "\033[?1;0c"
#define REPORT_VT52          "\033/Z"

#define conststr_sizeof(n)   ((sizeof(n)) - 1)


typedef struct {
    int p[VT100CSIPARAM_MAX];
    int count;
    int cmd;
    BOOL question;
} CSIParam;

// functions
static BOOL isCSI(unsigned char *, size_t);
static BOOL isXTERM(unsigned char *, size_t);
static BOOL isString(unsigned char *, NSStringEncoding);
static size_t getCSIParam(unsigned char *, size_t, CSIParam *, VT100Screen *);
static VT100TCC decode_csi(unsigned char *, size_t, size_t *,VT100Screen *);
static VT100TCC decode_xterm(unsigned char *, size_t, size_t *,NSStringEncoding);
static VT100TCC decode_other(unsigned char *, size_t, size_t *);
static VT100TCC decode_control(unsigned char *, size_t, size_t *,NSStringEncoding,VT100Screen *);
static int utf8_reqbyte(unsigned char);
static VT100TCC decode_ascii(unsigned char *, size_t, size_t *);
static VT100TCC decode_utf8(unsigned char *, size_t, size_t *);
static VT100TCC decode_euccn(unsigned char *, size_t, size_t *);
static VT100TCC decode_big5(unsigned char *,size_t, size_t *);
static VT100TCC decode_string(unsigned char *, size_t, size_t *,
			      NSStringEncoding);


static BOOL isCSI(unsigned char *code, size_t len)
{
    if (len >= 2 && code[0] == ESC && (code[1] == '['))
	return YES;
    return NO;
}

static BOOL isXTERM(unsigned char *code, size_t len)
{
    if (len >= 2 && code[0] == ESC && (code[1] == ']'))
        return YES;
    return NO;
}

static BOOL isString(unsigned char *code,
		    NSStringEncoding encoding)
{
    BOOL result = NO;

//    NSLog(@"%@",[NSString localizedNameOfStringEncoding:encoding]);
    if (isascii(*code)) {
        result = YES;
    }
    else if (encoding== NSUTF8StringEncoding) {
        if (*code >= 0x80)
            result = YES;
    }
    else if (isGBEncoding(encoding)) {
        if (iseuccn(*code))
            result = YES;
    }
    else if (isBig5Encoding(encoding)) {
        if (isbig5(*code))
            result = YES;
    }
    else if (isJPEncoding(encoding)) {
        if (*code ==0x8e || *code==0x8f|| (*code>=0xa1&&*code<=0xfe))
            result = YES;
    }
    else if (isSJISEncoding(encoding)) {
        if (*code >= 0x80)
            result = YES;
    }
    else if (isKREncoding(encoding)) {
        if (iseuckr(*code))
            result = YES;
    }
    else if (*code>=0x20) {
        result = YES;
    }

    return result;
}

static size_t getCSIParam(unsigned char *datap,
			  size_t datalen,
			  CSIParam *param, VT100Screen *SCREEN)
{
    int i;
    BOOL unrecognized=NO;
    unsigned char *orgp = datap;
    BOOL readNumericParameter = NO;

    NSCParameterAssert(datap != NULL);
    NSCParameterAssert(datalen >= 2);
    NSCParameterAssert(param != NULL);

    param->count = 0;
    param->cmd = 0;
    for (i = 0; i < VT100CSIPARAM_MAX; ++i )
	param->p[i] = -1;

    NSCParameterAssert(datap[0] == ESC);
    NSCParameterAssert(datap[1] == '[');
    datap += 2;
    datalen -= 2;

    if (datalen > 0 && *datap == '?') {
	param->question = YES;
	datap ++;
	datalen --;
    }
    else
	param->question = NO;

    while (datalen > 0) {
		
	if (isdigit(*datap)) {
	    int n = *datap - '0';
            datap++;
	    datalen--;

	    while (datalen > 0 && isdigit(*datap)) {
		n = n * 10 + *datap - '0';

		datap++;
		datalen--;
	    }
	    //if (param->count == 0 )
		//param->count = 1;
	    //param->p[param->count - 1] = n;
	    if(param->count < VT100CSIPARAM_MAX)
		param->p[param->count] = n;
	    // increment the parameter count
	    param->count++;

	    // set the numeric parameter flag
	    readNumericParameter = YES;

	}
	else if (*datap == ';') {
	    datap++;
	    datalen--;

	    // If we got an implied (blank) parameter, increment the parameter count again
	    if(readNumericParameter == NO)
		param->count++;
	    // reset the parameter flag
	    readNumericParameter = NO;

	    if (param->count >= VT100CSIPARAM_MAX) {
		// broken
		//param->cmd = 0xff;
                unrecognized=YES;
		//break;
	    }
	}
	else if (isalpha(*datap)||*datap=='@') {
	    datalen--;
            param->cmd = unrecognized?0xff:*datap;
            datap++;
	    break;
	}
        else if (*datap=='\'') {
            datap++;
            datalen--;
            switch (*datap) {
                case 'z':
                case '|':
                case 'w':
                    NSLog(@"Unsupported locator sequence");
                    param->cmd=0xff;
                    datap++;
                    datalen--;
                    break;
                default:
                    NSLog(@"Unrecognized locator sequence");
                    datap++;
                    datalen--;
                    param->cmd=0xff;
                    break;
            }
            break;
        }
        else if (*datap=='&') {
            datap++;
            datalen--;
            switch (*datap) {
                case 'w':
                    NSLog(@"Unsupported locator sequence");
                    param->cmd=0xff;
                    datap++;
                    datalen--;
                    break;
                default:
                    NSLog(@"Unrecognized locator sequence");
                    datap++;
                    datalen--;
                    param->cmd=0xff;
                    break;
            }
            break;
        }
	else {
            switch (*datap) {
                case VT100CC_ENQ: break;
                case VT100CC_BEL: [SCREEN playBell]; break;
                case VT100CC_BS:  [SCREEN backSpace]; break;
                case VT100CC_HT:  [SCREEN setTab]; break;
                case VT100CC_LF:
                case VT100CC_VT:
                case VT100CC_FF:  [SCREEN setNewLine]; break;
                case VT100CC_CR:  [SCREEN cursorToX:1 Y:[SCREEN cursorY]]; break;
                case VT100CC_SO:  break;
                case VT100CC_SI:  break;
                case VT100CC_DC1: break;
                case VT100CC_DC3: break;
                case VT100CC_CAN:
                case VT100CC_SUB: break;
                case VT100CC_DEL: [SCREEN deleteCharacters:1];break;
                default: unrecognized=YES; break;
            }
            datalen--;
            datap++;
	}
    }
    return datap - orgp;
}

#define SET_PARAM_DEFAULT(pm,n,d) \
    (((pm).p[(n)] = (pm).p[(n)] < 0 ? (d):(pm).p[(n)]), \
     ((pm).count  = (pm).count > (n) + 1 ? (pm).count : (n) + 1 ))

static VT100TCC decode_csi(unsigned char *datap,
			   size_t datalen,
			   size_t *rmlen,VT100Screen *SCREEN)
{
    VT100TCC result;
    CSIParam param;
    size_t paramlen;
    int i;

    paramlen = getCSIParam(datap, datalen, &param, SCREEN);
    if (paramlen > 0 && param.cmd > 0) {
        if (!param.question) {
            switch (param.cmd) {
                case 'D':		// Cursor Backward
                    result.type = VT100CSI_CUB;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    break;

                case 'B':		// Cursor Down
                    result.type = VT100CSI_CUD;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    break;

                case 'C':		// Cursor Forward
                    result.type = VT100CSI_CUF;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    break;

                case 'A':		// Cursor Up
                    result.type = VT100CSI_CUU;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    break;

                case 'H':
                    result.type = VT100CSI_CUP;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    SET_PARAM_DEFAULT(param, 1, 1);
                    break;

                case 'c':
                    result.type = VT100CSI_DA;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                case 'q':
                    result.type = VT100CSI_DECLL;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                case 'x':
                    if (param.count == 1)
                        result.type = VT100CSI_DECREQTPARM;
                    else
                        result.type = VT100CSI_DECREPTPARM;
                    break;

                case 'r':
                    result.type = VT100CSI_DECSTBM;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    SET_PARAM_DEFAULT(param, 1, [SCREEN height]);
                    break;

                case 'y':
                    if (param.count == 2)
                        result.type = VT100CSI_DECTST;
                    else
		    {
			NSLog(@"1: Unknown token %c", param.cmd);
			result.type = VT100_NOTSUPPORT;
		    }
                    break;

                case 'n':
                    result.type = VT100CSI_DSR;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                case 'J':
                    result.type = VT100CSI_ED;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                case 'K':
                    result.type = VT100CSI_EL;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                case 'f':
                    result.type = VT100CSI_HVP;
                    SET_PARAM_DEFAULT(param, 0, 1);
                    SET_PARAM_DEFAULT(param, 1, 1);
                    break;

                case 'l':
                    result.type = VT100CSI_RM;
                    break;

                case 'm':
                    result.type = VT100CSI_SGR;
                    for (i = 0; i < param.count; ++i) {
                        SET_PARAM_DEFAULT(param, i, 0);
//                        NSLog(@"m[%d]=%d",i,param.p[i]);
                    }
                    break;

                case 'h':
                    result.type = VT100CSI_SM;
                    break;

                case 'g':
                    result.type = VT100CSI_TBC;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;

                    // these are xterm controls
                case '@':
                    result.type = XTERMCC_INSBLNK;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'L':
                    result.type = XTERMCC_INSLN;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'P':
                    result.type = XTERMCC_DELCH;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'M':
                    result.type = XTERMCC_DELLN;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;

		// ANSI
		case 'G':
		    result.type = ANSICSI_CHA;
		    SET_PARAM_DEFAULT(param,0,1);
		    break;
                case 'd':
                    result.type = ANSICSI_VPA;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'e':
                    result.type = ANSICSI_VPR;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
                case 'X':
                    result.type = ANSICSI_ECH;
                    SET_PARAM_DEFAULT(param,0,1);
                    break;
		case 'i':
		    result.type = ANSICSI_PRINT;
		    SET_PARAM_DEFAULT(param,0,0);
		    break;
                default:
		    NSLog(@"2: Unknown token (%c); %s", param.cmd, datap);
                    result.type = VT100_NOTSUPPORT;
                    break;
            }
        }
        else {
            switch (param.cmd) {
                case 'h':		// Dec private mode set
                    result.type = VT100CSI_DECSET;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;
                case 'l':		// Dec private mode reset
                    result.type = VT100CSI_DECRST;
                    SET_PARAM_DEFAULT(param, 0, 0);
                    break;
                default:
		    NSLog(@"3: Unknown token %c", param.cmd);
                    result.type = VT100_NOTSUPPORT;
                    break;
                    
            }       
        }
	
	// copy CSI parameter
	for (i = 0; i < VT100CSIPARAM_MAX; ++i)
	    result.u.csi.p[i] = param.p[i];
	result.u.csi.count = param.count;
	result.u.csi.question = param.question;

	*rmlen = paramlen;
    }
    else {
	result.type = VT100_WAIT;
    }
    return result;
}


static VT100TCC decode_xterm(unsigned char *datap,
                             size_t datalen,
                             size_t *rmlen,
                             NSStringEncoding enc)
{
    int mode=0;
    VT100TCC result;
    NSData *data;
    BOOL unrecognized=NO;
    char s[100]={0}, *c=nil;

    NSCParameterAssert(datap != NULL);
    NSCParameterAssert(datalen >= 2);
    NSCParameterAssert(datap[0] == ESC);
    NSCParameterAssert(datap[1] == ']');
    datap += 2;
    datalen -= 2;
    *rmlen=2;
    
    while (isdigit(*datap)) {
        int n = *datap++ - '0';
        datalen--;
        (*rmlen)++;
        while (datalen > 0 && isdigit(*datap)) {
            n = n * 10 + *datap - '0';

            (*rmlen)++;
            datap++;
            datalen--;
        }
        mode=n;
    }
    if (datalen>0) {
        if (*datap != ';') {
            unrecognized=YES;
        }
        else {
            c=s;
            datalen--;
            datap++;
            (*rmlen)++;
            while (*datap!=0x007&&c-s<100&&datalen>0) {
                *c=*datap;
                datalen--;
                datap++;
                (*rmlen)++;
                c++;
            }
            if (*datap!=0x007) {
                if (datalen>0) unrecognized=YES;
                else {
                    *rmlen=0;
                }
            }
            else {
                *datap++;
                datalen--;
                (*rmlen)++;
            }
        }
    }
    else {
        *rmlen=0;
    }

    if (unrecognized||!(*rmlen)) {
        result.type = VT100_WAIT;
        NSLog(@"invalid: %d",*rmlen);
    }
    else {
        data = [NSData dataWithBytes:s length:c-s];
        result.u.string = [[[NSString alloc] initWithData:data
                                                 encoding:enc] autorelease];
	switch (mode) {
            case 0:
               result.type = XTERMCC_WINICON_TITLE;
		break;
            case 1:
               result.type = XTERMCC_ICON_TITLE;
		break;
            case 2:
            default:
                result.type = XTERMCC_WIN_TITLE;
		break;
        }
//        NSLog(@"result: %d[%@],%d",result.type,result.u.string,*rmlen);
    }

    return result;
}

static VT100TCC decode_other(unsigned char *datap,
			     size_t datalen,
			     size_t *rmlen)
{
    VT100TCC result;
    int c1, c2, c3;

    NSCParameterAssert(datap[0] == ESC);
    NSCParameterAssert(datalen > 1);

    c1 = (datalen >= 2 ? datap[1]: -1);
    c2 = (datalen >= 3 ? datap[2]: -1);
    c3 = (datalen >= 4 ? datap[3]: -1);

    switch (c1) {
    case '#':  
	if (c2 < 0) {
	    result.type = VT100_WAIT;
	}
	else {
            switch (c2) {
                case '8': result.type=VT100CSI_DECALN; break;
                default:
		    NSLog(@"4: Unknown token %c", c2);
                    result.type = VT100_NOTSUPPORT;
            }
	    *rmlen = 3;
	}
	break;

    case '=':
	result.type = VT100CSI_DECKPAM;
	*rmlen = 2;
	break;

    case '>':
	result.type = VT100CSI_DECKPNM;
	*rmlen = 2;
	break;

    case '<':
	result.type = STRICT_ANSI_MODE;
	*rmlen = 2;
	break;

    case '(':
        if (c2 < 0) {
            result.type = VT100_WAIT;
        }
        else {
            result.type = VT100CSI_SCS0;
            result.u.code=c2;
            *rmlen = 3;
        }
        break;
    case ')':
        if (c2 < 0) {
            result.type = VT100_WAIT;
        }
        else {
            result.type = VT100CSI_SCS1;
            result.u.code=c2;
            *rmlen = 3;
        }
        break;
    case '*':
        if (c2 < 0) {
            result.type = VT100_WAIT;
        }
        else {
            result.type = VT100CSI_SCS2;
            result.u.code=c2;
            *rmlen = 3;
        }
        break;
    case '+':
	if (c2 < 0) {
	    result.type = VT100_WAIT;
	}
	else {
	    result.type = VT100CSI_SCS3;
            result.u.code=c2;
	    *rmlen = 3;
	}
	break;

    case '8':
	result.type = VT100CSI_DECRC;
	*rmlen = 2;
	break;

    case '7':
	result.type = VT100CSI_DECSC;
        *rmlen = 2;
	break;

    case 'D':
	result.type = VT100CSI_IND;
	*rmlen = 2;
	break;

    case 'E':
	result.type = VT100CSI_NEL;
	*rmlen = 2;
	break;

    case 'H':
	result.type = VT100CSI_HTS;
	*rmlen = 2;
	break;

    case 'M':
	result.type = VT100CSI_RI;
	*rmlen = 2;
	break;

    case 'Z': 
	result.type = VT100CSI_DECID;
	*rmlen = 2;
	break;

    case 'c':
	result.type = VT100CSI_RIS;
	*rmlen = 2;
	break;

    default:
	NSLog(@"5: Unknown token %c(%x)", c1, c1);
	result.type = VT100_NOTSUPPORT;
	*rmlen = 2;
	break;
    }

    return result;
}

static VT100TCC decode_control(unsigned char *datap,
			       size_t datalen,
			       size_t *rmlen,
                               NSStringEncoding enc, VT100Screen *SCREEN)
{
    VT100TCC result;

    if (isCSI(datap, datalen)) {
	result = decode_csi(datap, datalen, rmlen, SCREEN);
    }
    else if (isXTERM(datap,datalen)) {
        result = decode_xterm(datap,datalen,rmlen,enc);
    }
    else {
	NSCParameterAssert(datalen > 0);

	switch ( *datap ) {
	case VT100CC_NULL:
	    result.type = VT100_SKIP;
	    *rmlen = 0;
	    while (datalen > 0 && *datap == '\0') {
		++datap;
		--datalen;
		++ *rmlen;
	    }
	    break;

	case VT100CC_ESC:
	    if (datalen == 1) {
		result.type = VT100_WAIT;
	    }
	    else {
		result = decode_other(datap, datalen, rmlen);
	    }
	    break;

	default:
	    result.type = *datap;
	    *rmlen = 1;
	    break;
	}
    }
    return result;
}

static VT100TCC decode_ascii(unsigned char *datap,
                             size_t datalen,
                             size_t *rmlen)
{
    unsigned char *last = datap;
    size_t len = datalen;
    VT100TCC result;
    
    while (len > 0 && *last >= 0x20 && *last <= 0x7f) {
        ++last;
        --len;
    }
    *rmlen = datalen - len;
    result.type = VT100_ASCIISTRING;
    result.u.string = [NSString stringWithCString:datap length:*rmlen];
    return result;
}

static int utf8_reqbyte(unsigned char f)
{
    int result;

    if (isascii(f))
        result = 1;
    else if ((f & 0xe0) == 0xc0)
        result = 2;
    else if ((f & 0xf0) == 0xe0)
        result = 3;
    else if ((f & 0xf8) == 0xf0)
        result = 4;
    else if ((f & 0xfc) == 0xf8)
        result = 5;
    else if ((f & 0xfe) == 0xfc)
        result = 6;
    else
        result = 0;

    return result;
}

static VT100TCC decode_utf8(unsigned char *datap,
                            size_t datalen ,
                            size_t *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    size_t len = datalen;
    int reqbyte;

    while (len > 0) {
        if (*p>=0x80) {
            reqbyte = utf8_reqbyte(*datap);
            if (reqbyte > 0) {
                if (len >= reqbyte) {
                p += reqbyte;
                len -= reqbyte;
                }
                else break;
            }
            else {
                *p=UNKNOWN;
                p++;
                len--;
            }
        }
        else break;
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    }
    else {
        *rmlen = datalen - len;
        result.type = VT100_STRING;
    }

   return result;
 
  
}


static VT100TCC decode_euccn(unsigned char *datap,
			     size_t datalen,
			     size_t *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    size_t len = datalen;


    while (len > 0) {
        if (iseuccn(*p)&&len>1) {
            if ((*(p+1)>=0x40&&*(p+1)<=0x7e)||*(p+1)>=0x80&&*(p+1)<=0xfe) {
                p += 2;
                len -= 2;
            }
            else {
                *p=UNKNOWN;
                p++;
                len--;
            }
        }
        else break;
    }
    if (len == datalen) {
	*rmlen = 0;
	result.type = VT100_WAIT;
    }
    else {
	*rmlen = datalen - len;
	result.type = VT100_STRING;
    }

    return result;
}

static VT100TCC decode_big5(unsigned char *datap,
			    size_t datalen,
			    size_t *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    size_t len = datalen;
    
    while (len > 0) {
        if (isbig5(*p)&&len>1) {
            if ((*(p+1)>=0x40&&*(p+1)<=0x7e)||*(p+1)>=0xa1&&*(p+1)<=0xfe) {
                p += 2;
                len -= 2;
            }
            else {
                *p=UNKNOWN;
                p++;
                len--;
            }
        }
        else break;
    }
    if (len == datalen) {
	*rmlen = 0;
	result.type = VT100_WAIT;
    }
    else {
	*rmlen = datalen - len;
	result.type = VT100_STRING;
    }

    return result;
}

static VT100TCC decode_euc_jp(unsigned char *datap,
                                   size_t datalen ,
                                   size_t *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    size_t len = datalen;

    while (len > 0) {
        if  (len > 1 && *p == 0x8e) {
                p += 2;
                len -= 2;
        }
        else if (len > 2  && *p == 0x8f ) {
            p += 3;
            len -= 3;
        }
        else if (len > 1 && *p >= 0xa1 && *p <= 0xfe ) {
            p += 2;
            len -= 2;
        }
        else break;
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    }
    else {
        *rmlen = datalen - len;
        result.type = VT100_STRING;
    }

    return result;
}


static VT100TCC decode_sjis(unsigned char *datap,
                                  size_t datalen ,
                                  size_t *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    size_t len = datalen;

    while (len > 0) {
        if (issjiskanji(*p)&&len>1) {
            p += 2;
            len -= 2;
        }
        else if (*p>=0x80) {
            p++;
            len--;
        }
        else break;
    }

    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    }
    else {
        *rmlen = datalen - len;
        result.type = VT100_STRING;
    }

    return result;
}


static VT100TCC decode_euckr(unsigned char *datap,
                             size_t datalen,
                             size_t *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    size_t len = datalen;

    while (len > 0) {
        if (iseuckr(*p)&&len>1) {
                p += 2;
                len -= 2;
        }
        else break;
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    }
    else {
        *rmlen = datalen - len;
        result.type = VT100_STRING;
    }

    return result;
}

static VT100TCC decode_other_enc(unsigned char *datap,
                             size_t datalen,
                             size_t *rmlen)
{
    VT100TCC result;
    unsigned char *p = datap;
    size_t len = datalen;

    while (len > 0) {
        if (*p>0x7f) {
            p++;
            len--;
        }
        else break;
    }
    if (len == datalen) {
        *rmlen = 0;
        result.type = VT100_WAIT;
    }
    else {
        *rmlen = datalen - len;
        result.type = VT100_STRING;
    }

    return result;
}

static VT100TCC decode_string(unsigned char *datap,
                              size_t datalen,
                              size_t *rmlen,
			     NSStringEncoding encoding)
{
    VT100TCC result;
    NSData *data;

    *rmlen = 1;
    result.type = VT100_UNKNOWNCHAR;
    result.u.code = datap[0];

//    NSLog(@"data: %@",[NSData dataWithBytes:datap length:datalen]);
    if (encoding == NSUTF8StringEncoding) {
        result = decode_utf8(datap, datalen, rmlen);
    }
    else if (isGBEncoding(encoding)) {
//        NSLog(@"Chinese-GB!");
        result = decode_euccn(datap, datalen, rmlen);
    }
    else if (isBig5Encoding(encoding)) {
        result = decode_big5(datap, datalen, rmlen);
    }
    else if (isJPEncoding(encoding)) {
//        NSLog(@"decoding euc-jp");
        result = decode_euc_jp(datap, datalen, rmlen);
    }
    else if (isSJISEncoding(encoding)) {
//        NSLog(@"decoding j-jis");
        result = decode_sjis(datap, datalen, rmlen);
    }
    else if (isKREncoding(encoding)) {
//        NSLog(@"decoding korean");
        result = decode_euckr(datap, datalen, rmlen);
    }
    else {
//        NSLog(@"%s(%d):decode_string()-support character encoding(%@d)",
//              __FILE__, __LINE__, [NSString localizedNameOfStringEncoding:encoding]);
        result = decode_other_enc(datap, datalen, rmlen);
    }

    if (result.type != VT100_WAIT) {
        data = [NSData dataWithBytes:datap length:*rmlen];
        result.u.string = [[[NSString alloc]
                                   initWithData:data
                                       encoding:encoding]
            autorelease];

        if (result.u.string==nil) {
            int i;
            NSLog(@"Null:%@",data);
            for(i=0;i<*rmlen;i++) datap[i]=UNKNOWN;
            result.u.string = [[NSString alloc] initWithCString:datap length:*rmlen];
        }
    }
    return result;
}

+ (void)initialize
{
}

- (id)init
{

#if DEBUG_ALLOC
    NSLog(@"%s(%d):-[VT100Terminal init 0x%x]", __FILE__, __LINE__, self);
#endif
    
    if ([super init] == nil)
	return nil;

    ENCODING = NSASCIIStringEncoding;
    STREAM   = [[NSMutableData alloc] init];
    
  

    LINE_MODE = NO;
    CURSOR_MODE = NO;
    COLUMN_MODE = NO;
    SCROLL_MODE = NO;
    SCREEN_MODE = NO;
    ORIGIN_MODE = NO;
    WRAPAROUND_MODE = YES;
    AUTOREPEAT_MODE = NO;
    INTERLACE_MODE = NO;
    KEYPAD_MODE = NO;
    INSERT_MODE = NO;
    saveCHARSET=CHARSET = NO;
    XON = YES;
    bold=blink=reversed=under=0;
    saveBold=saveBlink=saveReversed=saveUnder = 0;
    FG_COLORCODE = DEFAULT_FG_COLOR_CODE;
    BG_COLORCODE = DEFAULT_BG_COLOR_CODE;
    
    TRACE = NO;

    strictAnsiMode = NO;
    allowColumnMode = NO;
    printToAnsi = NO;
    pipeFile = NULL;

    defaultCharacterAttributeDictionary[0] = [[NSMutableDictionary alloc] init];
    defaultCharacterAttributeDictionary[1] = [[NSMutableDictionary alloc] init];
    characterAttributeDictionary[0] = [[NSMutableDictionary alloc] init];
    characterAttributeDictionary[1] = [[NSMutableDictionary alloc] init];
    streamOffset = 0;

    numLock = YES;
    
    return self;
}

- (void)dealloc
{
#if DEBUG_ALLOC
    NSLog(@"%s(%d):-[VT100Terminal dealloc 0x%x]", __FILE__, __LINE__, self);
#endif
    
    int i;
    
    if(STREAM != nil)
	[STREAM release];

    for(i=0;i<8;i++) {
        [colorTable[0][i] release];
        [colorTable[1][i] release];
    }
    [characterAttributeDictionary[0] release];
    [characterAttributeDictionary[1] release];
    [defaultCharacterAttributeDictionary[0] release];
    [defaultCharacterAttributeDictionary[1] release];
    
    [super dealloc];
}

- (BOOL)trace
{
    return TRACE;
}

- (void)setTrace:(BOOL)flag
{
    TRACE = flag;
}

- (BOOL)strictAnsiMode
{
    return (strictAnsiMode);
}

- (void)setStrictAnsiMode: (BOOL)flag
{
    strictAnsiMode = flag;
}

- (BOOL)allowColumnMode
{
    return (allowColumnMode);
}

- (void)setAllowColumnMode: (BOOL)flag
{
    allowColumnMode = flag;
}

- (BOOL)printToAnsi
{
    return (printToAnsi);
}

- (void)setPrintToAnsi: (BOOL)flag
{

    if(flag == NO)
    {
	//NSLog(@"Turning off printer...");
	if(pipeFile != NULL)
	{
	    pclose(pipeFile);
	}
	pipeFile = NULL;	
    }
    else
    {
	//NSLog(@"Turning on printer...");
	if(pipeFile != NULL)
	{
	    pclose(pipeFile);
	}
	pipeFile = popen("/usr/bin/lpr", "w");	
    }
    
    printToAnsi = flag;

}

- (NSStringEncoding)encoding
{
    return ENCODING;
}

- (void)setEncoding:(NSStringEncoding)encoding
{
    ENCODING = encoding;
}

- (void)cleanStream
{
    [STREAM autorelease];
    STREAM = [[NSMutableData data] retain];
}

- (void)putStreamData:(NSData *)data
{
    if([STREAM length] == 0)
	streamOffset = 0;
    [STREAM appendData:data];
}

- (VT100TCC)getNextToken
{
    unsigned char *datap;
    size_t datalen;
    VT100TCC result;

#if 0
    NSLog(@"buffer data = %@", STREAM);
#endif

    // get our current position in the stream
    datap = (unsigned char *)[STREAM bytes] + streamOffset;
    datalen = (size_t)[STREAM length] - streamOffset;

    if (datalen == 0) {
	result.type = VT100CC_NULL;
	result.length = 0;
	// We are done with this stream. Get rid of it and allocate a new one
	// to avoid allowing this to grow too big.
	streamOffset = 0;
	[STREAM release];
	STREAM = nil;
	STREAM = [[NSMutableData alloc] init];	
    }
    else {
	size_t rmlen = 0;

	if (iscontrol(datap[0])) {
	    result = decode_control(datap, datalen, &rmlen, ENCODING, SCREEN);
	}
	else {
            if (isascii(*datap)) {
                result = decode_ascii(datap, datalen, &rmlen);
            }
            else if (isString(datap,ENCODING)) {
		result = decode_string(datap, datalen, &rmlen, ENCODING);
                if(result.type != VT100_WAIT && rmlen == 0) {
                    result.type = VT100_UNKNOWNCHAR;
                    result.u.code = datap[0];
                    rmlen = 1;
                }
	    }
	    else {
		result.type = VT100_UNKNOWNCHAR;
		result.u.code = datap[0];
		rmlen = 1;
	    }
	}
	
	result.length = rmlen;
	result.position = datap;

	if (rmlen > 0) {
	    NSParameterAssert(datalen - rmlen >= 0);
	    if (TRACE && result.type == VT100_UNKNOWNCHAR) {
//		NSLog(@"INPUT-BUFFER %@, read %d byte, type %d", 
//                      STREAM, rmlen, result.type);
	    }

	    // mark our current position in the stream
	    streamOffset += rmlen;
	}
    }

    [self _setMode:result];
    [self _setCharAttr:result];

    return result;
}

- (void) printToken: (VT100TCC) token
{
    //NSLog(@"Printing token at 0x%x; length = %d", token.position, token.length);
    if(pipeFile != NULL)
	fwrite(token.position, token.length, 1, pipeFile);
}

- (NSData *)keyArrowUp:(unsigned int)modflag
{
    int mod=0;
    static char buf[20];

    if ((modflag&NSControlKeyMask) && (modflag&NSShiftKeyMask)) mod=6;
    else if (modflag&NSControlKeyMask) mod=5;
    else if (modflag&NSShiftKeyMask) mod=2;
    if (mod) {
        sprintf(buf,CURSOR_MOD_UP,mod);
        return [NSData dataWithBytes:buf length:strlen(buf)];
    }
    else {
        if (CURSOR_MODE)
            return [NSData dataWithBytes:CURSOR_SET_UP
                                                       length:conststr_sizeof(CURSOR_SET_UP)];
        else
            return [NSData dataWithBytes:CURSOR_RESET_UP
                                                       length:conststr_sizeof(CURSOR_RESET_UP)];
    }
}

- (NSData *)keyArrowDown:(unsigned int)modflag
{
    int mod=0;
    static char buf[20];

    if ((modflag&NSControlKeyMask) && (modflag&NSShiftKeyMask)) mod=6;
    else if (modflag&NSControlKeyMask) mod=5;
    else if (modflag&NSShiftKeyMask) mod=2;
    if (mod) {
        sprintf(buf,CURSOR_MOD_DOWN,mod);
        return [NSData dataWithBytes:buf length:strlen(buf)];
    }
    else {
        if (CURSOR_MODE)
            return [NSData dataWithBytes:CURSOR_SET_DOWN
                                  length:conststr_sizeof(CURSOR_SET_DOWN)];
        else
            return [NSData dataWithBytes:CURSOR_RESET_DOWN
                                  length:conststr_sizeof(CURSOR_RESET_DOWN)];
    }
}

- (NSData *)keyArrowLeft:(unsigned int)modflag
{
    int mod=0;
    static char buf[20];

    if ((modflag&NSControlKeyMask) && (modflag&NSShiftKeyMask)) mod=6;
    else if (modflag&NSControlKeyMask) mod=5;
    else if (modflag&NSShiftKeyMask) mod=2;
    if (mod) {
        sprintf(buf,CURSOR_MOD_LEFT,mod);
        return [NSData dataWithBytes:buf length:strlen(buf)];
    }
    else {
        if (CURSOR_MODE)
            return [NSData dataWithBytes:CURSOR_SET_LEFT
                                                       length:conststr_sizeof(CURSOR_SET_LEFT)];
        else
            return [NSData dataWithBytes:CURSOR_RESET_LEFT
                                                       length:conststr_sizeof(CURSOR_RESET_LEFT)];
    }
}

- (NSData *)keyArrowRight:(unsigned int)modflag
{
    int mod=0;
    static char buf[20];

    if ((modflag&NSControlKeyMask) && (modflag&NSShiftKeyMask)) mod=6;
    else if (modflag&NSControlKeyMask) mod=5;
    else if (modflag&NSShiftKeyMask) mod=2;
    if (mod) {
        sprintf(buf,CURSOR_MOD_RIGHT,mod);
        return [NSData dataWithBytes:buf length:strlen(buf)];
    }
    else {
        if (CURSOR_MODE)
            return [NSData dataWithBytes:CURSOR_SET_RIGHT
                                                       length:conststr_sizeof(CURSOR_SET_RIGHT)];
        else
            return [NSData dataWithBytes:CURSOR_RESET_RIGHT
                                                       length:conststr_sizeof(CURSOR_RESET_RIGHT)];
    }
}

- (NSData *)keyInsert
{
    return [NSData dataWithBytes:KEY_INSERT length:conststr_sizeof(KEY_INSERT)];
}

- (NSData *)keyHome
{
    return [NSData dataWithBytes:KEY_HOME length:conststr_sizeof(KEY_HOME)];
}

- (NSData *)keyDelete
{
    //    unsigned char del = 0x7f;
    //    return [NSData dataWithBytes:&del length:1];
    return [NSData dataWithBytes:KEY_DEL length:conststr_sizeof(KEY_DEL)];
}

- (NSData *)keyBackspace
{
    return [NSData dataWithBytes:KEY_BACKSPACE length:conststr_sizeof(KEY_BACKSPACE)];
}

- (NSData *)keyEnd
{
    return [NSData dataWithBytes:KEY_END length:conststr_sizeof(KEY_END)];
}

- (NSData *)keyPageUp
{
    return [NSData dataWithBytes:KEY_PAGE_UP
                                        length:conststr_sizeof(KEY_PAGE_UP)];
}

- (NSData *)keyPageDown
{
    return [NSData dataWithBytes:KEY_PAGE_DOWN 
		   length:conststr_sizeof(KEY_PAGE_DOWN)];
}

- (NSData *)keyFunction:(int)no
{
    char str[256];
    size_t len;

    if (no < 7) {
	sprintf(str, KEY_FUNCTION_FORMAT, no + 10);
    }
    else if (no < 11)
	sprintf(str, KEY_FUNCTION_FORMAT, no + 11);
    else
        sprintf(str, KEY_FUNCTION_FORMAT, no + 12);

    len = strlen(str);
    return [NSData dataWithBytes:str length:len];
}

- (NSData *)keyPFn: (int) n
{
    NSData *theData;
    
    switch (n)
    {
	case 4:
	    theData = [NSData dataWithBytes:KEY_PF4 length:conststr_sizeof(KEY_PF4)];
	    break;
	case 3:
	    theData = [NSData dataWithBytes:KEY_PF3 length:conststr_sizeof(KEY_PF3)];
	    break;
	case 2:
	    theData = [NSData dataWithBytes:KEY_PF2 length:conststr_sizeof(KEY_PF2)];
	    break;
	case 1:
	default:
	    theData = [NSData dataWithBytes:KEY_PF1 length:conststr_sizeof(KEY_PF1)];
	    break;
    }

    return (theData);
}

- (void) toggleNumLock
{
    numLock = !numLock;
}

- (BOOL) numLock
{
    return (numLock);
}

- (NSData *) keypadData: (unichar) unicode keystr: (NSString *) keystr
{
    NSData *theData = nil;

    // numeric keypad mode
    if(![self keypadMode])
	return ([keystr dataUsingEncoding:NSUTF8StringEncoding]);

    // alternate keypad mode
    switch (unicode)
    {
	case '0':
	    theData = [NSData dataWithBytes:ALT_KP_0 length:conststr_sizeof(ALT_KP_0)];
	    break;
	case '1':
	    theData = [NSData dataWithBytes:ALT_KP_1 length:conststr_sizeof(ALT_KP_1)];
	    break;
	case '2':
	    theData = [NSData dataWithBytes:ALT_KP_2 length:conststr_sizeof(ALT_KP_2)];
	    break;
	case '3':
	    theData = [NSData dataWithBytes:ALT_KP_3 length:conststr_sizeof(ALT_KP_3)];
	    break;
	case '4':
	    theData = [NSData dataWithBytes:ALT_KP_4 length:conststr_sizeof(ALT_KP_4)];
	    break;
	case '5':
	    theData = [NSData dataWithBytes:ALT_KP_5 length:conststr_sizeof(ALT_KP_5)];
	    break;
	case '6':
	    theData = [NSData dataWithBytes:ALT_KP_6 length:conststr_sizeof(ALT_KP_6)];
	    break;
	case '7':
	    theData = [NSData dataWithBytes:ALT_KP_7 length:conststr_sizeof(ALT_KP_7)];
	    break;
	case '8':
	    theData = [NSData dataWithBytes:ALT_KP_8 length:conststr_sizeof(ALT_KP_8)];
	    break;
	case '9':
	    theData = [NSData dataWithBytes:ALT_KP_9 length:conststr_sizeof(ALT_KP_9)];
	    break;
	case '-':
	    theData = [NSData dataWithBytes:ALT_KP_MINUS length:conststr_sizeof(ALT_KP_MINUS)];
	    break;
	case '+':
	    theData = [NSData dataWithBytes:ALT_KP_PLUS length:conststr_sizeof(ALT_KP_PLUS)];
	    break;	    
	case '.':
	    theData = [NSData dataWithBytes:ALT_KP_PERIOD length:conststr_sizeof(ALT_KP_PERIOD)];
	    break;	    
	case 0x03:
	    theData = [NSData dataWithBytes:ALT_KP_ENTER length:conststr_sizeof(ALT_KP_ENTER)];
	    break;
    }

    return (theData);
}

- (BOOL)lineMode
{
    return LINE_MODE;
}

- (BOOL)cursorMode
{
    return CURSOR_MODE;
}

- (BOOL)columnMode
{
    return COLUMN_MODE;
}

- (BOOL)scrollMode
{
    return SCROLL_MODE;
}

- (BOOL)screenMode
{
    return SCREEN_MODE;
}

- (BOOL)originMode
{
    return ORIGIN_MODE;
}

- (BOOL)wraparoundMode
{
    return WRAPAROUND_MODE;
}

- (BOOL)autorepeatMode
{
    return AUTOREPEAT_MODE;
}

- (BOOL)interlaceMode
{
    return INTERLACE_MODE;
}

- (BOOL)keypadMode
{
    return KEYPAD_MODE;
}

- (BOOL)insertMode
{
    return INSERT_MODE;
}

- (BOOL) xon
{
    return XON;
}

- (int) charset
{
    return CHARSET;
}

- (int)foregroundColorCode
{
    return FG_COLORCODE;
}

- (int)backgroundColorCode
{
    return BG_COLORCODE;
}

- (NSData *)reportActivePositionWithX:(int)x Y:(int)y
{
    char buf[64];

    snprintf(buf, sizeof(buf), REPORT_POSITION, y, x);

    return [NSData dataWithBytes:buf length:strlen(buf)];
}

- (NSData *)reportStatus
{
    return [NSData dataWithBytes:REPORT_STATUS
			  length:conststr_sizeof(REPORT_STATUS)];
}

- (NSData *)reportDeviceAttribute
{
    return [NSData dataWithBytes:REPORT_WHATAREYOU
			  length:conststr_sizeof(REPORT_WHATAREYOU)];
}

- (NSMutableDictionary *)characterAttributeDictionary:(BOOL) asc
{
    return(characterAttributeDictionary[asc?0:1]);
}

- (NSMutableDictionary *)defaultCharacterAttributeDictionary: (BOOL) asc
{
    return (defaultCharacterAttributeDictionary[asc?0:1]);
}

- (void) initDefaultCharacterAttributeDictionary
{

    NSColor *fg, *bg;
    NSMutableParagraphStyle *pstyle=[[NSMutableParagraphStyle alloc] init];

    [pstyle setLineBreakMode:NSLineBreakByClipping];
    [pstyle setParagraphSpacing:0];
    [pstyle setLineSpacing:0];
    fg = [self defaultFGColor];
    bg = [self defaultBGColor];

    [characterAttributeDictionary[0] setObject:fg
                                        forKey:NSForegroundColorAttributeName];
    [characterAttributeDictionary[0] removeObjectForKey:NSBackgroundColorAttributeName];
    [characterAttributeDictionary[0] setObject:[SCREEN font] forKey:NSFontAttributeName];
    [characterAttributeDictionary[0] setObject:[NSNumber numberWithInt:(1)]
                                        forKey:@"NSCharWidthAttributeName"];
    [characterAttributeDictionary[0] setObject:pstyle
                                        forKey:NSParagraphStyleAttributeName];
    [characterAttributeDictionary[1] setObject:fg
                                        forKey:NSForegroundColorAttributeName];
    [characterAttributeDictionary[1] removeObjectForKey:NSBackgroundColorAttributeName];
    [characterAttributeDictionary[1] setObject:[SCREEN nafont] forKey:NSFontAttributeName];
    [characterAttributeDictionary[1] setObject:[NSNumber numberWithInt:(2)]
                                        forKey:@"NSCharWidthAttributeName"];
    [characterAttributeDictionary[1] setObject:pstyle
                                        forKey:NSParagraphStyleAttributeName];
    [defaultCharacterAttributeDictionary[0] setObject:fg
                                                                    forKey:NSForegroundColorAttributeName];
    [defaultCharacterAttributeDictionary[0] removeObjectForKey:NSBackgroundColorAttributeName];
    [defaultCharacterAttributeDictionary[0] setObject:[SCREEN font] forKey:NSFontAttributeName];
    [defaultCharacterAttributeDictionary[0] setObject:[NSNumber numberWithInt:(1)]
                                               forKey:@"NSCharWidthAttributeName"];
    [defaultCharacterAttributeDictionary[0] setObject:pstyle
                                               forKey:NSParagraphStyleAttributeName];
    [defaultCharacterAttributeDictionary[1] setObject:fg
                                               forKey:NSForegroundColorAttributeName];
    [defaultCharacterAttributeDictionary[1] removeObjectForKey:NSBackgroundColorAttributeName];
    [defaultCharacterAttributeDictionary[1] setObject:[SCREEN nafont] forKey:NSFontAttributeName];
    [defaultCharacterAttributeDictionary[1] setObject:[NSNumber numberWithInt:(2)]
                                               forKey:@"NSCharWidthAttributeName"];
    [defaultCharacterAttributeDictionary[1] setObject:pstyle
                                               forKey:NSParagraphStyleAttributeName];
}

- (void)_setMode:(VT100TCC)token
{
    BOOL mode;
    NSColor *fg, *bg;
    
    switch (token.type) {
        case VT100CSI_DECSET:
        case VT100CSI_DECRST:
            mode=(token.type == VT100CSI_DECSET);

            switch (token.u.csi.p[0]) {
                case 20: LINE_MODE = mode; break;
                case 1:  CURSOR_MODE = mode; break;
                case 2:  ANSI_MODE = mode; break;
                case 3:  COLUMN_MODE = mode; break;
                case 4:  SCROLL_MODE = mode; break;
                case 5:
                    SCREEN_MODE = mode;
                    if (mode) {
                        bg=[self defaultFGColor];
                        fg=[self defaultBGColor];
                    }else {
                        fg=[self defaultFGColor];
                        bg=[self defaultBGColor];
                    }

		    bg = [bg colorWithAlphaComponent: [defaultBGColor alphaComponent]];
		    fg = [fg colorWithAlphaComponent: [defaultFGColor alphaComponent]];
                        
                    [defaultCharacterAttributeDictionary[0] setObject:fg
                                                               forKey:NSForegroundColorAttributeName];
                    [defaultCharacterAttributeDictionary[1] setObject:fg
                                                               forKey:NSForegroundColorAttributeName];
                    [defaultCharacterAttributeDictionary[0] setObject:bg
                                                               forKey:NSBackgroundColorAttributeName];
                    [defaultCharacterAttributeDictionary[1] setObject:bg
                                                               forKey:NSBackgroundColorAttributeName];
                    [characterAttributeDictionary[0] setObject:fg
                                                               forKey:NSForegroundColorAttributeName];
                    [characterAttributeDictionary[1] setObject:fg
                                                               forKey:NSForegroundColorAttributeName];
                    [characterAttributeDictionary[0] setObject:bg
                                                               forKey:NSBackgroundColorAttributeName];
                    [characterAttributeDictionary[1] setObject:bg
                                                               forKey:NSBackgroundColorAttributeName];
                    [SCREEN setScreenAttributes];
                    break;
                case 6:  ORIGIN_MODE = mode; break;
                case 7:  WRAPAROUND_MODE = mode; break;
                case 8:  AUTOREPEAT_MODE = mode; break;
                case 9:  INTERLACE_MODE  = mode; break;
		case 40: allowColumnMode = mode; break;
            }
            break;
        case VT100CSI_SM:
        case VT100CSI_RM:
            mode=(token.type == VT100CSI_SM);

            switch (token.u.csi.p[0]) {
                case 4:
                    INSERT_MODE = mode; break;
            }
            break;
        case VT100CSI_DECKPAM:
            KEYPAD_MODE = YES;
            break;
        case VT100CSI_DECKPNM:
            KEYPAD_MODE = NO;
            break;
        case VT100CC_SI:
            CHARSET = 0;
            break;
        case VT100CC_SO:
            CHARSET = 1;
            break;
        case VT100CC_DC1:
            XON = YES;
            break;
        case VT100CC_DC3:
            XON = NO;
            break;
        case VT100CSI_DECRC:
            bold=saveBold;
            under=saveUnder;
            blink=saveBlink;
            reversed=saveReversed;
            CHARSET=saveCHARSET;
            [self setCharacterAttributeDictionary];
            break;
        case VT100CSI_DECSC:
            saveBold=bold;
            saveUnder=under;
            saveBlink=blink;
            saveReversed=reversed;
            [self setCharacterAttributeDictionary];
            saveCHARSET=CHARSET;
            break;
    }
}

- (void) setCharacterAttributeDictionary
{
    NSMutableDictionary *dic;
    NSColor *fg, *bg;
    int i;
    float alpha;

    fg = [self colorFromTable:FG_COLORCODE bold:bold];
    bg = [self colorFromTable:BG_COLORCODE bold:NO];

    alpha = [defaultBGColor alphaComponent];

    for(i=0;i<2;i++) {
        dic=characterAttributeDictionary[i];
        if (reversed) {
	    if (alpha<0.99)
		fg=[fg colorWithAlphaComponent:alpha];
            [dic setObject:bg forKey:NSForegroundColorAttributeName];
            [dic setObject:fg forKey:NSBackgroundColorAttributeName];
        }
        else {
            [dic setObject:fg forKey:NSForegroundColorAttributeName];
            if (BG_COLORCODE!=DEFAULT_BG_COLOR_CODE)
	    {
		if (alpha<0.99)
		    bg=[bg colorWithAlphaComponent:alpha];
		[dic setObject:bg forKey:NSBackgroundColorAttributeName];
	    }
            else [dic removeObjectForKey:NSBackgroundColorAttributeName];
        }

        [dic setObject:[NSNumber numberWithInt:under]
                forKey:NSUnderlineStyleAttributeName];
        [dic setObject:[NSNumber numberWithInt:blink]
                forKey:NSBlinkAttributeName];
    }

}

- (void)_setCharAttr:(VT100TCC)token
{
    if (token.type == VT100CSI_SGR) {

        if (token.u.csi.count == 0) {
            // all attribute off
            bold=under=blink=reversed=0;      
	    FG_COLORCODE = DEFAULT_FG_COLOR_CODE;
	    BG_COLORCODE = DEFAULT_BG_COLOR_CODE; 
        }
        else {
            int i;
            for (i = 0; i < token.u.csi.count; ++i) {
                int n = token.u.csi.p[i];
                switch (n) {
                case VT100CHARATTR_ALLOFF:
                    // all attribute off
                    bold=under=blink=reversed=0;
                    FG_COLORCODE = DEFAULT_FG_COLOR_CODE;
		    BG_COLORCODE = DEFAULT_BG_COLOR_CODE;
                    break;

                case VT100CHARATTR_BOLD:
                    bold=1;
                    break;
		case VT100CHARATTR_NORMAL:
                    bold=0;
		    break;
                case VT100CHARATTR_UNDER:
                    under=1;
                    break;
		case VT100CHARATTR_NOT_UNDER:
                    under=0;
		    break;
                case VT100CHARATTR_BLINK:
                    blink=1;
                    break;
		case VT100CHARATTR_STEADY:
                    blink=0;
		    break;
                case VT100CHARATTR_REVERSE:
                    reversed=1;
                    break;
		case VT100CHARATTR_POSITIVE:
                    reversed=0;
		    break;
                case VT100CHARATTR_FG_DEFAULT:
                    FG_COLORCODE = DEFAULT_FG_COLOR_CODE;
                    break;
                case VT100CHARATTR_BG_DEFAULT:
                    BG_COLORCODE = DEFAULT_BG_COLOR_CODE;
                    break;
                default:
                    if (n>=VT100CHARATTR_FG_BLACK&&n<=VT100CHARATTR_FG_WHITE) {
                        FG_COLORCODE = n - VT100CHARATTR_FG_BASE - COLORCODE_BLACK;
                    }
                    else if (n>=VT100CHARATTR_BG_BLACK&&n<=VT100CHARATTR_BG_WHITE) {
                        BG_COLORCODE = n - VT100CHARATTR_BG_BASE - COLORCODE_BLACK;
                    }
                }
            }
        }

	// reset our default character attributes
	[self setCharacterAttributeDictionary];
    }
}

- (void) setFGColor:(NSColor*)color
{
    [defaultFGColor release];
    defaultFGColor=[color copy];
    // reset our default character attributes
    [defaultCharacterAttributeDictionary[0] setObject:color forKey:(SCREEN_MODE?NSBackgroundColorAttributeName:NSForegroundColorAttributeName)];
    
    [defaultCharacterAttributeDictionary[1] setObject:color forKey:(SCREEN_MODE?NSBackgroundColorAttributeName:NSForegroundColorAttributeName)];
    
    [characterAttributeDictionary[0] setObject:color forKey:(SCREEN_MODE?NSBackgroundColorAttributeName:NSForegroundColorAttributeName)];
    
    [characterAttributeDictionary[1] setObject:color forKey:(SCREEN_MODE?NSBackgroundColorAttributeName:NSForegroundColorAttributeName)];

    [SCREEN setScreenAttributes];
    
}

- (void) setBGColor:(NSColor*)color
{
    [defaultBGColor release];
    defaultBGColor=[color copy];

    // reset our default character attributes
    if (SCREEN_MODE) {
        [defaultCharacterAttributeDictionary[0] setObject:color
                                                   forKey:NSForegroundColorAttributeName];
        [defaultCharacterAttributeDictionary[1] setObject:color
                                                   forKey:NSForegroundColorAttributeName];
        [characterAttributeDictionary[0] setObject:color
                                            forKey:NSForegroundColorAttributeName];
        [characterAttributeDictionary[1] setObject:color
                                            forKey:NSForegroundColorAttributeName];
    }

    [SCREEN setScreenAttributes];

}

- (void) setBoldColor: (NSColor*)color
{
    [defaultBoldColor release];
    defaultBoldColor=[color copy];
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
    [colorTable[hili?1:0][index] release];
    colorTable[hili?1:0][index]=[c copy];
}

- (void) setScreen:(VT100Screen*) sc
{
    SCREEN=sc;
}

- (NSColor *) colorFromTable:(int) index bold:(BOOL) b
{
    NSColor *color;

    if (index==DEFAULT_FG_COLOR_CODE)
    {
	if(b)
	{
	    color = [self defaultBoldColor];
	}
	else
	{
	    color=(SCREEN_MODE?defaultBGColor:defaultFGColor);
	}
    }
    else if (index==DEFAULT_BG_COLOR_CODE)
    {
	if(b)
	{
	    color = [self defaultBoldColor];
	}
	else
	{
	    color=(SCREEN_MODE?defaultFGColor:defaultBGColor);
	}
    }
    else
    {
        color=colorTable[b?1:0][index];
    }

    return color;
    
}

@end
