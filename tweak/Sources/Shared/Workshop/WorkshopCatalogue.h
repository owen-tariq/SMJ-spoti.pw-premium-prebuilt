// SPDX-License-Identifier: MIT
// The Workshop (WorkshopPage.m): a small catalogue of downloadable DATA files, installed into the local Library
// with one tap. It stands in for a closed server with a plain JSON index on a static HTTPS host, by default this
// repo's workshop/ folder (workshop/README.md has the schema and the rules).
//
//     WorkshopValidate.h     the checks as plain C (addresses, names, ranges, GraphicEQ text), tested by the harness
//     WorkshopCatalogue.m    the fetch, the validation of what came back, the install and the installed index
//     WorkshopPage.m         the page
//
// Safety: data only (looks, EQ gains, GraphicEQ text), https only, hard caps, sha256 and size checked before
// anything is stored, no URL inside a file is ever followed.
//
// Threading: the fetch and install functions are called on the main queue and answer on it; the rest is any thread.
#import <Foundation/Foundation.h>

#define SGKeyWorkshopBaseURL @"spotifyglass.workshop.baseURL"

typedef NS_ENUM(NSInteger, SGWorkshopType) {
    SGWorkshopTypeLook,        // visualizer look  -> Library/Looks through SGLibrarySaveLook
    SGWorkshopTypeEQ,          // 15 band EQ gains -> Library/Workshop/<id>.eq.json
    SGWorkshopTypeCorrection,  // GraphicEQ line   -> Library/Workshop/<id>.geq.txt
};

@interface SGWorkshopItem : NSObject
@property (nonatomic, readonly) SGWorkshopType type;
@property (nonatomic, readonly, copy) NSString *itemID, *name, *author, *summary, *file, *sha256;
@property (nonatomic, readonly) NSUInteger size;
@end

typedef NS_ENUM(NSInteger, SGWorkshopState) {
    SGWorkshopStateAvailable,
    SGWorkshopStateInstalled,
    SGWorkshopStateUpdate,     // installed, but the catalogue's sha256 differs
};

extern NSErrorDomain const SGWorkshopErrorDomain;
typedef NS_ENUM(NSInteger, SGWorkshopErrorCode) {
    SGWorkshopErrorOffline = 1,
    SGWorkshopErrorUnreadable,   // the catalogue could not be read
    SGWorkshopErrorRefused,      // a file failed a check
    SGWorkshopErrorNetwork,
};

NSString *SGWorkshopDefaultBaseURL(void);
// The address in use: the stored one, or the default; always ends in "/".
NSString *SGWorkshopBaseURL(void);
// Stores an address (empty resets to the default). Answers what is wrong with it, or nil once stored.
NSString *SGWorkshopSetBaseURL(NSString *text);
BOOL SGWorkshopUsesDefaultBaseURL(void);

// Parses an index (not the network): items that pass every check, in file order. Nil and an error when the
// index is too big, not JSON, not version 1 or lists over 200 items. `skipped` counts items dropped for
// failing a check (may be NULL).
NSArray<SGWorkshopItem *> *SGWorkshopParseIndex(NSData *data, NSUInteger *skipped, NSError **error);
// Checks a downloaded file against its item: size, sha256, then its content as its type's data. On success
// `payload` is an NSDictionary (look), an NSArray of 15 numbers (eq) or the cleaned NSString (correction).
BOOL SGWorkshopValidatePayload(SGWorkshopItem *item, NSData *data, id *payload, NSError **error);

// Network; answer on the main queue.
void SGWorkshopFetchIndex(void (^done)(NSArray<SGWorkshopItem *> *items, NSUInteger skipped, NSError *error));
void SGWorkshopInstall(SGWorkshopItem *item, void (^done)(NSError *error));

// What is installed, by the plist under Application Support/spoti.pw/Library/workshop-installed.plist.
SGWorkshopState SGWorkshopStateOf(SGWorkshopItem *item);
// Removes the item's file from the Library (SGLibraryDeleteLook or the Workshop shelf) and its entry.
BOOL SGWorkshopRemove(SGWorkshopItem *item);
// Whether a Library look of that name exists that the Workshop did not install (installing would replace it).
BOOL SGWorkshopWouldReplaceOwnLook(SGWorkshopItem *item);
// Sets an installed eq / correction as the sound: the 15 band equalizer's gains or the Graphic EQ's line, and
// switches that effect on. Answers an error when the file is gone or no longer valid. Main thread.
BOOL SGWorkshopUse(SGWorkshopItem *item, NSError **error);
