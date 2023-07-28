#pragma ONCE

#ifdef MSDFGEN_IMPL_CPP

#define BODY(x) x

#include "msdfgen/msdfgen.h"
#include "msdfgen/msdfgen-ext.h"

using namespace msdfgen;

extern "C" {

#else

#define BODY(x) ;
typedef struct FreeTypeHandle FreeTypeHandle;
typedef struct FontHandle FontHandle;
typedef struct GlyphIndex GlyphIndex;
typedef struct Shape Shape;

#endif

FreetypeHandle* cz_initializeFreetype(void) BODY({
    return initializeFreetype();
})
void cz_deinitializeFreetype(FreetypeHandle* ft) BODY({
    return deinitializeFreetype(ft);
})
FontHandle* cz_loadFontData(FreeTypeHandle* ft, byte* data, int length) BODY({
    return loadFontData(ft, data, length);
})
void cz_destroyFont(FreeTypeHandle* ft) BODY({
    return destroyFont(ft);
})
bool cz_getGlyphIndex(GlyphIndex* glyphIndex, FontHandle* font, unicode_t unicode) BODY({
    return getGlyphIndex(&glyphIndex, font, unicode);
})
bool cz_loadGlyph(Shape* output, FontHandle* font, unicode_t unicode, double* advance) BODY({
    return loadGlyph(output, font, unicode, advance);
})

#if false
int main() BODY({
    FreetypeHandle *ft = initializeFreetype();
    if (ft) {
        FontHandle *font = loadFont(ft, "C:\\Windows\\Fonts\\arialbd.ttf");
        if (font) {
            Shape shape;
            if (loadGlyph(shape, font, 'A')) {
                shape.normalize();
                //                      max. angle
                edgeColoringSimple(shape, 3.0);
                //           image width, height
                Bitmap<float, 3> msdf(32, 32);
                //                     range, scale, translation
                generateMSDF(msdf, shape, 4.0, 1.0, Vector2(4.0, 4.0));
                savePng(msdf, "output.png");
            }
            destroyFont(font);
        }
        deinitializeFreetype(ft);
    }
    return 0;
})
#endif




#ifdef MSDFGEN_IMPL_CPP
}
#endif
