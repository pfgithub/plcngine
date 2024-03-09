#pragma once

#include "stdint.h"
#include "stdbool.h"

#ifdef __cplusplus
#include "msdfgen.h"
#include "ext/import-font.h"
using namespace msdfgen;
#else
typedef struct FreetypeHandle FreetypeHandle;
typedef struct FontHandle FontHandle;
typedef struct GlyphIndex GlyphIndex;
#endif

typedef struct cz_Bitmap3f cz_Bitmap3f;
typedef struct cz_Shape cz_Shape;

#ifdef __cplusplus
extern "C" {
#endif

FreetypeHandle* cz_initializeFreetype(void);
void cz_deinitializeFreetype(FreetypeHandle* ft);
FontHandle* cz_loadFontData(FreetypeHandle* ft, const uint8_t* data, int length);
void cz_destroyFont(FontHandle* ft);
bool cz_loadGlyph(cz_Shape* output, FontHandle* font, uint32_t unicode, double* advance);

cz_Bitmap3f* cz_createBitmap3f(int width, int height);
void cz_destroyBitmap3f(cz_Bitmap3f* bitmap);
float* cz_bitmap3fPixels(cz_Bitmap3f* bitmap);
int cz_bitmap3fWidth(cz_Bitmap3f* bitmap);
int cz_bitmap3fHeight(cz_Bitmap3f* bitmap);

cz_Shape* cz_createShape();
void cz_destroyShape(cz_Shape* shape);
void cz_shapeNormalize(cz_Shape* shape);
void cz_edgeColoringSimple(cz_Shape* shape, float max_angle);

void cz_generateMSDF(cz_Bitmap3f* bitmap, const cz_Shape* shape, double scale_x, double scale_y, double translate_x, double translate_y, double range);

#ifdef __cplusplus
}
#endif
