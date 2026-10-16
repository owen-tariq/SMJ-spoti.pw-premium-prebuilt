// SPDX-License-Identifier: MIT
// The Library's shelves (Library.h): where each lives, and importing into, listing and deleting from each.
// LibraryPage.m is their one UI; the visualizer reads and writes looks through the Looks functions.
//
// Threading: any thread. The import of a model copies hundreds of megabytes, so the page calls it off the
// main thread; the rest is small. The notifications of Library.h are posted on the main queue.
#import <Foundation/Foundation.h>

#pragma mark - fonts

// The shelf's directory, made on first ask.
NSString *SGLibraryFontsDirectory(void);
// The font files on the shelf, sorted by name.
NSArray<NSString *> *SGLibraryFontFiles(void);
// The families a file on the shelf carries (one, nearly always); empty for one CoreText would not read.
NSArray<NSString *> *SGLibraryFontFamiliesOf(NSString *file);
// Copies a picked .ttf or .otf in (replacing one of the same name) and registers it; answers its name, or
// nil and an error when CoreText would not take it (the copy is removed again).
NSString *SGLibraryImportFont(NSURL *url, NSError **error);
// Unregisters and deletes a file of the shelf.
BOOL SGLibraryDeleteFont(NSString *file);
// Registers every file of the shelf with CoreText for this process, once; a launch does this in the
// background, and SGLibraryFontFamilies waits for it.
void SGLibraryRegisterFonts(void);

#pragma mark - looks

NSString *SGLibraryLooksDirectory(void);
// The looks on the shelf, by name (the file name without .json), sorted.
NSArray<NSString *> *SGLibraryLookNames(void);
NSURL *SGLibraryLookURL(NSString *name);
// The dictionary a look holds, nil when there is no such look or the file is not a JSON object.
NSDictionary<NSString *, id> *SGLibraryLook(NSString *name);
// Writes a look (any JSON-serializable dictionary) under a name, replacing one of that name; posts the change.
BOOL SGLibrarySaveLook(NSString *name, NSDictionary<NSString *, id> *look, NSError **error);
// Copies a picked .json in: it has to parse as an object. Answers the look's name, or nil and an error.
NSString *SGLibraryImportLook(NSURL *url, NSError **error);
BOOL SGLibraryDeleteLook(NSString *name);

#pragma mark - the custom Sing model

// Where an imported model goes: .../spoti.pw/Sing/Custom/separator.mlmodelc.
NSURL *SGLibraryCustomSingModelFolder(void);
// Whether the folder at `url` is a compiled Core ML model as far as the Library checks: model.mil or
// coremldata.bin inside it.
BOOL SGLibraryLooksLikeModel(NSURL *url);
// Whether an imported model is in place (whatever the switch says).
BOOL SGLibraryHasCustomSingModel(void);
// The imported model's size on disk, 0 without one.
int64_t SGLibraryCustomSingModelSize(void);
// Imports what the picker handed over: a folder that is the model or holds one, or a .zip holding one. Copies
// (or extracts) into the custom folder, replacing what was there, and posts the change. Slow: call it off
// the main thread. Answers NO and an error when nothing in it is a model.
BOOL SGLibraryImportSingModel(NSURL *url, NSError **error);
// Deletes the imported model and posts the change.
void SGLibraryRemoveCustomSingModel(void);
