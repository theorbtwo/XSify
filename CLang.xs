#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include <clang-c/Index.h>

/* This is hopefully still C code that xsubpp won't muck with. */

enum CXChildVisitResult my_visitor(CXCursor cursor, CXCursor parent, CXClientData client_data) {
  dSP;
  int return_count;
  SV *cursor_sv;
  SV *parent_sv;
  enum CXChildVisitResult result;

  ENTER;
  SAVETMPS;
  
  PUSHMARK(SP);

  cursor_sv = sv_newmortal();
  sv_setref_pvn(cursor_sv, "CLang::Cursor", (const char *)&cursor, sizeof(CXCursor));
  XPUSHs(cursor_sv);

  parent_sv = sv_newmortal();
  sv_setref_pvn(parent_sv, "CLang::Cursor", (const char *)&parent, sizeof(CXCursor));
  XPUSHs(parent_sv);

  PUTBACK;

  return_count = call_sv((SV*)client_data, G_SCALAR);

  SPAGAIN;

  if (return_count != 1)
    croak("WTF: call_pv G_SCALAR didn't return one item, but %d", return_count);

  result = POPi;

  // warn("Result from visitor is %d\n", result);

  PUTBACK;
  FREETMPS;
  LEAVE;  

  return result;
}

MODULE = CLang::Index   PACKAGE = CLang::Index  PREFIX = clang_

PROTOTYPES: DISABLE

CXIndex
clang_createIndex(int excludeDeclarationsFromPCH = 0, int displayDiagnostics = 1);

void
clang_disposeIndex(CXIndex index);

CXTranslationUnit
clang_parseTranslationUnit(CXIndex CIdx, const char *source_filename, const char * const * command_line_args, int num_command_line_args, struct CXUnsavedFile *unsaved_files, unsigned num_unsaved_files, unsigned options);

MODULE = CLang::TranslationUnit   PACKAGE = CLang::TranslationUnit  PREFIX = clang_

void
clang_disposeTranslationUnit(CXTranslationUnit tu);

CXCursor
clang_getTranslationUnitCursor(CXTranslationUnit tu);

MODULE = Clang::Cursor  PACKAGE = CLang::Cursor  PREFIX = clang_

void
visitChildren(CXCursor cursor, CV* callback)
  CODE:
    clang_visitChildren(cursor, my_visitor, (CXClientData)callback);

CXString
clang_getCursorUSR(CXCursor cursor);

int
clang_getCursorKind(CXCursor cursor);

CXType
clang_getCursorType(CXCursor cursor);

CXSourceLocation
clang_getCursorLocation(CXCursor cursor);

CXSourceRange
clang_getCursorExtent(CXCursor cursor);

CXString
clang_getCursorSpelling(CXCursor cursor);

CXType
clang_getCursorResultType(CXCursor cursor);

int
clang_getCXXAccessSpecifier(CXCursor cursor);

CXCursor
clang_getCursorSemanticParent(CXCursor cursor);

MODULE = CLang::String  PACKAGE = CLang::String  PREFIX = clang_

void
clang_disposeString(CXString string);

const char*
clang_getCString(CXString string);

MODULE = CLang::Type   PACKAGE = CLang::Type  PREFIX = clang_

int
clang_isConstQualifiedType(CXType T);

CXCursor
clang_getTypeDeclaration(CXType T);

CXType
clang_getCanonicalType(CXType T);

int
getTypeKind(CXType type)
 CODE:
  /* Somewhat odd that there isn't a "better" way to do this. */
  RETVAL = (int)type.kind;
 OUTPUT:
  RETVAL

CXType
clang_getPointeeType(CXType type);

CXType
clang_getArrayElementType(CXType T);

UV
clang_getArraySize(CXType T);

MODULE = CLang::SourceLocation    PACKAGE = CLang::SourceLocation   PREFIX = clang_

SV*
getPresumedLocationFilename(CXSourceLocation location)
 CODE:
  CXString string;
  clang_getPresumedLocation(location, &string, NULL, NULL);
  RETVAL = newSV(0);
  sv_setref_pvn(RETVAL, "CLang::String", (const char *)&string, sizeof(string));
 OUTPUT:
  RETVAL

unsigned
getPresumedLocationLine(CXSourceLocation location)
 CODE:
  clang_getPresumedLocation(location, NULL, &RETVAL, NULL);
 OUTPUT:
  RETVAL

MODULE = CLang::SourceRange   PACKAGE = CLang::SourceRange

CXSourceLocation
clang_getRangeStart(CXSourceRange range);

CXSourceLocation
clang_getRangeEnd(CXSourceRange range);



MODULE = CLang   PACKAGE = CLang

